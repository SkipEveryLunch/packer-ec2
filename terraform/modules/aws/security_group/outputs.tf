output "id_alb" {
  value = aws_security_group.alb.id
}
output "id_ec2" {
  value = aws_security_group.ec2.id
}
output "id_aurora" {
  value = aws_security_group.aurora.id
}
