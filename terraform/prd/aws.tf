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
  source  = "../modules/aws/alb"
  env     = local.env
  vpc_id  = module.vpc.id_app
  alb = {
    security_group_id = module.security_group.id_alb
    subnet_id_1a      = module.subnet.id_public_1a
    subnet_id_1c      = module.subnet.id_public_1c
    certificate_arn   = data.aws_acm_certificate.main.arn
  }
}

resource "aws_route53_record" "app" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = local.domain
  type    = "A"
  alias {
    name                   = module.alb.dns_name_app
    zone_id                = module.alb.zone_id_app
    evaluate_target_health = true
  }
}
