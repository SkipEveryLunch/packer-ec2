output "profile_name_ec2" {
  value = aws_iam_instance_profile.ec2.name
}
output "arn_gha_build_base" {
  value = aws_iam_role.gha_build_base.arn
}
output "arn_gha_build_app" {
  value = aws_iam_role.gha_build_app.arn
}
output "arn_gha_deploy" {
  value = aws_iam_role.gha_deploy.arn
}
