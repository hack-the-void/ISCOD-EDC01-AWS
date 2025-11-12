terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.profile

  assume_role {
    role_arn     = "arn:aws:iam::083756035245:role/MediTrack-Terraform-Role"
    session_name = "terraform-meditrack"
  }
}