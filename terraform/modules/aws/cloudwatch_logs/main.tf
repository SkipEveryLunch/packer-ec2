resource "aws_cloudwatch_log_group" "app" {
  name              = "/ec2-packer/${var.env}/app"
  retention_in_days = 30
}
