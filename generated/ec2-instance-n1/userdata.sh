#!/bin/bash
set -e
apt-get update -y
apt-get install -y ca-certificates curl gnupg lsb-release

# Install Docker from official repo
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

systemctl enable docker
systemctl start docker
usermod -aG docker ubuntu

# Install SSM agent (for GitHub Actions deploy)
snap install amazon-ssm-agent --classic
systemctl enable snap.amazon-ssm-agent.amazon-ssm-agent
systemctl start snap.amazon-ssm-agent.amazon-ssm-agent

mkdir -p /home/ubuntu/app

# Write nginx config
cat <<'NGINX' > /home/ubuntu/app/nginx.conf
events { worker_connections 1024; }
http {
  include /etc/nginx/mime.types;
  client_max_body_size 32M;
  server {
    listen 80;
    location / {
      proxy_pass         http://app:8000;
      proxy_http_version 1.1;
      proxy_set_header   Upgrade $http_upgrade;
      proxy_set_header   Connection "upgrade";
      proxy_set_header   Host $host;
      proxy_set_header   X-Real-IP $remote_addr;
      proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header   X-Forwarded-Proto $http_x_forwarded_proto;
      proxy_read_timeout 300s;
    }
  }
}
NGINX

# Write docker-compose
cat <<'EOF' > /home/ubuntu/app/docker-compose.yml
version: "3.8"
services:
  app:
    image: vijju5557/devopsai:latest
    restart: always
    env_file: .env
    volumes:
      - app_data:/app/generated
      - app_db:/app/data
  nginx:
    image: nginx:latest
    restart: always
    ports:
      - "80:80"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
    depends_on:
      - app
volumes:
  app_data:
  app_db:
EOF

# Write empty .env (GitHub Actions will fill this on first deploy)
touch /home/ubuntu/app/.env

chown -R ubuntu:ubuntu /home/ubuntu/app
cd /home/ubuntu/app && docker compose up -d
