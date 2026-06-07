// 箱のみ。値（version）は作らず手動投入する
//   aws secretsmanager put-secret-value --secret-id ec2-packer/${env}/app-env \
//     --secret-string '{"SECRET_KEY_BASE":"..."}'
resource "aws_secretsmanager_secret" "app_env" {
  name                    = "ec2-packer/${var.env}/app-env"
  recovery_window_in_days = 0 // 実験PJ: 即時削除可
}
