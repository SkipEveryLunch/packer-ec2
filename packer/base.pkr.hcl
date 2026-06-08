packer {
  required_plugins {
    amazon = {
      version = "1.8.0"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

variable "region" {
  default = "ap-northeast-1"
}

variable "env" {
  default = "prd"
}

data "amazon-ami" "al2023" {
  region = var.region
  filters = {
    name                = "al2023-ami-2023.*-x86_64"
    root-device-type    = "ebs"
    virtualization-type = "hvm"
  }
  most_recent = true
  owners      = ["amazon"]
}

source "amazon-ebs" "base" {
  region        = var.region
  source_ami    = data.amazon-ami.al2023.id
  instance_type = "t3.medium"
  ssh_username  = "ec2-user"
  ami_name      = "al2023-ruby-base-${var.env}-{{timestamp}}"
  tags = {
    Name    = "al2023-ruby-base-${var.env}"
    Env     = var.env
    Role    = "al2023-ruby-base"
    Manager = "packer"
  }
  run_tags = {
    Name    = "packer-builder-al2023-ruby-base-${var.env}"
    Manager = "packer"
  }
  run_volume_tags = {
    Manager = "packer"
  }
  snapshot_tags = {
    Manager = "packer"
  }
}

build {
  sources = ["source.amazon-ebs.base"]

  provisioner "shell" {
    execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    script          = "packer/scripts/install-base.sh"
  }
}
