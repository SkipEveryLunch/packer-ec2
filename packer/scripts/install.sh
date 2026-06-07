#!/bin/bash
set -euo pipefail

APP_DIR="/var/www/app"

# Install Ruby and build dependencies
dnf install -y ruby ruby-devel rubygems gcc gcc-c++ make

# Tools for runtime secret fetch (jq + AWS CLI v2; AL2023 does not ship awscli)
dnf install -y jq unzip
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
unzip -q /tmp/awscliv2.zip -d /tmp
/tmp/aws/install
rm -rf /tmp/awscliv2.zip /tmp/aws

# Install bundler
gem install bundler --no-document

# Deploy app
mkdir -p "$APP_DIR"
cp -r /tmp/ror/. "$APP_DIR/"
chown -R ec2-user:ec2-user "$APP_DIR"

# Bundle install
cd "$APP_DIR"
bundle config set --local without 'development test'
bundle install

# SECRET_KEY_BASE is no longer baked into the AMI here.
# It is fetched at boot from Secrets Manager (see setup-service.sh).
echo "RAILS_ENV=production" >> /etc/environment
