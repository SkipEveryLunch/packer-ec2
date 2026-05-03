#!/bin/bash
set -euo pipefail

APP_DIR="/var/www/app"

# Install Ruby and build dependencies
dnf install -y ruby ruby-devel rubygems gcc gcc-c++ make

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

# Generate SECRET_KEY_BASE and persist to environment
SECRET=$(bundle exec rails secret)
echo "SECRET_KEY_BASE=$SECRET" >> /etc/environment
echo "RAILS_ENV=production" >> /etc/environment
