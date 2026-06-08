#!/bin/bash
set -euo pipefail

install -m 0755 /tmp/files/with-secrets    /usr/local/bin/with-secrets
install -m 0644 /tmp/files/puma.service    /etc/systemd/system/puma.service

# Log directory for puma stdout/stderr (also tailed by CloudWatch Agent)
install -d -m 0755 -o ec2-user -g ec2-user /var/log/puma

# CloudWatch Agent config (json → toml conversion via fetch-config)
install -m 0644 /tmp/files/cloudwatch-agent.json \
  /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

systemctl daemon-reload
systemctl enable puma
systemctl enable amazon-cloudwatch-agent
