#!/bin/bash
set -euo pipefail

APP_DIR="/var/www/app"

# Deploy app (ruby / bundler / aws-cli / jq come from al2023-ruby-base AMI)
mkdir -p "$APP_DIR"
cp -r /tmp/ror/. "$APP_DIR/"
chown -R ec2-user:ec2-user "$APP_DIR"

cd "$APP_DIR"
bundle config set --local without 'development test'
bundle install --jobs=4 --retry=2

echo "RAILS_ENV=production" >> /etc/environment
