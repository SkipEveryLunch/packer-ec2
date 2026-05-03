packer {
  required_plugins {
    amazon = {
      version = ">= 1.3.0"
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

source "amazon-ebs" "rails" {
  region        = var.region
  source_ami    = data.amazon-ami.al2023.id
  instance_type = "t3.small"
  ssh_username  = "ec2-user"
  ami_name      = "rails-app-${var.env}-{{timestamp}}"
  tags = {
    Name = "rails-app-${var.env}"
    Env  = var.env
  }
}

build {
  sources = ["source.amazon-ebs.rails"]

  provisioner "file" {
    source      = "ror"
    destination = "/tmp/"
  }

  provisioner "shell" {
    script = "packer/scripts/install.sh"
  }

  provisioner "shell" {
    script = "packer/scripts/setup-service.sh"
  }

  post-processor "manifest" {
    output     = "packer/manifest.json"
    strip_path = true
  }
}
