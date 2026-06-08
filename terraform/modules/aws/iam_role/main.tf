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
GHA roles (one per workflow, OIDC trust narrowed by job_workflow_ref)
************************************************************/
resource "aws_iam_role" "gha_build_base" {
  name = "gha-build-base-${var.env}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = var.oidc_github_actions_arn }
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:job_workflow_ref" = "${var.github_repo}/.github/workflows/build-base-ami.yml@refs/heads/main"
        }
      }
    }]
  })
}

resource "aws_iam_role" "gha_build_app" {
  name = "gha-build-app-${var.env}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = var.oidc_github_actions_arn }
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:job_workflow_ref" = "${var.github_repo}/.github/workflows/build-ami.yml@refs/heads/main"
        }
      }
    }]
  })
}

resource "aws_iam_role" "gha_deploy" {
  name = "gha-deploy-${var.env}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = var.oidc_github_actions_arn }
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:job_workflow_ref" = "${var.github_repo}/.github/workflows/deploy.yml@refs/heads/main"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "gha_build_base" {
  for_each = {
    packer_build = aws_iam_policy.packer_build.arn
  }
  role       = aws_iam_role.gha_build_base.name
  policy_arn = each.value
}

resource "aws_iam_role_policy_attachment" "gha_build_app" {
  for_each = {
    packer_build = aws_iam_policy.packer_build.arn
    ssm_put_ami  = aws_iam_policy.ssm_put_ami.arn
  }
  role       = aws_iam_role.gha_build_app.name
  policy_arn = each.value
}

resource "aws_iam_role_policy_attachment" "gha_deploy" {
  for_each = {
    asg_refresh    = aws_iam_policy.asg_refresh.arn
    ssm_get_deploy = aws_iam_policy.ssm_get_deploy.arn
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
      ]
      Resource = "*"
      Condition = {
        StringEquals = {
          "aws:RequestedRegion" = "ap-northeast-1"
        }
      }
    }]
  })
}

resource "aws_iam_policy" "asg_refresh" {
  name = "asg-refresh-${var.env}"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "LaunchTemplateMutations"
        Effect = "Allow"
        Action = [
          "ec2:CreateLaunchTemplateVersion",
          "ec2:ModifyLaunchTemplate",
        ]
        Resource = "arn:aws:ec2:ap-northeast-1:${var.account_id}:launch-template/*"
      },
      {
        Sid    = "ASGMutations"
        Effect = "Allow"
        Action = [
          "autoscaling:UpdateAutoScalingGroup",
          "autoscaling:StartInstanceRefresh",
        ]
        Resource = "arn:aws:autoscaling:ap-northeast-1:${var.account_id}:autoScalingGroup:*:autoScalingGroupName/app-${var.env}"
      },
      {
        // Describe* APIs do not support resource-level permissions
        Sid    = "DescribeNoResourceLevel"
        Effect = "Allow"
        Action = [
          "ec2:DescribeLaunchTemplates",
          "ec2:DescribeLaunchTemplateVersions",
          "autoscaling:DescribeInstanceRefreshes",
          "autoscaling:DescribeAutoScalingGroups",
        ]
        Resource = "*"
      },
    ]
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

resource "aws_iam_policy" "ssm_put_ami" {
  name = "ssm-put-ami-${var.env}"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "ssm:PutParameter"
      Resource = "arn:aws:ssm:ap-northeast-1:${var.account_id}:parameter/ec2-packer/${var.env}/ami-id"
    }]
  })
}

resource "aws_iam_policy" "ssm_get_deploy" {
  name = "ssm-get-deploy-${var.env}"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ssm:GetParameter",
        "ssm:GetParameters",
      ]
      Resource = [
        "arn:aws:ssm:ap-northeast-1:${var.account_id}:parameter/ec2-packer/${var.env}/ami-id",
        "arn:aws:ssm:ap-northeast-1:${var.account_id}:parameter/ec2-packer/${var.env}/launch-template-id",
        "arn:aws:ssm:ap-northeast-1:${var.account_id}:parameter/ec2-packer/${var.env}/asg-name",
      ]
    }]
  })
}
