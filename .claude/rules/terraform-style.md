# Terraform Style Rules (ec2-packer)

## ファイル構成

| ファイル | 内容 |
|---|---|
| `main.tf` | リソース定義のみ |
| `variables.tf` | variable + locals（派生値もここ） |
| `outputs.tf` | output のみ |
| `backend.tf` | S3 バックエンド（profile なし） |
| `versions.tf` | required_version + provider（default_tags 含む） |
| `aws.tf` | module 呼び出しのみ（環境ディレクトリ直下） |

## モジュール設計

**1 AWSリソース種別 = 1モジュール**

```
modules/aws/
├── vpc/               # aws_vpc のみ
├── subnet/            # aws_subnet のみ
├── internet_gateway/  # aws_internet_gateway のみ
├── route_table/       # aws_route_table + aws_route_table_association
├── security_group/    # aws_security_group のみ
├── alb/               # aws_lb + aws_lb_listener + aws_lb_target_group
├── asg/               # aws_launch_template + aws_autoscaling_group
├── aurora/            # aws_rds_cluster + aws_rds_cluster_instance
└── iam_role/          # aws_iam_role + aws_iam_instance_profile
```

- 同種リソースを1ファイルにまとめることで記法・パターンが統一される
- 複数の密結合リソース（lb + listener + target_group 等）は同モジュールにまとめてよい
- 「機能」や「サービス名」でモジュールを切らない

## 命名規則

| 種別 | パターン | 例 |
|---|---|---|
| リソース名 | `{service}-{env}` | `cp-bastion-stg` |
| EC2 tags.Name | `cp-{role}-{az}-{env}` | `cp-nat-1a-stg` |
| TF リソース識別子 | 用途を明示 | `aws_instance.bastion` |
| ボリューム | 常に gp3, 8GB, delete_on_termination=true | — |

## 出力名プレフィックス

| プレフィックス | 用途 |
|---|---|
| `id_*` | リソース ID |
| `arn_*` | ARN |
| `url_*` | URL / endpoint |
| `network_interface_id_*` | ENI ID |
| `zone_id_*` | Route53 zone ID |
| `dns_name_*` | DNS 名 |

## Variables パターン

```hcl
// シンプル変数: type/default は必要時のみ
variable "env" {}
variable "public_subnet_id" { type = string }

// 関連変数はオブジェクトに集約。optional でデフォルト指定可
variable "bastion" {
  type = object({
    ami_id               = optional(string, "ami-023ff3d4ab11b2525") // AL2023
    iam_instance_profile = string
    security_group_id    = string
  })
}

// 派生値は variables.tf 内の locals で
locals {
  env        = "prd"
  account_id = "123456789012"
  region     = "ap-northeast-1"
}
```

## Module 呼び出しフォーマット

```hcl
// 空行なし。順序: source → 共通変数 → オブジェクト変数
module "ec2" {
  source           = "../modules/aws/ec2"
  env              = local.env
  public_subnet_id = module.subnet.id_public_1a
  bastion = {
    iam_instance_profile = module.iam_role.profile_bastion
    security_group_id    = module.security_group.id_bastion
  }
  nat_1a = {
    iam_instance_profile = module.iam_role.profile_nat
    security_group_id    = module.security_group.id_nat
  }
}
```

## EC2 リソース パターン

```hcl
resource "aws_instance" "bastion" {
  tags = { Name = "cp-bastion-${var.env}" }

  ami                    = var.bastion.ami_id
  instance_type          = "t2.micro"
  iam_instance_profile   = var.bastion.iam_instance_profile
  subnet_id              = var.public_subnet_id
  vpc_security_group_ids = [var.bastion.security_group_id]
  source_dest_check      = true // NAT は false

  root_block_device {
    delete_on_termination = true
    volume_size           = 8
    volume_type           = "gp3"
  }
}
```

## Provider / versions.tf テンプレート

```hcl
terraform {
  required_version = "~> 1.11.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.5.0"
    }
  }
}

provider "aws" {
  region  = "ap-northeast-1"
  profile = "cp-terraform-prd"
  default_tags { tags = { Env = "prd" } }
}

// CloudFront / ACM が必要な場合のみ追加
provider "aws" {
  region  = "us-east-1"
  profile = "cp-terraform-prd"
  alias   = "us_east_1"
  default_tags { tags = { Env = "prd" } }
}
```

## backend.tf テンプレート

```hcl
terraform {
  backend "s3" {
    bucket = "cp-terraform-prd"
    key    = "main.tfstate"
    region = "ap-northeast-1"
    // profile は書かない
  }
}
```

## Lifecycle ルール

```hcl
// CI/CD 管理の属性は ignore（AMI は Packer で更新される場合）
lifecycle {
  ignore_changes = [ami]
}
```

## Data Source 戦略

- Route53 Hosted Zone・ACM 証明書は手動作成 → data source で参照
- Terraform apply のたびに DNS 伝播を待たなくて済む

```hcl
data "aws_route53_zone" "main" { name = local.domain }
data "aws_acm_certificate" "main" {
  domain      = "*.${local.domain}"
  statuses    = ["ISSUED"]
  most_recent = true
}
```

## タグ戦略

- `Env` タグは provider の `default_tags` で全リソースに自動付与
- リソース固有の `Name` タグのみ各リソースに記述
- 追加タグが必要な場合のみ `tags = { Name = "...", Role = "..." }`

## コメント規則

```hcl
// 単行メモ
// MEMO: 重要な補足事項

/************************************************************
セクション区切り（main.tf でリソースグループを分ける）
************************************************************/
```

## IAM パターン

### ロール命名
```
aws_iam_role        : {service}-{env}           例: cp-bastion-prd
aws_iam_policy      : {permission-type}-{env}   例: secrets-manager-read-prd
aws_iam_instance_profile : ロール名と同一
```

### AssumeRole ポリシーの書き方

```hcl
// EC2 / Lambda / ECS タスク（サービスプリンシパル）
assume_role_policy = jsonencode({
  Version = "2012-10-17"
  Statement = [{
    Effect    = "Allow"
    Action    = "sts:AssumeRole"
    Principal = { Service = "ec2.amazonaws.com" }
  }]
})

// GitHub Actions OIDC（StringLike で branch/tag を絞る）
assume_role_policy = jsonencode({
  Version = "2012-10-17"
  Statement = [{
    Effect = "Allow"
    Action = "sts:AssumeRoleWithWebIdentity"
    Principal = { Federated = var.oidc_github_actions_arn }
    Condition = {
      StringLike = {
        "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:ref:refs/heads/main"
      }
    }
  }]
})

// IAM スイッチロール（複数アカウントから AssumeRole）
assume_role_policy = jsonencode({
  Version = "2012-10-17"
  Statement = [{
    Effect    = "Allow"
    Action    = "sts:AssumeRole"
    Principal = {
      AWS = [for id in local.allowed_account_ids : "arn:aws:iam::${id}:root"]
    }
  }]
})
```

### ポリシーアタッチは for_each でまとめる

```hcl
// AWS 管理ポリシーとカスタムポリシーを混在させてよい
resource "aws_iam_role_policy_attachment" "gha_deploy" {
  for_each = {
    ecr          = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
    custom_build = aws_iam_policy.packer_build.arn
    custom_ssm   = aws_iam_policy.ssm_params.arn
  }
  role       = aws_iam_role.gha_deploy.name
  policy_arn = each.value
}
```

### outputs 命名プレフィックス（IAM）

| プレフィックス | 用途 |
|---|---|
| `arn_*` | Role ARN |
| `name_*` | Role 名 |
| `profile_name_*` | Instance Profile 名 |

### OIDC プロバイダーは独立モジュールに切り出す

```
modules/aws/oidc_github_actions/   # aws_iam_openid_connect_provider のみ
modules/aws/iam_role/              # aws_iam_role + aws_iam_policy + attachment
```

OIDC プロバイダーの ARN を iam_role モジュールに変数として渡す。

```hcl
module "oidc_github_actions" {
  source = "../modules/aws/oidc_github_actions"
}

module "iam_role" {
  source                  = "../modules/aws/iam_role"
  oidc_github_actions_arn = module.oidc_github_actions.arn
}
```

### カスタムポリシーは独立 aws_iam_policy リソースとして定義する

インラインポリシー（`aws_iam_role_policy`）は使わない。独立させることで複数ロールからの再利用が可能になる。

```hcl
// ❌ インラインポリシー（再利用不可）
resource "aws_iam_role_policy" "foo" { ... }

// ✅ 独立ポリシー → attachment で付与
resource "aws_iam_policy" "ssm_params" { ... }
resource "aws_iam_role_policy_attachment" "..." {
  for_each   = { ssm = aws_iam_policy.ssm_params.arn }
  role       = aws_iam_role.foo.name
  policy_arn = each.value
}
```

## Packer 連携パターン

- Packer でビルドした AMI ID は SSM Parameter Store 経由で受け渡す
- Terraform 側は data source で取得し、`ami_id` に渡す

```hcl
data "aws_ssm_parameter" "ami_bastion" {
  name = "/ec2-packer/${local.env}/ami-bastion"
}

// module 呼び出し側
bastion = {
  ami_id               = data.aws_ssm_parameter.ami_bastion.value
  iam_instance_profile = module.iam_role.profile_bastion
  security_group_id    = module.security_group.id_bastion
}
```
