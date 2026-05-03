output "profile_name_ec2" {
  value = aws_iam_instance_profile.ec2.name
}
output "arn_gha_deploy" {
  value = aws_iam_role.gha_deploy.arn
}
