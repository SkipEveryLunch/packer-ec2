variable "account_id" {}
variable "domain" {}
variable "profile" {}

locals {
  env    = "prd"
  region = "ap-northeast-1"
  domain = var.domain
}
