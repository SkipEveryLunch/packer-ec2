/************************************************************
EC2 instance role
************************************************************/
resource "aws_iam_role" "ec2" {
  name = "ec2-app-${var.env}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ec2" {
  for_each = {
    ssm          = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    secrets_read = aws_iam_policy.secrets_read.arn
    cw_agent     = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  }
  role       = aws_iam_role.ec2.name
  policy_arn = each.value
}

resource "aws_iam_instance_profile" "ec2" {
  name = "ec2-app-${var.env}"
  role = aws_iam_role.ec2.name
}

/************************************************************
GHA deploy role
************************************************************/
resource "aws_iam_role" "gha_deploy" {
  name = "gha-deploy-${var.env}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRoleWithWebIdentity"
      Principal = {
        Federated = var.oidc_github_actions_arn
      }
      Condition = {
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:ref:refs/heads/main"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "gha_deploy" {
  for_each = {
    packer_build = aws_iam_policy.packer_build.arn
    asg_refresh  = aws_iam_policy.asg_refresh.arn
    ssm_params   = aws_iam_policy.ssm_params.arn
  }
  role       = aws_iam_role.gha_deploy.name
  policy_arn = each.value
}

/************************************************************
custom policies
************************************************************/
resource "aws_iam_policy" "packer_build" {
  name = "packer-build-${var.env}"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ec2:AttachVolume",
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:CopyImage",
        "ec2:CreateImage",
        "ec2:CreateKeyPair",
        "ec2:CreateSecurityGroup",
        "ec2:CreateSnapshot",
        "ec2:CreateTags",
        "ec2:CreateVolume",
        "ec2:DeleteKeyPair",
        "ec2:DeleteSecurityGroup",
        "ec2:DeleteSnapshot",
        "ec2:DeleteVolume",
        "ec2:DeregisterImage",
        "ec2:DescribeImageAttribute",
        "ec2:DescribeImages",
        "ec2:DescribeInstances",
        "ec2:DescribeInstanceStatus",
        "ec2:DescribeRegions",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeSnapshots",
        "ec2:DescribeSubnets",
        "ec2:DescribeTags",
        "ec2:DescribeVolumes",
        "ec2:DetachVolume",
        "ec2:GetPasswordData",
        "ec2:ModifyImageAttribute",
        "ec2:ModifyInstanceAttribute",
        "ec2:ModifySnapshotAttribute",
        "ec2:RegisterImage",
        "ec2:RunInstances",
        "ec2:StopInstances",
        "ec2:TerminateInstances",
        "iam:PassRole",
      ]
      Resource = "*"
    }]
  })
}

resource "aws_iam_policy" "asg_refresh" {
  name = "asg-refresh-${var.env}"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ec2:CreateLaunchTemplateVersion",
        "ec2:ModifyLaunchTemplate",
        "ec2:DescribeLaunchTemplates",
        "ec2:DescribeLaunchTemplateVersions",
        "autoscaling:UpdateAutoScalingGroup",
        "autoscaling:StartInstanceRefresh",
        "autoscaling:DescribeInstanceRefreshes",
        "autoscaling:DescribeAutoScalingGroups",
      ]
      Resource = "*"
    }]
  })
}

resource "aws_iam_policy" "secrets_read" {
  name = "secrets-read-${var.env}"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "secretsmanager:GetSecretValue"
      Resource = var.secret_app_env_arn
    }]
  })
}

resource "aws_iam_policy" "ssm_params" {
  name = "ssm-params-${var.env}"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ssm:PutParameter",
        "ssm:GetParameter",
        "ssm:GetParameters",
      ]
      Resource = "arn:aws:ssm:ap-northeast-1:${var.account_id}:parameter/ec2-packer/*"
    }]
  })
}
