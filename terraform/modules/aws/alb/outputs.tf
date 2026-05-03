output "arn_target_group_app" {
  value = aws_lb_target_group.app.arn
}
output "dns_name_app" {
  value = aws_lb.app.dns_name
}
output "zone_id_app" {
  value = aws_lb.app.zone_id
}
