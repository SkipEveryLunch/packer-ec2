variable "env" {}

variable "asg" {
  type = object({
    instance_profile_name = string
    security_group_id     = string
    subnet_id_1a          = string
    subnet_id_1c          = string
    target_group_arn      = string
  })
}
