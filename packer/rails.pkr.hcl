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

data "amazon-ami" "ruby_base" {
  region = var.region
  filters = {
    name             = "al2023-ruby-base-${var.env}-*"
    root-device-type = "ebs"
  }
  most_recent = true
  owners      = ["self"]
}

source "amazon-ebs" "rails" {
  region        = var.region
  source_ami    = data.amazon-ami.ruby_base.id
  instance_type = "t3.medium"
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

  provisioner "file" {
    source      = "packer/files"
    destination = "/tmp/"
  }

  provisioner "shell" {
    execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    script          = "packer/scripts/install.sh"
  }

  provisioner "shell" {
    execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    script          = "packer/scripts/setup-service.sh"
  }

  post-processor "manifest" {
    output     = "packer/manifest.json"
    strip_path = true
  }
}
