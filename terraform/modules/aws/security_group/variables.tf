variable "env" {}
variable "vpc_id" { type = string }

locals {
  default_egress = [
    {
      description      = ""
      cidr_blocks      = ["0.0.0.0/0"]
      from_port        = 0
      to_port          = 0
      protocol         = "-1"
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      security_groups  = []
      self             = false
    },
  ]
}
