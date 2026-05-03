# ec2-packer 構成プラン

## 概要

Packer で Rails 込みの AMI を焼き、ASG Instance Refresh で EC2 を入れ替えるイミュータブルデプロイシステム。教育用最小構成。

## システム構成図

```
Internet
  │
  ▼
Route53 (data)  →  ALB (public subnet)
                     │  HTTPS:443 / HTTP:80→redirect
                     ▼
              EC2 × ASG (public subnet, AZ: 1a/1c)
              [Puma:3000 + Rails app]
                     │
                     ▼
              Aurora Serverless v2 (private subnet)
              [PostgreSQL 16]
```

## ディレクトリ構成

```
ec2-packer/
├── .github/
│   └── workflows/
│       ├── build-ami.yml        # Packer AMI ビルド
│       └── deploy.yml           # terraform apply + ASG Instance Refresh
├── packer/
│   ├── rails.pkr.hcl            # AMI 定義
│   └── scripts/
│       ├── install.sh           # Ruby / Node / 依存パッケージ
│       └── setup-service.sh     # systemd ユニット設定
├── terraform/
│   ├── modules/
│   │   └── aws/
│   │       ├── vpc/
│   │       ├── subnet/
│   │       ├── security_group/
│   │       ├── alb/
│   │       ├── asg/
│   │       ├── aurora/
│   │       └── iam_role/
│   └── prd/
│       ├── aws.tf
│       ├── backend.tf
│       ├── versions.tf
│       └── variables.tf
└── ror/                         # Rails 最小構成アプリ
    └── (rails new --minimal --database=postgresql)
```

---

## Terraform リソース詳細

### ネットワーク構成

#### module: vpc

| リソース | 論理名 | 設定値 |
|---|---|---|
| `aws_vpc` | `app` | CIDR: `10.0.0.0/16`, DNS support/hostnames: true |

- **outputs**: `id_app` (VPC ID)

#### module: subnet

| リソース | 論理名 | AZ | CIDR | 用途 |
|---|---|---|---|---|
| `aws_subnet` | `public_1a` | ap-northeast-1a | 10.0.0.0/24 | EC2/ALB |
| `aws_subnet` | `public_1c` | ap-northeast-1c | 10.0.1.0/24 | EC2/ALB |
| `aws_subnet` | `private_1a` | ap-northeast-1a | 10.0.10.0/24 | Aurora |
| `aws_subnet` | `private_1c` | ap-northeast-1c | 10.0.11.0/24 | Aurora |
| `aws_internet_gateway` | `app` | — | — | public 向け IGW |
| `aws_route_table` | `public` | — | `0.0.0.0/0 → IGW` | public ルート |
| `aws_route_table_association` | `public_1a/1c` | — | — | public subnet に紐付け |

- NAT Gateway は不要（EC2 はパブリックサブネット直、Aurora はプライベートで外部通信なし）
- **outputs**: `id_public_1a`, `id_public_1c`, `id_private_1a`, `id_private_1c`

#### module: security_group

| リソース | 論理名 | Inbound | Outbound |
|---|---|---|---|
| `aws_security_group` | `alb` | 80 from `0.0.0.0/0`, 443 from `0.0.0.0/0` | 3000 to `sg_ec2` |
| `aws_security_group` | `ec2` | 3000 from `sg_alb` | 5432 to `sg_aurora`, 443 to `0.0.0.0/0` |
| `aws_security_group` | `aurora` | 5432 from `sg_ec2` | なし |

- EC2 の outbound 443 は AWS API (SSM, ECR 等) のため
- **outputs**: `id_alb`, `id_ec2`, `id_aurora`

---

### ロードバランサー

#### module: alb

| リソース | 論理名 | 設定 |
|---|---|---|
| `aws_lb` | `app` | internal=false, type=application, subnets=[public_1a, public_1c] |
| `aws_lb_target_group` | `app` | port=3000, protocol=HTTP, target_type=instance |
| `aws_lb_listener` | `https` | port=443, protocol=HTTPS, cert=data.acm, action=forward to TG |
| `aws_lb_listener` | `http` | port=80, protocol=HTTP, action=redirect to HTTPS(301) |

**target_group ヘルスチェック設定**:
```
path                = "/up"   # Rails の health check エンドポイント
protocol            = "HTTP"
healthy_threshold   = 2
unhealthy_threshold = 3
interval            = 30
```

- **outputs**: `arn_target_group_app`, `dns_name_app`, `zone_id_app`

---

### EC2 / ASG

#### module: asg

| リソース | 論理名 | 設定 |
|---|---|---|
| `aws_launch_template` | `app` | 後述 |
| `aws_autoscaling_group` | `app` | min=1, max=2, desired=1 |
| `aws_autoscaling_attachment` | `app` | ASG ↔ ALB TG を紐付け |

**Launch Template 設定**:

| 項目 | 値 |
|---|---|
| `image_id` | `data.aws_ssm_parameter.ami_id.value` |
| `instance_type` | `t3.small` |
| `iam_instance_profile` | `module.iam_role.profile_ec2` |
| `vpc_security_group_ids` | `[module.security_group.id_ec2]` |
| `user_data` | DB 接続情報等を環境変数に注入するスクリプト (base64) |

**ASG 設定**:

| 項目 | 値 |
|---|---|
| `vpc_zone_identifier` | `[public_1a, public_1c]` |
| `health_check_type` | `"ELB"` |
| `health_check_grace_period` | `300` |
| `target_group_arns` | `[module.alb.arn_target_group_app]` |

**lifecycle**:
```hcl
lifecycle {
  ignore_changes = [desired_capacity]
}
```

**SSM Parameter Store** (Packer が書き込む):
```
/ec2-packer/prd/ami-id   ← 最新 AMI ID
```

Terraform 側:
```hcl
data "aws_ssm_parameter" "ami_id" {
  name = "/ec2-packer/${local.env}/ami-id"
}
```

- **outputs**: `name_asg_app` (Instance Refresh の対象名として使用)

---

### Aurora Serverless v2

#### module: aurora

| リソース | 論理名 | 設定 |
|---|---|---|
| `aws_db_subnet_group` | `app` | private_1a, private_1c |
| `aws_rds_cluster` | `app` | 後述 |
| `aws_rds_cluster_instance` | `app_1` | `db.serverless`, count=1 |

**RDS Cluster 設定**:

| 項目 | 値 |
|---|---|
| `engine` | `aurora-postgresql` |
| `engine_version` | `16.6` |
| `engine_mode` | `provisioned` |
| `cluster_identifier` | `app-${var.env}` |
| `database_name` | `app_${var.env}` |
| `master_username` | `appuser` |
| `manage_master_user_password` | `true` (Secrets Manager に自動保存) |
| `vpc_security_group_ids` | `[module.security_group.id_aurora]` |
| `db_subnet_group_name` | `aws_db_subnet_group.app.name` |
| `skip_final_snapshot` | `true` (教育用) |
| `deletion_protection` | `false` (教育用) |

**Serverless v2 スケーリング**:
```hcl
serverlessv2_scaling_configuration {
  min_capacity = 0.5
  max_capacity = 4
}
```

**Secrets Manager から DB 接続情報を取得** (EC2 user_data 内):
```bash
SECRET=$(aws secretsmanager get-secret-value --secret-id <cluster_master_user_secret_arn>)
export DATABASE_URL="postgresql://appuser:${PASSWORD}@${ENDPOINT}/app_prd"
```

- **outputs**: `endpoint_app`, `secret_arn_app` (Secrets Manager ARN)

---

### IAM

#### module: iam_role

| リソース | 論理名 | ポリシー |
|---|---|---|
| `aws_iam_role` | `ec2` | AssumeRole: ec2.amazonaws.com |
| `aws_iam_role_policy_attachment` | `ssm` | AmazonSSMManagedInstanceCore |
| `aws_iam_role_policy_attachment` | `secrets` | SecretsManagerReadWrite (絞り込み推奨) |
| `aws_iam_role_policy_attachment` | `ssm_params` | AmazonSSMReadOnlyAccess |
| `aws_iam_instance_profile` | `ec2` | role=iam_role.ec2 |

- **outputs**: `profile_ec2`

---

### DNS / SSL

#### data sources (prd/aws.tf 直書き、module化不要)

```hcl
data "aws_route53_zone" "main" {
  name = local.domain   // "your-domain.example.com"
}

data "aws_acm_certificate" "main" {
  domain      = "*.${local.domain}"
  statuses    = ["ISSUED"]
  most_recent = true
}
```

#### Route53 レコード (aws.tf に直書き)

```hcl
resource "aws_route53_record" "app" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = local.domain
  type    = "A"
  alias {
    name                   = module.alb.dns_name_app
    zone_id                = module.alb.zone_id_app
    evaluate_target_health = true
  }
}
```

---

### prd/variables.tf (locals)

```hcl
locals {
  env        = "prd"
  account_id = "xxxxxxxxxxxx"
  region     = "ap-northeast-1"
  domain     = "your-domain.example.com"
}
```

---

## Packer テンプレート概要 (packer/rails.pkr.hcl)

```
source: amazon-ebs
  base AMI: AL2023 最新 (data source で取得)
  instance_type: t3.small
  AMI 名: rails-app-${timestamp}

build steps:
  1. install.sh    : dnf で Ruby 3.x / Node / postgresql-client / nginx を install
  2. bundle install / assets precompile (ror/ をコピー)
  3. setup-service.sh : puma を systemd unit として登録
  4. AMI ID を SSM Parameter Store /ec2-packer/prd/ami-id に書き込み
```

---

## Rails 最小構成 (ror/)

```
rails new ror --minimal --database=postgresql --skip-test

Post モデル:
  - message: text (NOT NULL)
  - timestamps

ルーティング:
  resources :posts, only: [:index, :create]

コントローラー:
  PostsController
    index  : Post.all (一覧)
    create : Post.create!(message: params[:message])

ビュー:
  posts/index.html.erb
    - 投稿フォーム (message テキストエリア)
    - 投稿一覧

ヘルスチェック:
  GET /up → 200 (Rails 7.1+ デフォルト)
```

---

## GHA ワークフロー概要

### build-ami.yml

トリガー: `ror/**` または `packer/**` への push (main ブランチ)

```
jobs:
  build:
    1. checkout
    2. packer init & build
       → AMI 完成後、Packer が SSM へ AMI ID を書き込む
    3. deploy job を trigger (workflow_run または repository_dispatch)
```

### deploy.yml

トリガー: `build-ami.yml` 完了後 / `terraform/**` への push

```
jobs:
  terraform:
    1. terraform init / plan / apply
       → Launch Template が SSM から最新 AMI ID を取得して更新

  refresh:
    needs: terraform
    2. aws autoscaling start-instance-refresh \
         --auto-scaling-group-name <asg_name> \
         --preferences '{"MinHealthyPercentage": 50}'
    3. aws autoscaling describe-instance-refreshes でポーリング待機
```

---

## 構築順序

```
1. ror/         Rails アプリ実装・ローカル動作確認
2. terraform/   modules + prd/ を実装・apply (AMI なし状態でインフラのみ)
3. packer/      AMI テンプレート実装・手動ビルドで AMI → SSM 確認
4. terraform/   再 apply で Launch Template が AMI ID を取得することを確認
5. ASG          手動で Instance Refresh → 動作確認
6. .github/     GHA ワークフロー実装・E2E 確認
```

---

## 未決事項 (実装前に確認)

- [ ] ドメイン名・Route53 ホストゾーン名
- [ ] AWS アカウント ID / プロファイル名
- [ ] tfstate 用 S3 バケット名
- [ ] Rails のデプロイ先ディレクトリ (`/var/www/app` 等)
- [ ] DB パスワード管理: Secrets Manager の ARN を user_data に渡す方法
