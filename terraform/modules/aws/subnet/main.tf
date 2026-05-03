resource "aws_subnet" "public_1a" {
  vpc_id                  = var.vpc_id
  cidr_block              = "10.0.0.0/24"
  availability_zone       = "ap-northeast-1a"
  map_public_ip_on_launch = true
  tags = {
    Name = "public-1a-${var.env}"
  }
}

resource "aws_subnet" "public_1c" {
  vpc_id                  = var.vpc_id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-northeast-1c"
  map_public_ip_on_launch = true
  tags = {
    Name = "public-1c-${var.env}"
  }
}

resource "aws_subnet" "private_1a" {
  vpc_id                  = var.vpc_id
  cidr_block              = "10.0.10.0/24"
  availability_zone       = "ap-northeast-1a"
  map_public_ip_on_launch = false
  tags = {
    Name = "private-1a-${var.env}"
  }
}

resource "aws_subnet" "private_1c" {
  vpc_id                  = var.vpc_id
  cidr_block              = "10.0.11.0/24"
  availability_zone       = "ap-northeast-1c"
  map_public_ip_on_launch = false
  tags = {
    Name = "private-1c-${var.env}"
  }
}
