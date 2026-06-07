variable "env" {}
variable "account_id" { type = string }
variable "oidc_github_actions_arn" { type = string }
variable "github_repo" { type = string } // "org/repo" 形式
variable "secret_app_env_arn" { type = string }
