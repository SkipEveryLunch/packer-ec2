#!/bin/bash
set -euo pipefail

cat > /etc/systemd/system/puma.service << 'EOF'
[Unit]
Description=Puma HTTP Server
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/var/www/app
EnvironmentFile=/etc/environment
ExecStart=/usr/bin/bundle exec puma -C /var/www/app/config/puma.rb
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable puma
