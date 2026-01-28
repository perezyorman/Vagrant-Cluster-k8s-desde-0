#!/bin/bash
# setup-etcd.sh - Configurar cluster etcd en control planes

set -e

echo "=== CONFIGURANDO CLUSTER ETCD ==="

# 1. Descargar e instalar etcd en controlplane01
echo "Instalando etcd en controlplane01..."
vagrant ssh controlplane01 << 'EOF'
# Variables
ETCD_VERSION="v3.5.9"
ARCH="amd64"

# Descargar etcd
wget -q --show-progress --https-only --timestamping \
  "https://github.com/etcd-io/etcd/releases/download/${ETCD_VERSION}/etcd-${ETCD_VERSION}-linux-${ARCH}.tar.gz"

# Extraer e instalar
tar -xvf etcd-${ETCD_VERSION}-linux-${ARCH}.tar.gz
sudo mv etcd-${ETCD_VERSION}-linux-${ARCH}/etcd* /usr/local/bin/

# Verificar instalación
etcd --version
etcdctl version
EOF

# 2. Descargar e instalar etcd en controlplane02
echo "Instalando etcd en controlplane02..."
vagrant ssh controlplane02 << 'EOF'
ETCD_VERSION="v3.5.9"
ARCH="amd64"

wget -q --show-progress --https-only --timestamping \
  "https://github.com/etcd-io/etcd/releases/download/${ETCD_VERSION}/etcd-${ETCD_VERSION}-linux-${ARCH}.tar.gz"

tar -xvf etcd-${ETCD_VERSION}-linux-${ARCH}.tar.gz
sudo mv etcd-${ETCD_VERSION}-linux-${ARCH}/etcd* /usr/local/bin/

etcd --version
EOF

# 3. Configurar etcd en controlplane01
echo "Configurando etcd en controlplane01..."
vagrant ssh controlplane01 << 'EOF'
# Obtener IP
PRIMARY_IP=$(ip addr show enp0s8 | grep "inet " | awk '{print $2}' | cut -d/ -f1)
ETCD_NAME=$(hostname -s)

# Crear directorios
sudo mkdir -p /etc/etcd /var/lib/etcd
sudo chmod 700 /var/lib/etcd

# Copiar certificados (ya deberían estar)
sudo cp /var/lib/kubernetes/pki/etcd-server.crt /etc/etcd/
sudo cp /var/lib/kubernetes/pki/etcd-server.key /etc/etcd/
sudo chmod 600 /etc/etcd/*.key

# Crear servicio systemd
cat << SERVICE | sudo tee /etc/systemd/system/etcd.service
[Unit]
Description=etcd
Documentation=https://github.com/coreos/etcd

[Service]
Type=notify
ExecStart=/usr/local/bin/etcd \\
  --name=${ETCD_NAME} \\
  --cert-file=/etc/etcd/etcd-server.crt \\
  --key-file=/etc/etcd/etcd-server.key \\
  --peer-cert-file=/etc/etcd/etcd-server.crt \\
  --peer-key-file=/etc/etcd/etcd-server.key \\
  --trusted-ca-file=/etc/etcd/ca.crt \\
  --peer-trusted-ca-file=/etc/etcd/ca.crt \\
  --peer-client-cert-auth \\
  --client-cert-auth \\
  --initial-advertise-peer-urls=https://${PRIMARY_IP}:2380 \\
  --listen-peer-urls=https://${PRIMARY_IP}:2380 \\
  --advertise-client-urls=https://${PRIMARY_IP}:2379 \\
  --listen-client-urls=https://${PRIMARY_IP}:2379,https://127.0.0.1:2379 \\
  --initial-cluster-token=etcd-cluster-0 \\
  --initial-cluster=controlplane01=https://192.168.56.11:2380,controlplane02=https://192.168.56.12:2380 \\
  --initial-cluster-state=new \\
  --data-dir=/var/lib/etcd
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE

# Iniciar etcd
sudo systemctl daemon-reload
sudo systemctl enable etcd
sudo systemctl start etcd

# Verificar
sleep 3
sudo systemctl status etcd --no-pager | head -20
EOF

# 4. Configurar etcd en controlplane02
echo "Configurando etcd en controlplane02..."
vagrant ssh controlplane02 << 'EOF'
# Obtener IP
PRIMARY_IP=$(ip addr show enp0s8 | grep "inet " | awk '{print $2}' | cut -d/ -f1)
ETCD_NAME=$(hostname -s)

# Crear directorios
sudo mkdir -p /etc/etcd /var/lib/etcd
sudo chmod 700 /var/lib/etcd

# Copiar certificados
sudo cp /var/lib/kubernetes/pki/etcd-server.crt /etc/etcd/
sudo cp /var/lib/kubernetes/pki/etcd-server.key /etc/etcd/
sudo chmod 600 /etc/etcd/*.key

# Crear servicio systemd (MISMO cluster, diferente IP)
cat << SERVICE | sudo tee /etc/systemd/system/etcd.service
[Unit]
Description=etcd
Documentation=https://github.com/coreos/etcd

[Service]
Type=notify
ExecStart=/usr/local/bin/etcd \\
  --name=${ETCD_NAME} \\
  --cert-file=/etc/etcd/etcd-server.crt \\
  --key-file=/etc/etcd/etcd-server.key \\
  --peer-cert-file=/etc/etcd/etcd-server.crt \\
  --peer-key-file=/etc/etcd/etcd-server.key \\
  --trusted-ca-file=/etc/etcd/ca.crt \\
  --peer-trusted-ca-file=/etc/etcd/ca.crt \\
  --peer-client-cert-auth \\
  --client-cert-auth \\
  --initial-advertise-peer-urls=https://${PRIMARY_IP}:2380 \\
  --listen-peer-urls=https://${PRIMARY_IP}:2380 \\
  --advertise-client-urls=https://${PRIMARY_IP}:2379 \\
  --listen-client-urls=https://${PRIMARY_IP}:2379,https://127.0.0.1:2379 \\
  --initial-cluster-token=etcd-cluster-0 \\
  --initial-cluster=controlplane01=https://192.168.56.11:2380,controlplane02=https://192.168.56.12:2380 \\
  --initial-cluster-state=new \\
  --data-dir=/var/lib/etcd
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE

# Iniciar etcd
sudo systemctl daemon-reload
sudo systemctl enable etcd
sudo systemctl start etcd

# Verificar
sleep 3
sudo systemctl status etcd --no-pager | head -20
EOF

# 5. Verificar cluster etcd
echo "Verificando cluster etcd..."
echo "--- Desde controlplane01 ---"
vagrant ssh controlplane01 << 'EOF'
sleep 5
sudo ETCDCTL_API=3 etcdctl member list \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/etcd/ca.crt \
  --cert=/etc/etcd/etcd-server.crt \
  --key=/etc/etcd/etcd-server.key
EOF

echo "--- Desde controlplane02 ---"
vagrant ssh controlplane02 << 'EOF'
sleep 3
sudo ETCDCTL_API=3 etcdctl member list \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/etcd/ca.crt \
  --cert=/etc/etcd/etcd-server.crt \
  --key=/etc/etcd/etcd-server.key
EOF

echo "=== ETCD CONFIGURADO ==="
