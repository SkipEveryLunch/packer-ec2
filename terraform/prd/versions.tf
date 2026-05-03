terraform {
  required_version = "~> 1.11.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.5.0"
    }
  }
}

provider "aws" {
  region  = "ap-northeast-1"
  profile = var.profile
  default_tags {
    tags = {
      Env = "prd"
    }
  }
}
