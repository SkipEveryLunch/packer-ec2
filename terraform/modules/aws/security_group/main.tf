/************************************************************
alb
************************************************************/
resource "aws_security_group" "alb" {
  name   = "alb-${var.env}"
  vpc_id = var.vpc_id
  tags = {
    Name = "alb-${var.env}"
  }
  ingress = [
    {
      description      = ""
      cidr_blocks      = ["0.0.0.0/0"]
      from_port        = 80
      to_port          = 80
      protocol         = "tcp"
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      security_groups  = []
      self             = false
    },
    {
      description      = ""
      cidr_blocks      = ["0.0.0.0/0"]
      from_port        = 443
      to_port          = 443
      protocol         = "tcp"
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      security_groups  = []
      self             = false
    },
  ]
  egress = local.default_egress
}

/************************************************************
ec2
************************************************************/
resource "aws_security_group" "ec2" {
  name   = "ec2-${var.env}"
  vpc_id = var.vpc_id
  tags = {
    Name = "ec2-${var.env}"
  }
  ingress = [
    {
      description      = ""
      cidr_blocks      = []
      from_port        = 3000
      to_port          = 3000
      protocol         = "tcp"
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      security_groups  = [aws_security_group.alb.id]
      self             = false
    },
  ]
  egress = local.default_egress
}

/************************************************************
aurora
************************************************************/
resource "aws_security_group" "aurora" {
  name   = "aurora-${var.env}"
  vpc_id = var.vpc_id
  tags = {
    Name = "aurora-${var.env}"
  }
  ingress = [
    {
      description      = ""
      cidr_blocks      = []
      from_port        = 5432
      to_port          = 5432
      protocol         = "tcp"
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      security_groups  = [aws_security_group.ec2.id]
      self             = false
    },
  ]
  egress = local.default_egress
}
