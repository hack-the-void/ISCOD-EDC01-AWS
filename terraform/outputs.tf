output "bucket_name" {
  value = aws_s3_bucket.website.bucket
}

output "cloudfront_domain" {
  value = aws_cloudfront_distribution.cdn.domain_name
}

output "web_public_ip" {
  description = "IP publique du serveur web"
  value       = aws_instance.web.public_ip
}