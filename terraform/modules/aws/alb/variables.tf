variable "env" {}
variable "vpc_id" { type = string }

variable "alb" {
  type = object({
    security_group_id = string
    subnet_id_1a      = string
    subnet_id_1c      = string
    certificate_arn   = string
  })
}
