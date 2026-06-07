#!/bin/bash
set -euo pipefail

install -m 0755 /tmp/files/with-secrets    /usr/local/bin/with-secrets
install -m 0644 /tmp/files/puma.service    /etc/systemd/system/puma.service

systemctl daemon-reload
systemctl enable puma
