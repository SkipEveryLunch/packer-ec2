data "aws_route53_zone" "main" {
  name = local.domain
}

data "aws_acm_certificate" "main" {
  domain      = "*.${local.domain}"
  statuses    = ["ISSUED"]
  most_recent = true
}
