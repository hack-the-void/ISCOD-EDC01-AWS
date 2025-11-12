########################################
# Locals
########################################

locals {
  project_name = "MediTrack"   # Nom du projet
  vpc_cidr     = "10.0.0.0/16" # Plage d'adresses du VPC
  subnet_cidr  = "10.0.1.0/24" # Plage d'adresses du subnet public
}

########################################
# Réseau avec le VPC
########################################

# - CREATION DU VPC :
resource "aws_vpc" "main" {
  cidr_block           = local.vpc_cidr # Plage d'adresses du VPC
  enable_dns_support   = true           # Résolution DNS Interne
  enable_dns_hostnames = true           # pour avoir des noms DNS sur les instances

  tags = {
    Name = "${local.project_name}-VPC"
  }
}

# - SUBNET PUBLIC - La partie des ressources exposée
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id   # Je rattache au VPC
  cidr_block              = local.subnet_cidr # plage d'adresse du subnet
  map_public_ip_on_launch = true              # pour avoir une ip publique sur l'instance

  tags = {
    Name = "${local.project_name}-Public-Subnet"
  }
}

resource "aws_internet_gateway" "gw" { # Gateway pour sortir sur internet
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.project_name}-IGW"
  }
}

resource "aws_route_table" "public" { # Table de routage
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id # Je route tout le trafic (0.0.0.0/0) vers Internet
  }

  tags = {
    Name = "${local.project_name}-RouteTable"
  }
}

resource "aws_route_table_association" "public_assoc" { # Association entre le subnet public et la route public
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

########################################
# S3
########################################

resource "aws_s3_bucket" "website" { # Bucket S3 qui stock les fichiers du site
  bucket = "meditrack-site-1f6ea17b"

  force_destroy = true # Pour forcer la destruction du bucket même s'il y a des choses dedans

  tags = {
    Name = "${local.project_name}-Site"
  }
}

# Chiffrement serveur SSE pour le S3
resource "aws_s3_bucket_server_side_encryption_configuration" "website" {
  bucket = aws_s3_bucket.website.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256" # Chiffrement géré par AWS
    }
  }
}

########################################
# CloudFront
########################################

# Origin Access Control : permet a CloudFront d'accéder au S3 en privé
resource "aws_cloudfront_origin_access_control" "oac" {
  name                              = "${local.project_name}-OAC"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
  description                       = "OAC for ${local.project_name} static site"
}

# Distribution CloudFront CDN qui cache et sert le site
resource "aws_cloudfront_distribution" "cdn" {
  origin {
    domain_name              = aws_s3_bucket.website.bucket_regional_domain_name
    origin_id                = "s3-${local.project_name}"
    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
  }

  enabled             = true
  default_root_object = "index.html"

  # Comportement par défaut du cache
  default_cache_behavior {
    target_origin_id       = "s3-${local.project_name}"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]

    forwarded_values {
      query_string = false # Ne pas forward les query strings à l'origine

      cookies {
        forward = "none" # Ne pas transmettre les cookies
      }
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true # Certificat par défault Cloudfront
  }

  restrictions {
    geo_restriction {
      restriction_type = "none" # Pas de restriction géographique
    }
  }

  tags = {
    Name = "${local.project_name}-CDN"
  }
}

# Policy S3 qui autorise CloudFront à lire dans le bucket
resource "aws_s3_bucket_policy" "website" {
  bucket = aws_s3_bucket.website.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontRead"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com" # Service CloudFront
        }
        Action   = ["s3:GetObject"]                 # Lecture des objets
        Resource = "${aws_s3_bucket.website.arn}/*" # sur tout le contenu du bucket
      }
    ]
  })
}

########################################
# IAM
########################################

resource "aws_iam_role" "ec2_s3_role" {
  name = "${local.project_name}-EC2-S3-Role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${local.project_name}-EC2-S3-Role"
  }
}

resource "aws_iam_role_policy" "ec2_s3_policy" {
  name = "${local.project_name}-EC2-S3-Policy"
  role = aws_iam_role.ec2_s3_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.website.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [
          "${aws_s3_bucket.website.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2_s3_profile" {
  name = "${local.project_name}-EC2-S3-Profile"
  role = aws_iam_role.ec2_s3_role.name
}

########################################
# EC2 + SG
########################################

# pare-feu du VPC
resource "aws_security_group" "web_sg" {
  vpc_id = aws_vpc.main.id

  # SSH ouvert à tous mais uniquement avec clé SSH (si j'avais une ip publique fixe, j'aurais autorisé que celle-ci)
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Autoriser tout le traffic vers l'extérieur
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.project_name}-Web-SG"
  }
}

#  Création de l'EC2
resource "aws_instance" "web" {
  ami           = "ami-00c71bd4d220aa22a"
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.public.id
  key_name      = "mediTrack-key"

  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.web_sg.id]

  iam_instance_profile = aws_iam_instance_profile.ec2_s3_profile.name

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
    encrypted   = true
  }

  tags = {
    Name = "${local.project_name}-Web"
  }
}

# Pour push l'IP public dans le fichier inventory
resource "local_file" "ansible_inventory" {
  content = <<EOF
[web]
${aws_instance.web.public_ip} ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/meditrack-key
EOF

  filename = "${path.module}/../ansible/inventory.ini"
}