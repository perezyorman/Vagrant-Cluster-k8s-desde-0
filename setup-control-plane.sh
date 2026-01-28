#!/bin/bash
# setup-control-plane.sh - Configurar Kubernetes Control Plane

set -e

echo "=== CONFIGURANDO CONTROL PLANE DE KUBERNETES ==="

# ============================================
# 1. DESCARGAR BINARIOS DE KUBERNETES
# ============================================
echo "1. Descargando binarios de Kubernetes..."

for node in controlplane01 controlplane02; do
  echo "--- Instalando en $node ---"
  vagrant ssh $node << 'EOF'
# Versión de Kubernetes
KUBERNETES_VERSION="v1.29.0"
ARCH="amd64"

# Descargar binarios
wget -q --show-progress --https-only --timestamping \
  "https://dl.k8s.io/${KUBERNETES_VERSION}/kubernetes-server-linux-${ARCH}.tar.gz"

# Extraer
tar -xvf kubernetes-server-linux-${ARCH}.tar.gz
cd kubernetes/server/bin

# Instalar binarios críticos
sudo mv kube-apiserver kube-controller-manager kube-scheduler kubectl /usr/local/bin/
sudo chmod +x /usr/local/bin/kube-*

# Verificar instalación
echo "Versiones instaladas:"
kube-apiserver --version
kube-controller-manager --version
kube-scheduler --version
EOF
done

# ============================================
# 2. CONFIGURAR KUBE-APISERVER
# ============================================
echo "2. Configurando kube-apiserver..."

# En controlplane01
echo "--- Configurando API Server en controlplane01 ---"
vagrant ssh controlplane01 << 'EOF'
# Variables
PRIMARY_IP=$(ip addr show enp0s8 | grep "inet " | awk '{print $2}' | cut -d/ -f1)
ETCD_SERVERS="https://192.168.56.11:2379,https://192.168.56.12:2379"
SERVICE_CIDR="10.96.0.0/12"
CLUSTER_CIDR="10.244.0.0/16"

# Crear directorio para logs
sudo mkdir -p /var/log/kubernetes

# Crear archivo de servicio kube-apiserver
cat << SERVICE | sudo tee /etc/systemd/system/kube-apiserver.service
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-apiserver \\
  --advertise-address=${PRIMARY_IP} \\
  --allow-privileged=true \\
  --apiserver-count=2 \\
  --audit-log-maxage=30 \\
  --audit-log-maxbackup=3 \\
  --audit-log-maxsize=100 \\
  --audit-log-path=/var/log/kubernetes/audit.log \\
  --authorization-mode=Node,RBAC \\
  --bind-address=0.0.0.0 \\
  --client-ca-file=/var/lib/kubernetes/pki/ca.crt \\
  --enable-admission-plugins=NodeRestriction \\
  --enable-bootstrap-token-auth=true \\
  --etcd-cafile=/var/lib/kubernetes/pki/ca.crt \\
  --etcd-certfile=/var/lib/kubernetes/pki/apiserver-kubelet-client.crt \\
  --etcd-keyfile=/var/lib/kubernetes/pki/apiserver-kubelet-client.key \\
  --etcd-servers=${ETCD_SERVERS} \\
  --event-ttl=1h \\
  --encryption-provider-config=/var/lib/kubernetes/encryption-config.yaml \\
  --kubelet-certificate-authority=/var/lib/kubernetes/pki/ca.crt \\
  --kubelet-client-certificate=/var/lib/kubernetes/pki/apiserver-kubelet-client.crt \\
  --kubelet-client-key=/var/lib/kubernetes/pki/apiserver-kubelet-client.key \\
  --kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname \\
  --proxy-client-cert-file=/var/lib/kubernetes/pki/apiserver-kubelet-client.crt \\
  --proxy-client-key-file=/var/lib/kubernetes/pki/apiserver-kubelet-client.key \\
  --requestheader-allowed-names=frontend-proxy-client \\
  --requestheader-client-ca-file=/var/lib/kubernetes/pki/ca.crt \\
  --requestheader-extra-headers-prefix=X-Remote-Extra- \\
  --requestheader-group-headers=X-Remote-Group \\
  --requestheader-username-headers=X-Remote-User \\
  --secure-port=6443 \\
  --service-account-issuer=https://kubernetes.default.svc.cluster.local \\
  --service-account-key-file=/var/lib/kubernetes/pki/service-account.crt \\
  --service-account-signing-key-file=/var/lib/kubernetes/pki/service-account.key \\
  --service-cluster-ip-range=${SERVICE_CIDR} \\
  --tls-cert-file=/var/lib/kubernetes/pki/kube-apiserver.crt \\
  --tls-private-key-file=/var/lib/kubernetes/pki/kube-apiserver.key
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE

# Habilitar e iniciar
sudo systemctl daemon-reload
sudo systemctl enable kube-apiserver
sudo systemctl start kube-apiserver

# Verificar
sleep 5
echo "Estado del API Server:"
sudo systemctl status kube-apiserver --no-pager | head -10
EOF

# En controlplane02
echo "--- Configurando API Server en controlplane02 ---"
vagrant ssh controlplane02 << 'EOF'
PRIMARY_IP=$(ip addr show enp0s8 | grep "inet " | awk '{print $2}' | cut -d/ -f1)
ETCD_SERVERS="https://192.168.56.11:2379,https://192.168.56.12:2379"
SERVICE_CIDR="10.96.0.0/12"

# Crear directorio para logs
sudo mkdir -p /var/log/kubernetes

# Mismo archivo de servicio, solo cambia advertise-address
cat << SERVICE | sudo tee /etc/systemd/system/kube-apiserver.service
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-apiserver \\
  --advertise-address=${PRIMARY_IP} \\
  --allow-privileged=true \\
  --apiserver-count=2 \\
  --audit-log-maxage=30 \\
  --audit-log-maxbackup=3 \\
  --audit-log-maxsize=100 \\
  --audit-log-path=/var/log/kubernetes/audit.log \\
  --authorization-mode=Node,RBAC \\
  --bind-address=0.0.0.0 \\
  --client-ca-file=/var/lib/kubernetes/pki/ca.crt \\
  --enable-admission-plugins=NodeRestriction \\
  --enable-bootstrap-token-auth=true \\
  --etcd-cafile=/var/lib/kubernetes/pki/ca.crt \\
  --etcd-certfile=/var/lib/kubernetes/pki/apiserver-kubelet-client.crt \\
  --etcd-keyfile=/var/lib/kubernetes/pki/apiserver-kubelet-client.key \\
  --etcd-servers=${ETCD_SERVERS} \\
  --event-ttl=1h \\
  --encryption-provider-config=/var/lib/kubernetes/encryption-config.yaml \\
  --kubelet-certificate-authority=/var/lib/kubernetes/pki/ca.crt \\
  --kubelet-client-certificate=/var/lib/kubernetes/pki/apiserver-kubelet-client.crt \\
  --kubelet-client-key=/var/lib/kubernetes/pki/apiserver-kubelet-client.key \\
  --kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname \\
  --proxy-client-cert-file=/var/lib/kubernetes/pki/apiserver-kubelet-client.crt \\
  --proxy-client-key-file=/var/lib/kubernetes/pki/apiserver-kubelet-client.key \\
  --requestheader-allowed-names=frontend-proxy-client \\
  --requestheader-client-ca-file=/var/lib/kubernetes/pki/ca.crt \\
  --requestheader-extra-headers-prefix=X-Remote-Extra- \\
  --requestheader-group-headers=X-Remote-Group \\
  --requestheader-username-headers=X-Remote-User \\
  --secure-port=6443 \\
  --service-account-issuer=https://kubernetes.default.svc.cluster.local \\
  --service-account-key-file=/var/lib/kubernetes/pki/service-account.crt \\
  --service-account-signing-key-file=/var/lib/kubernetes/pki/service-account.key \\
  --service-cluster-ip-range=${SERVICE_CIDR} \\
  --tls-cert-file=/var/lib/kubernetes/pki/kube-apiserver.crt \\
  --tls-private-key-file=/var/lib/kubernetes/pki/kube-apiserver.key
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE

sudo systemctl daemon-reload
sudo systemctl enable kube-apiserver
sudo systemctl start kube-apiserver

sleep 3
echo "Estado del API Server:"
sudo systemctl status kube-apiserver --no-pager | head -10
EOF

# ============================================
# 3. CONFIGURAR KUBE-CONTROLLER-MANAGER
# ============================================
echo "3. Configurando kube-controller-manager..."

for node in controlplane01 controlplane02; do
  echo "--- Configurando Controller Manager en $node ---"
  vagrant ssh $node << 'EOF'
# Crear directorio para kubeconfigs si no existe
sudo mkdir -p /etc/kubernetes

# Copiar kubeconfig (ya debería estar)
sudo cp /var/lib/kubernetes/pki/*.kubeconfig /etc/kubernetes/ 2>/dev/null || true

# Crear archivo de servicio
cat << SERVICE | sudo tee /etc/systemd/system/kube-controller-manager.service
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-controller-manager \\
  --bind-address=0.0.0.0 \\
  --cluster-cidr=10.244.0.0/16 \\
  --cluster-name=kubernetes \\
  --cluster-signing-cert-file=/var/lib/kubernetes/pki/ca.crt \\
  --cluster-signing-key-file=/var/lib/kubernetes/pki/ca.key \\
  --kubeconfig=/etc/kubernetes/kube-controller-manager.kubeconfig \\
  --leader-elect=true \\
  --root-ca-file=/var/lib/kubernetes/pki/ca.crt \\
  --service-account-private-key-file=/var/lib/kubernetes/pki/service-account.key \\
  --service-cluster-ip-range=10.96.0.0/12 \\
  --use-service-account-credentials=true \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE

sudo systemctl daemon-reload
sudo systemctl enable kube-controller-manager
sudo systemctl start kube-controller-manager

sleep 2
echo "Estado del Controller Manager:"
sudo systemctl status kube-controller-manager --no-pager | head -10
EOF
done

# ============================================
# 4. CONFIGURAR KUBE-SCHEDULER
# ============================================
echo "4. Configurando kube-scheduler..."

for node in controlplane01 controlplane02; do
  echo "--- Configurando Scheduler en $node ---"
  vagrant ssh $node << 'EOF'
# Crear configuración de scheduler
sudo mkdir -p /etc/kubernetes
cat << CONFIG | sudo tee /etc/kubernetes/scheduler.yaml
apiVersion: kubescheduler.config.k8s.io/v1
kind: KubeSchedulerConfiguration
clientConnection:
  kubeconfig: "/etc/kubernetes/kube-scheduler.kubeconfig"
leaderElection:
  leaderElect: true
CONFIG

# Crear archivo de servicio
cat << SERVICE | sudo tee /etc/systemd/system/kube-scheduler.service
[Unit]
Description=Kubernetes Scheduler
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-scheduler \\
  --config=/etc/kubernetes/scheduler.yaml \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE

sudo systemctl daemon-reload
sudo systemctl enable kube-scheduler
sudo systemctl start kube-scheduler

sleep 2
echo "Estado del Scheduler:"
sudo systemctl status kube-scheduler --no-pager | head -10
EOF
done

# ============================================
# 5. VERIFICACIÓN FINAL
# ============================================
echo "5. Verificando Control Plane..."

# Esperar a que todo esté listo
sleep 10

echo "--- Verificando servicios en controlplane01 ---"
vagrant ssh controlplane01 << 'EOF'
echo "1. Servicios activos:"
sudo systemctl status kube-apiserver kube-controller-manager kube-scheduler --no-pager | grep -A3 "Active:" | grep -v "●"

echo -e "\n2. Puerto 6443 (API Server):"
sudo ss -tlnp | grep 6443 || echo "Puerto 6443 no escuchando"

echo -e "\n3. Logs del API Server (últimas 5 líneas):"
sudo journalctl -u kube-apiserver --no-pager -n 5 | tail -5
EOF

echo "--- Verificando servicios en controlplane02 ---"
vagrant ssh controlplane02 << 'EOF'
echo "1. Servicios activos:"
sudo systemctl status kube-apiserver kube-controller-manager kube-scheduler --no-pager | grep -A3 "Active:" | grep -v "●"

echo -e "\n2. Puerto 6443 (API Server):"
sudo ss -tlnp | grep 6443 || echo "Puerto 6443 no escuchando"
EOF

# ============================================
# 6. CONFIGURAR KUBECTL EN HOST
# ============================================
echo "6. Configurando kubectl en tu máquina local..."

# Copiar admin.kubeconfig a ~/.kube
mkdir -p ~/.kube
cp admin.kubeconfig ~/.kube/config

# Verificar que funciona
echo "Probando conexión al cluster..."
kubectl cluster-info 2>/dev/null && echo "✓ Conexión exitosa" || echo "✗ Cluster no responde aún"

echo -e "\n=== CONTROL PLANE CONFIGURADO ==="
echo "Para verificar manualmente:"
echo "1. kubectl get nodes"
echo "2. kubectl get componentstatuses"
echo "3. vagrant ssh controlplane01"
echo "4. sudo systemctl status kube-apiserver"
