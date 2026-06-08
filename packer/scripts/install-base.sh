#!/bin/bash
set -euo pipefail

# Ruby + native gem build toolchain
dnf install -y ruby ruby-devel rubygems gcc gcc-c++ make

# Runtime tool used by the with-secrets wrapper
dnf install -y jq

# AWS CLI v2 (AL2023 default repos do not ship awscli v2)
dnf install -y unzip
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
unzip -q /tmp/awscliv2.zip -d /tmp
/tmp/aws/install
rm -rf /tmp/awscliv2.zip /tmp/aws

# CloudWatch Agent (config is placed at app AMI build time)
dnf install -y amazon-cloudwatch-agent

# Bundler
gem install bundler --no-document
