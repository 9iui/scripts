#!/usr/bin/env bash
set -euo pipefail

echo "==============================="
echo " ELK All-in-One Install Script "
echo " Ubuntu 20.04 / 22.04 | Elastic 8.x"
echo "==============================="

# ----- ROOT CHECK -----
if [ "${EUID}" -ne 0 ]; then
  echo "❌ Run with sudo: sudo ./install-elk-all-in-one.sh"
  exit 1
fi

ELASTIC_VERSION="8.x"
ELASTIC_PASSWORD_FILE="/root/elastic-password.txt"
KIBANA_ENROLLMENT_FILE="/root/kibana-enrollment-token.txt"

echo "[+] Update system + install deps..."
apt update && apt upgrade -y
apt install -y curl apt-transport-https ca-certificates gnupg openjdk-17-jdk

echo "[+] Add Elastic repo key..."
curl -fsSL https://artifacts.elastic.co/GPG-KEY-elasticsearch \
| gpg --dearmor -o /usr/share/keyrings/elastic-keyring.gpg

echo "[+] Add Elastic repo..."
echo "deb [signed-by=/usr/share/keyrings/elastic-keyring.gpg] https://artifacts.elastic.co/packages/${ELASTIC_VERSION}/apt stable main" \
| tee /etc/apt/sources.list.d/elastic-${ELASTIC_VERSION}.list >/dev/null

apt update

echo "[+] Install Elasticsearch + Logstash + Kibana..."
apt install -y elasticsearch logstash kibana

echo "[+] Configure Elasticsearch (all-in-one, local-only HTTP)..."
cat <<EOF > /etc/elasticsearch/elasticsearch.yml
cluster.name: elk-cluster
node.name: node-1
network.host: localhost
http.port: 9200
discovery.type: single-node
EOF

echo "[+] Set Elasticsearch heap (safe default for small lab)..."
mkdir -p /etc/elasticsearch/jvm.options.d
cat <<EOF > /etc/elasticsearch/jvm.options.d/heap.options
-Xms1g
-Xmx1g
EOF

echo "[+] Enable + start Elasticsearch..."
systemctl enable elasticsearch
systemctl start elasticsearch

echo "[+] Wait for Elasticsearch..."
for i in {1..60}; do
  if curl -s http://localhost:9200 >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

echo "[+] Create elastic password (saved root-only)..."
ELASTIC_PASS=$(/usr/share/elasticsearch/bin/elasticsearch-reset-password -u elastic -b | awk '{print $NF}')
echo "${ELASTIC_PASS}" > "${ELASTIC_PASSWORD_FILE}"
chmod 600 "${ELASTIC_PASSWORD_FILE}"
echo "    Saved: ${ELASTIC_PASSWORD_FILE}"

echo "[+] Create Kibana enrollment token (saved root-only)..."
KIBANA_TOKEN=$(/usr/share/elasticsearch/bin/elasticsearch-create-enrollment-token -s kibana)
echo "${KIBANA_TOKEN}" > "${KIBANA_ENROLLMENT_FILE}"
chmod 600 "${KIBANA_ENROLLMENT_FILE}"
echo "    Saved: ${KIBANA_ENROLLMENT_FILE}"

echo "[+] Configure Kibana..."
cat <<EOF > /etc/kibana/kibana.yml
server.port: 5601
server.host: "0.0.0.0"
elasticsearch.hosts: ["https://localhost:9200"]
EOF

echo "[+] Enroll Kibana (one-time bootstrap)..."
/usr/share/kibana/bin/kibana-setup --enrollment-token "${KIBANA_TOKEN}" || true

echo "[+] Configure Logstash pipeline (Beats -> Elasticsearch)..."
cat <<EOF > /etc/logstash/conf.d/beats-to-es.conf
input {
  beats {
    port => 5044
  }
}

output {
  elasticsearch {
    hosts => ["https://localhost:9200"]
    user => "elastic"
    password => "${ELASTIC_PASS}"
    ssl => true
    cacert => "/etc/elasticsearch/certs/http_ca.crt"
    index => "logs-%{+YYYY.MM.dd}"
  }
}
EOF

echo "[+] Enable + restart Kibana + Logstash..."
systemctl enable kibana logstash
systemctl restart kibana
systemctl restart logstash

# UFW rules (optional + safe)
if command -v ufw >/dev/null 2>&1; then
  echo "[+] Opening ports (if UFW is active)..."
  ufw allow 5601 >/dev/null 2>&1 || true
  ufw allow 5044 >/dev/null 2>&1 || true
fi

echo "==============================="
echo " Verification "
echo "==============================="

echo "[+] Elasticsearch (TLS + auth) test:"
curl --cacert /etc/elasticsearch/certs/http_ca.crt \
  -u "elastic:${ELASTIC_PASS}" \
  https://localhost:9200 | head -n 5 || true

echo ""
echo "✅ ELK All-in-One installed!"
echo "Kibana UI: http://<SERVER-IP>:5601"
echo "Elastic password: ${ELASTIC_PASSWORD_FILE}"
echo "Kibana token: ${KIBANA_ENROLLMENT_FILE}"
echo ""
echo "Next: ship logs with Filebeat to port 5044."
