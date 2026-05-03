/************************************************************
SSM parameter (initial placeholder, overwritten by Packer)
************************************************************/
resource "aws_ssm_parameter" "ami_id" {
  name  = "/ec2-packer/${var.env}/ami-id"
  type  = "String"
  value = "ami-023ff3d4ab11b2525" // AL2023 default
  lifecycle {
    ignore_changes = [value]
  }
}

/************************************************************
SSM parameters (for GHA deploy pipeline)
************************************************************/
resource "aws_ssm_parameter" "launch_template_id" {
  name  = "/ec2-packer/${var.env}/launch-template-id"
  type  = "String"
  value = aws_launch_template.app.id
}

resource "aws_ssm_parameter" "asg_name" {
  name  = "/ec2-packer/${var.env}/asg-name"
  type  = "String"
  value = aws_autoscaling_group.app.name
}

/************************************************************
launch template
************************************************************/
resource "aws_launch_template" "app" {
  name          = "app-${var.env}"
  image_id      = aws_ssm_parameter.ami_id.value
  instance_type = "t3.small"

  iam_instance_profile {
    name = var.asg.instance_profile_name
  }

  vpc_security_group_ids = [var.asg.security_group_id]

  user_data = base64encode(<<-EOT
    #!/bin/bash
    echo "RAILS_ENV=production" | tee -a /etc/environment
    systemctl restart puma
  EOT
  )

  lifecycle {
    ignore_changes = [image_id]
  }
}

/************************************************************
auto scaling group
************************************************************/
resource "aws_autoscaling_group" "app" {
  name                      = "app-${var.env}"
  min_size                  = 1
  max_size                  = 2
  desired_capacity          = 1
  vpc_zone_identifier       = [var.asg.subnet_id_1a, var.asg.subnet_id_1c]
  target_group_arns         = [var.asg.target_group_arn]
  health_check_type         = "ELB"
  health_check_grace_period = 300

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Default"
  }

  lifecycle {
    ignore_changes = [desired_capacity]
  }
}
