#!/usr/bin/env bash
set -e

echo "==============================="
echo " ELK Stack Installation Script "
echo " Ubuntu 20.04 / 22.04 "
echo "==============================="

# ---- VARIABLES ----
ELASTIC_VERSION="8.x"

# ---- CHECK ROOT ----
if [ "$EUID" -ne 0 ]; then
  echo "❌ Please run as root or with sudo"
  exit 1
fi

# ---- SYSTEM UPDATE ----
echo "[+] Updating system..."
apt update && apt upgrade -y

# ---- DEPENDENCIES ----
echo "[+] Installing dependencies..."
apt install -y curl apt-transport-https ca-certificates gnupg openjdk-17-jdk

# ---- JAVA CHECK ----
echo "[+] Java version:"
java -version

# ---- ADD ELASTIC REPO ----
echo "[+] Adding Elastic GPG key..."
curl -fsSL https://artifacts.elastic.co/GPG-KEY-elasticsearch \
| gpg --dearmor -o /usr/share/keyrings/elastic-keyring.gpg

echo "[+] Adding Elastic repository..."
echo "deb [signed-by=/usr/share/keyrings/elastic-keyring.gpg] \
https://artifacts.elastic.co/packages/${ELASTIC_VERSION}/apt stable main" \
| tee /etc/apt/sources.list.d/elastic-${ELASTIC_VERSION}.list

apt update

# ---- INSTALL ELK ----
echo "[+] Installing Elasticsearch..."
apt install -y elasticsearch

echo "[+] Installing Logstash..."
apt install -y logstash

echo "[+] Installing Kibana..."
apt install -y kibana

# ---- CONFIGURE ELASTICSEARCH ----
echo "[+] Configuring Elasticsearch..."
cat <<EOF > /etc/elasticsearch/elasticsearch.yml
cluster.name: elk-cluster
node.name: node-1
network.host: localhost
http.port: 9200
discovery.type: single-node
EOF

# ---- MEMORY SETTINGS ----
echo "[+] Setting Elasticsearch JVM memory..."
mkdir -p /etc/elasticsearch/jvm.options.d
cat <<EOF > /etc/elasticsearch/jvm.options.d/heap.options
-Xms1g
-Xmx1g
EOF

# ---- CONFIGURE KIBANA ----
echo "[+] Configuring Kibana..."
cat <<EOF > /etc/kibana/kibana.yml
server.port: 5601
server.host: "0.0.0.0"
elasticsearch.hosts: ["http://localhost:9200"]
EOF

# ---- CREATE LOGSTASH PIPELINE ----
echo "[+] Creating Logstash test pipeline..."
cat <<EOF > /etc/logstash/conf.d/test.conf
input {
  beats {
    port => 5044
  }
}

output {
  elasticsearch {
    hosts => ["http://localhost:9200"]
    index => "logs-%{+YYYY.MM.dd}"
  }
}
EOF

# ---- ENABLE & START SERVICES ----
echo "[+] Enabling and starting services..."
systemctl daemon-reexec
systemctl enable elasticsearch logstash kibana
systemctl start elasticsearch logstash kibana

# ---- FIREWALL ----
if command -v ufw >/dev/null 2>&1; then
  echo "[+] Configuring UFW firewall..."
  ufw allow 9200
  ufw allow 5601
  ufw allow 5044
fi

# ---- STATUS CHECK ----
echo "==============================="
echo " Service Status "
echo "==============================="
systemctl --no-pager status elasticsearch | head -n 5
systemctl --no-pager status kibana | head -n 5
systemctl --no-pager status logstash | head -n 5

echo "==============================="
echo " ELK Installation Complete "
echo "==============================="
echo "Elasticsearch: http://localhost:9200"
echo "Kibana: http://<SERVER-IP>:5601"
echo ""
echo "⚠️  Next Steps:"
echo "1. Reset elastic password:"
echo "   /usr/share/elasticsearch/bin/elasticsearch-reset-password -u elastic"
echo ""
echo "2. Generate Kibana enrollment token:"
echo "   /usr/share/elasticsearch/bin/elasticsearch-create-enrollment-token -s kibana"
