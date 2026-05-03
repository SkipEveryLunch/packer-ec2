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
              [Puma:3000 + Rails API app]
                     │
                     ▼ ※ Phase 2
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
│   ├── rails.pkr.hcl
│   └── scripts/
│       ├── install.sh           # Ruby / 依存パッケージ
│       └── setup-service.sh     # systemd ユニット設定
├── terraform/
│   ├── modules/aws/
│   │   ├── vpc/
│   │   ├── subnet/
│   │   ├── internet_gateway/
│   │   ├── route_table/
│   │   ├── security_group/
│   │   ├── alb/
│   │   ├── asg/            # Phase 1
│   │   ├── iam_role/       # Phase 1
│   │   └── aurora/         # Phase 2
│   └── prd/
│       ├── aws.tf
│       ├── data.tf
│       ├── versions.tf
│       └── variables.tf
└── ror/
    └── (rails new --api --minimal --skip-test)
```

---

## Phase 1: Hello World

DB なしで `GET /hello → { message: "hello world" }` がブラウザから返るところまで。

### 構築順序

```
1. ror/         Rails API アプリ実装・ローカル動作確認
2. packer/      AMI テンプレート実装・手動ビルド → SSM に AMI ID 書き込み確認
3. terraform/   iam_role + asg を実装・apply
4.              ALB ヘルスチェック通過 → https://{domain}/hello で確認
5. .github/     GHA ワークフロー実装・E2E 確認
```

### Rails 構成 (ror/)

```
rails new ror --api --minimal --skip-test

ルーティング:
  GET /hello → HelloController#index

レスポンス:
  { message: "hello world" }

ヘルスチェック:
  GET /up → 200 (Rails デフォルト)
```

### Terraform: IAM (module: iam_role)

| リソース | 論理名 | 設定 |
|---|---|---|
| `aws_iam_role` | `ec2` | AssumeRole: ec2.amazonaws.com |
| `aws_iam_role_policy_attachment` | `ssm` | AmazonSSMManagedInstanceCore |
| `aws_iam_instance_profile` | `ec2` | role = iam_role.ec2 |

- **outputs**: `profile_name_ec2`

### Terraform: ASG (module: asg)

| リソース | 論理名 | 設定 |
|---|---|---|
| `aws_launch_template` | `app` | 後述 |
| `aws_autoscaling_group` | `app` | min=1, max=2, desired=1 |

**Launch Template**:

| 項目 | 値 |
|---|---|
| `image_id` | `data.aws_ssm_parameter.ami_id.value` |
| `instance_type` | `t3.small` |
| `iam_instance_profile` | `module.iam_role.profile_name_ec2` |
| `vpc_security_group_ids` | `[module.security_group.id_ec2]` |
| `user_data` | RAILS_ENV=production 等の環境変数を注入 (base64) |

**ASG**:

| 項目 | 値 |
|---|---|
| `vpc_zone_identifier` | `[public_1a, public_1c]` |
| `target_group_arns` | `[module.alb.arn_target_group_app]` |
| `health_check_type` | `"ELB"` |
| `health_check_grace_period` | `300` |

```hcl
lifecycle {
  ignore_changes = [desired_capacity]
}
```

**SSM Parameter Store** (Packer が書き込む):
```
/ec2-packer/prd/ami-id
```

```hcl
// data.tf
data "aws_ssm_parameter" "ami_id" {
  name = "/ec2-packer/${local.env}/ami-id"
}
```

- **outputs**: `name_asg_app`

### Packer (packer/rails.pkr.hcl)

```
source: amazon-ebs
  base: AL2023 最新 AMI (data source)
  instance_type: t3.small
  AMI 名: rails-app-{timestamp}

build:
  1. install.sh        : dnf で Ruby 3.x インストール
  2. bundle install    : ror/ をコピーして依存解決
  3. setup-service.sh  : puma を systemd unit 登録 (port 3000)
  4. post-processor    : AMI ID を SSM /ec2-packer/prd/ami-id に書き込み
```

---

## Phase 2: DB 連携

Hello World 確認後に実施。

### 追加内容

- Aurora Serverless v2 (PostgreSQL 16) を private subnet に構築
- Post モデル (message: text) の CRUD API を追加
- IAM に Secrets Manager ポリシーを追加
- user_data で `DATABASE_URL` を Secrets Manager から取得して注入

### Rails 追加実装

```
Post モデル:
  - message: text (NOT NULL)
  - timestamps

ルーティング:
  resources :posts, only: [:index, :create]

レスポンス (JSON):
  index  : Post.all
  create : Post.create!(message: params[:message])
```

### Terraform: Aurora (module: aurora)

| リソース | 論理名 | 設定 |
|---|---|---|
| `aws_db_subnet_group` | `app` | private_1a, private_1c |
| `aws_rds_cluster` | `app` | aurora-postgresql 16, serverless v2 |
| `aws_rds_cluster_instance` | `app_1` | db.serverless, count=1 |

**RDS Cluster**:

| 項目 | 値 |
|---|---|
| `engine` | `aurora-postgresql` |
| `engine_version` | `16.6` |
| `engine_mode` | `provisioned` |
| `manage_master_user_password` | `true` (Secrets Manager 自動保存) |
| `skip_final_snapshot` | `true` (教育用) |
| `deletion_protection` | `false` (教育用) |

```hcl
serverlessv2_scaling_configuration {
  min_capacity = 0.5
  max_capacity = 4
}
```

- **outputs**: `endpoint_app`, `secret_arn_app`

### Terraform: IAM 追加

| リソース | 追加ポリシー |
|---|---|
| `aws_iam_role_policy_attachment` | SecretsManagerReadWrite (対象 ARN を絞る) |

---

## 実装済み Terraform リソース

| モジュール | リソース | 状態 |
|---|---|---|
| vpc | aws_vpc | ✅ |
| subnet | aws_subnet ×4 | ✅ |
| internet_gateway | aws_internet_gateway | ✅ |
| route_table | aws_route_table + association ×4 | ✅ |
| security_group | alb / ec2 / aurora SG | ✅ |
| alb | aws_lb + target_group + listener ×2 | ✅ |
| — | data: route53_zone, acm_certificate | ✅ |
| — | aws_route53_record | ✅ |
| iam_role | — | 未 (Phase 1) |
| asg | — | 未 (Phase 1) |
| aurora | — | 未 (Phase 2) |

---

## GHA ワークフロー

### build-ami.yml
トリガー: `ror/**` または `packer/**` への push (main)

```
1. checkout
2. packer init & build → SSM に AMI ID 書き込み
3. deploy workflow を呼び出し
```

### deploy.yml
トリガー: `build-ami.yml` 完了後 / `terraform/**` への push

```
1. terraform init / plan / apply
2. aws autoscaling start-instance-refresh --auto-scaling-group-name {name}
3. describe-instance-refreshes でポーリング待機
```

---

## 未決事項

- [ ] ドメイン名・Route53 ホストゾーン名
- [ ] AWS アカウント ID / プロファイル名
- [ ] Rails のデプロイ先ディレクトリ (`/var/www/app` 等)
