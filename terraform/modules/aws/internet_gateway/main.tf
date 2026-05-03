resource "aws_internet_gateway" "app" {
  vpc_id = var.vpc_id
  tags = {
    Name = "igw-${var.env}"
  }
}
