variable "account_id" {}
variable "domain" {}
variable "profile" {}
variable "github_repo" {} // "org/repo" 形式

locals {
  env    = "prd"
  region = "ap-northeast-1"
  domain = var.domain
}
