#!/bin/bash
set -e

# Pastikan dijalankan sebagai root
if [ "$(id -u)" != "0" ]; then
   echo "Please run as root"
   exit 1
fi

# Konversi CRLF ke LF (jika file diedit dari Windows)
if command -v dos2unix >/dev/null 2>&1; then
    dos2unix "$0" >/dev/null 2>&1 || true
fi

echo "=== Installing Postal Mail Server on Ubuntu 22.04 ==="
sleep 2

# --- Update & Dependencies ---
apt update -y
apt install -y curl wget gnupg lsb-release apt-transport-https ca-certificates software-properties-common git redis-server rabbitmq-server mysql-server

# --- Install Docker ---
echo "Installing Docker..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt update -y
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# --- Setup MySQL ---
DBPASS="postalpass"
mysql -e "CREATE DATABASE IF NOT EXISTS postal CHARSET utf8mb4 COLLATE utf8mb4_unicode_ci;"
mysql -e "CREATE USER IF NOT EXISTS 'postal'@'localhost' IDENTIFIED BY '${DBPASS}';"
mysql -e "GRANT ALL PRIVILEGES ON postal.* TO 'postal'@'localhost'; FLUSH PRIVILEGES;"

# --- Setup RabbitMQ ---
systemctl enable rabbitmq-server
systemctl start rabbitmq-server
MQPASS="postalrabbit"
rabbitmqctl add_user postal "${MQPASS}" 2>/dev/null || true
rabbitmqctl add_vhost /postal 2>/dev/null || true
rabbitmqctl set_permissions -p /postal postal ".*" ".*" ".*" 2>/dev/null || true

# --- Install Postal ---
echo "Installing Postal..."
curl -sSL https://raw.githubusercontent.com/postalserver/install/master/install.sh | sh
postal install

# --- Configure Postal ---
DOMAIN="mail.$(hostname -f)"
postal initialize-config
sed -i "s/web\.example\.com/${DOMAIN}/g" /opt/postal/config/postal.yml
sed -i "s/rabbitmq:\/\/.*@localhost/rabbitmq:\/\/postal:${MQPASS}@localhost\/postal/g" /opt/postal/config/postal.yml
sed -i "s/mysql:\/\/.*@localhost/mysql:\/\/postal:${DBPASS}@localhost\/postal/g" /opt/postal/config/postal.yml

# --- Initialize Postal DB ---
postal initialize

# --- Create first admin user ---
postal make-user

# --- Enable Postal service ---
postal start
systemctl enable postal

echo ""
echo "✅ Postal installation complete!"
echo "Login URL: https://${DOMAIN}/"
echo "DB User: postal / ${DBPASS}"
echo "MQ User: postal / ${MQPASS}"
echo ""
