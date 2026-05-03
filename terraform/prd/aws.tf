module "vpc" {
  source = "../modules/aws/vpc"
  env    = local.env
}

module "subnet" {
  source = "../modules/aws/subnet"
  env    = local.env
  vpc_id = module.vpc.id_app
}

module "internet_gateway" {
  source = "../modules/aws/internet_gateway"
  env    = local.env
  vpc_id = module.vpc.id_app
}

module "route_table" {
  source               = "../modules/aws/route_table"
  env                  = local.env
  vpc_id               = module.vpc.id_app
  internet_gateway_id  = module.internet_gateway.id_app
  public_subnet_id_1a  = module.subnet.id_public_1a
  public_subnet_id_1c  = module.subnet.id_public_1c
  private_subnet_id_1a = module.subnet.id_private_1a
  private_subnet_id_1c = module.subnet.id_private_1c
}

module "security_group" {
  source = "../modules/aws/security_group"
  env    = local.env
  vpc_id = module.vpc.id_app
}

module "alb" {
  source = "../modules/aws/alb"
  env    = local.env
  vpc_id = module.vpc.id_app
  alb = {
    security_group_id = module.security_group.id_alb
    subnet_id_1a      = module.subnet.id_public_1a
    subnet_id_1c      = module.subnet.id_public_1c
    certificate_arn   = data.aws_acm_certificate.main.arn
  }
}

module "asg" {
  source = "../modules/aws/asg"
  env    = local.env
  asg = {
    instance_profile_name = module.iam_role.profile_name_ec2
    security_group_id     = module.security_group.id_ec2
    subnet_id_1a          = module.subnet.id_public_1a
    subnet_id_1c          = module.subnet.id_public_1c
    target_group_arn      = module.alb.arn_target_group_app
  }
}

module "oidc_github_actions" {
  source = "../modules/aws/oidc_github_actions"
}

module "iam_role" {
  source                  = "../modules/aws/iam_role"
  env                     = local.env
  account_id              = var.account_id
  oidc_github_actions_arn = module.oidc_github_actions.arn
  github_repo             = var.github_repo
}

resource "aws_route53_record" "app" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = local.api_fqdn
  type    = "A"
  alias {
    name                   = module.alb.dns_name_app
    zone_id                = module.alb.zone_id_app
    evaluate_target_health = true
  }
}
