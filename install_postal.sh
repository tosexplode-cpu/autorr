#!/bin/bash
# ============================================================
#  AUTO INSTALL POSTAL MAIL SERVER - Ubuntu 22.04+
#  Coded by ChatGPT GPT-5
# ============================================================

set -e

echo "============================================"
echo "       POSTAL AUTO INSTALLER (Ubuntu 22.04)"
echo "============================================"
sleep 1

# === User Input ===
read -p "Enter your mail domain (example: mail.example.com): " DOMAIN
read -p "Enter MySQL password for Postal user: " DBPASS
read -p "Enter RabbitMQ password: " MQPASS

# === Update System ===
apt update -y && apt upgrade -y
apt install -y curl wget git gnupg software-properties-common unzip nano apt-transport-https ca-certificates lsb-release

# === MariaDB Install ===
apt install -y mariadb-server
systemctl enable mariadb
systemctl start mariadb

mysql -u root <<MYSQL_SCRIPT
CREATE DATABASE postal CHARSET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'postal'@'127.0.0.1' IDENTIFIED BY '${DBPASS}';
GRANT ALL PRIVILEGES ON postal.* TO 'postal'@'127.0.0.1';
FLUSH PRIVILEGES;
MYSQL_SCRIPT

# === RabbitMQ Install ===
apt install -y rabbitmq-server
systemctl enable rabbitmq-server
systemctl start rabbitmq-server
rabbitmqctl add_user postal ${MQPASS} || true
rabbitmqctl add_vhost /postal || true
rabbitmqctl set_permissions -p /postal postal ".*" ".*" ".*"

# === Redis Install ===
apt install -y redis-server
systemctl enable redis-server
systemctl start redis-server

# === Docker Install ===
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
tee /etc/apt/sources.list.d/docker.list > /dev/null

apt update -y
apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
systemctl enable docker
systemctl start docker

# === Install Ruby & Postal ===
apt install -y ruby ruby-dev build-essential
gem install bundler
gem install postal

mkdir -p /opt/postal
cd /opt/postal
postal initialize-config

# === Write Config ===
cat > /opt/postal/config/postal.yml <<EOL
web:
  host: ${DOMAIN}
main_db:
  host: 127.0.0.1
  username: postal
  password: ${DBPASS}
  database: postal
message_db:
  host: 127.0.0.1
  username: postal
  password: ${DBPASS}
  prefix: postal
rabbitmq:
  host: 127.0.0.1
  username: postal
  password: ${MQPASS}
dns:
  mx_records:
    - ${DOMAIN}
  smtp_server_hostname: ${DOMAIN}
  spf_include: ${DOMAIN}
  return_path: rp.${DOMAIN}
  route_domain: routes.${DOMAIN}
smtp_server:
  tls_enabled: true
  tls_certificate_path: /etc/letsencrypt/live/${DOMAIN}/fullchain.pem
  tls_private_key_path: /etc/letsencrypt/live/${DOMAIN}/privkey.pem
EOL

# === Initialize Postal ===
postal initialize

# === Start Postal ===
postal start

# === Firewall Rules ===
ufw allow 22
ufw allow 25
ufw allow 80
ufw allow 443
ufw allow 465
ufw allow 587
ufw --force enable

# === Install SSL ===
apt install -y certbot
certbot certonly --standalone -d ${DOMAIN} --non-interactive --agree-tos -m admin@${DOMAIN} || true

postal restart

# === Create Admin User ===
echo "Creating admin user..."
postal make-user <<USER_INPUT
admin@${DOMAIN}
Postal Admin
password123
USER_INPUT

# === Done ===
echo "============================================"
echo "Postal Installation Complete!"
echo "============================================"
echo "Dashboard URL: https://${DOMAIN}"
echo "Login Email: admin@${DOMAIN}"
echo "Login Password: password123"
echo "MySQL User: postal | Password: ${DBPASS}"
echo "RabbitMQ User: postal | Password: ${MQPASS}"
echo "============================================"
echo "Next Steps:"
echo " - Add SPF, DKIM, and MX DNS records from Postal dashboard."
echo " - Then test sending an email."
echo "============================================"
