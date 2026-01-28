#!/bin/bash
# ============================================
# KUBERNETES THE HARD WAY - SETUP COMPLETO
# Versión: 1.0 - Optimizado para Vagrant
# ============================================

set -e  # Detiene el script si hay error

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== INICIANDO KUBERNETES THE HARD WAY ===${NC}"

# ============================================
# FASE 1: CONFIGURACIÓN DE VAGRANT
# ============================================
echo -e "\n${YELLOW}--- FASE 1: Creando VMs con Vagrant ---${NC}"

cat > Vagrantfile << 'VAGRANT'
# -*- mode: ruby -*-
# vi: set ft=ruby sw=2 ts=2 sts=2:

# CONFIGURACIÓN PARA KUBERNETES THE HARD WAY
# Optimizado para laptop con 16GB RAM

# Configuración de RED
IP_NW = "192.168.56."

# Número de nodos
NUM_CONTROL_NODES = 2
NUM_WORKER_NODES = 2

# Configuración de RECURSOS
CONTROL_NODE_CONFIG = {
  "ram" => 2048,     # 2GB
  "cpu" => 2
}

WORKER_NODE_CONFIG = {
  "ram" => 3072,     # 3GB
  "cpu" => 2
}

# Direcciones IP fijas (IMPORTANTE para certificados)
CONTROL_IPS = ["192.168.56.11", "192.168.56.12"]
WORKER_IPS = ["192.168.56.21", "192.168.56.22"]

Vagrant.configure("2") do |config|
  config.vm.box = "ubuntu/jammy64"
  config.vm.boot_timeout = 600
  config.vm.box_check_update = false

  # Control Planes
  (1..NUM_CONTROL_NODES).each do |i|
    config.vm.define "controlplane0#{i}" do |node|
      node.vm.hostname = "controlplane0#{i}"
      node.vm.network :private_network, ip: CONTROL_IPS[i-1]
      
      node.vm.provider "virtualbox" do |vb|
        vb.name = "k8s-cp#{i}"
        vb.memory = CONTROL_NODE_CONFIG["ram"]
        vb.cpus = CONTROL_NODE_CONFIG["cpu"]
        vb.customize ["modifyvm", :id, "--ioapic", "on"]
        vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
      end
      
      # Provisionamiento inicial
      node.vm.provision "shell", inline: <<-SHELL
        apt-get update
        apt-get install -y curl wget vim net-tools
        
        # Configurar hosts
        echo "192.168.56.11 controlplane01" >> /etc/hosts
        echo "192.168.56.12 controlplane02" >> /etc/hosts
        echo "192.168.56.21 worker01" >> /etc/hosts
        echo "192.168.56.22 worker02" >> /etc/hosts
      SHELL
    end
  end

  # Workers
  (1..NUM_WORKER_NODES).each do |i|
    config.vm.define "worker0#{i}" do |node|
      node.vm.hostname = "worker0#{i}"
      node.vm.network :private_network, ip: WORKER_IPS[i-1]
      
      node.vm.provider "virtualbox" do |vb|
        vb.name = "k8s-worker#{i}"
        vb.memory = WORKER_NODE_CONFIG["ram"]
        vb.cpus = WORKER_NODE_CONFIG["cpu"]
        vb.customize ["modifyvm", :id, "--ioapic", "on"]
      end
      
      node.vm.provision "shell", inline: <<-SHELL
        apt-get update
        apt-get install -y curl wget vim net-tools
        echo "192.168.56.11 controlplane01" >> /etc/hosts
        echo "192.168.56.12 controlplane02" >> /etc/hosts
        echo "192.168.56.21 worker01" >> /etc/hosts
        echo "192.168.56.22 worker02" >> /etc/hosts
      SHELL
    end
  end
end
VAGRANT

echo "Creando VMs con Vagrant..."
vagrant up

# ============================================
# FASE 2: PREPARAR TODAS LAS VMs
# ============================================
echo -e "\n${YELLOW}--- FASE 2: Preparando todas las VMs ---${NC}"

cat > prepare-all-vms.sh << 'PREPARE'
#!/bin/bash
run_on_all() {
  for NODE in controlplane01 controlplane02 worker01 worker02; do
    echo "=== Ejecutando en $NODE: $1 ==="
    vagrant ssh $NODE -c "$1" || true
  done
}

# 1. Actualizar sistema
run_on_all "sudo apt-get update && sudo apt-get upgrade -y"

# 2. Instalar dependencias CRÍTICAS
run_on_all "sudo apt-get install -y \
  apt-transport-https \
  ca-certificates \
  curl \
  gnupg \
  lsb-release \
  net-tools \
  socat \
  conntrack \
  ipset"

# 3. Deshabilitar swap
run_on_all "sudo swapoff -a"
run_on_all "sudo sed -i '/ swap / s/^/#/' /etc/fstab"

# 4. Cargar módulos del kernel
run_on_all "sudo modprobe overlay"
run_on_all "sudo modprobe br_netfilter"

# 5. Configurar sysctl
run_on_all "cat << 'CONFIG' | sudo tee /etc/sysctl.d/kubernetes.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
CONFIG"

run_on_all "sudo sysctl --system"

# 6. Instalar containerd
run_on_all "sudo apt-get install -y containerd"

# 7. Configurar containerd
run_on_all "sudo mkdir -p /etc/containerd"
run_on_all "containerd config default | sudo tee /etc/containerd/config.toml"
run_on_all "sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml"
run_on_all "sudo systemctl restart containerd"
run_on_all "sudo systemctl enable containerd"

echo "=== PREPARACIÓN COMPLETADA ==="
PREPARE

chmod +x prepare-all-vms.sh
./prepare-all-vms.sh

# ============================================
# FASE 3: INSTALAR HERRAMIENTAS CLIENTE
# ============================================
echo -e "\n${YELLOW}--- FASE 3: Instalando herramientas en HOST ---${NC}"

# Crear directorio de trabajo
mkdir -p ~/k8s-lab
cd ~/k8s-lab

# Instalar kubectl
echo "Instalando kubectl..."
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/

# Instalar cfssl
echo "Instalando cfssl..."
wget -q --show-progress --https-only --timestamping \
  https://github.com/cloudflare/cfssl/releases/download/v1.6.4/cfssl_1.6.4_linux_amd64 \
  https://github.com/cloudflare/cfssl/releases/download/v1.6.4/cfssljson_1.6.4_linux_amd64

chmod +x cfssl_1.6.4_linux_amd64 cfssljson_1.6.4_linux_amd64
sudo mv cfssl_1.6.4_linux_amd64 /usr/local/bin/cfssl
sudo mv cfssljson_1.6.4_linux_amd64 /usr/local/bin/cfssljson

# ============================================
# FASE 4: GENERAR TODOS LOS CERTIFICADOS
# ============================================
echo -e "\n${YELLOW}--- FASE 4: Generando certificados TLS ---${NC}"

# 4.1 CA Configuration
cat > ca-config.json <<EOF
{
  "signing": {
    "default": {
      "expiry": "8760h"
    },
    "profiles": {
      "kubernetes": {
        "usages": ["signing", "key encipherment", "server auth", "client auth"],
        "expiry": "8760h"
      }
    }
  }
}
EOF

# 4.2 Certificate Authority
cat > ca-csr.json <<EOF
{
  "CN": "Kubernetes",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "Portland",
      "O": "Kubernetes",
      "OU": "Kubernetes The Hard Way",
      "ST": "Oregon"
    }
  ]
}
EOF

cfssl gencert -initca ca-csr.json | cfssljson -bare ca

# 4.3 Admin Certificate
cat > admin-csr.json <<EOF
{
  "CN": "admin",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "Portland",
      "O": "system:masters",
      "OU": "Kubernetes The Hard Way",
      "ST": "Oregon"
    }
  ]
}
EOF

cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes admin-csr.json | cfssljson -bare admin

# 4.4 Worker Certificates
for i in 1 2; do
  cat > worker0${i}-csr.json <<EOF
{
  "CN": "system:node:worker0${i}",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "Portland",
      "O": "system:nodes",
      "OU": "Kubernetes The Hard Way",
      "ST": "Oregon"
    }
  ]
}
EOF
  
  cfssl gencert \
    -ca=ca.pem \
    -ca-key=ca-key.pem \
    -config=ca-config.json \
    -hostname=worker0${i},192.168.56.2${i} \
    -profile=kubernetes \
    worker0${i}-csr.json | cfssljson -bare worker0${i}
done

# 4.5 Control Plane Certificates
declare -A certs=(
  ["kube-controller-manager"]="system:kube-controller-manager"
  ["kube-scheduler"]="system:kube-scheduler"
  ["kube-proxy"]="system:kube-proxy"
  ["kubernetes"]="kubernetes"
  ["service-account"]="service-accounts"
  ["etcd-server"]="etcd"
)

for cert in "${!certs[@]}"; do
  CN=${certs[$cert]}
  
  cat > ${cert}-csr.json <<EOF
{
  "CN": "${CN}",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "Portland",
      "O": "Kubernetes",
      "OU": "Kubernetes The Hard Way",
      "ST": "Oregon"
    }
  ]
}
EOF
  
  if [ "$cert" == "kubernetes" ]; then
    # API Server necesita todas las IPs
    cfssl gencert \
      -ca=ca.pem \
      -ca-key=ca-key.pem \
      -config=ca-config.json \
      -hostname=10.32.0.1,192.168.56.11,192.168.56.12,192.168.56.21,192.168.56.22,127.0.0.1,kubernetes.default \
      -profile=kubernetes \
      ${cert}-csr.json | cfssljson -bare ${cert}
  elif [ "$cert" == "etcd-server" ]; then
    # etcd necesita IPs de control planes
    cfssl gencert \
      -ca=ca.pem \
      -ca-key=ca-key.pem \
      -config=ca-config.json \
      -hostname=192.168.56.11,192.168.56.12,127.0.0.1 \
      -profile=kubernetes \
      ${cert}-csr.json | cfssljson -bare ${cert}
  else
    # Otros certificados
    cfssl gencert \
      -ca=ca.pem \
      -ca-key=ca-key.pem \
      -config=ca-config.json \
      -profile=kubernetes \
      ${cert}-csr.json | cfssljson -bare ${cert}
  fi
done

echo -e "${GREEN}✓ Todos los certificados generados${NC}"

# ============================================
# FASE 5: DISTRIBUIR CERTIFICADOS
# ============================================
echo -e "\n${YELLOW}--- FASE 5: Distribuyendo certificados ---${NC}"

cat > distribute-certs.sh << 'DISTRIBUTE'
#!/bin/bash

# 1. Crear directorios en todos los nodos
for NODE in controlplane01 controlplane02 worker01 worker02; do
  vagrant ssh $NODE -c "sudo mkdir -p /etc/kubernetes/pki /var/lib/kubernetes/pki /etc/etcd"
done

# 2. Distribuir CA a todos los nodos
for NODE in controlplane01 controlplane02 worker01 worker02; do
  cat ca.pem | vagrant ssh $NODE -c "sudo tee /etc/kubernetes/pki/ca.pem > /dev/null"
  cat ca.pem | vagrant ssh $NODE -c "sudo tee /var/lib/kubernetes/pki/ca.crt > /dev/null"
done

# 3. Mapa de distribución
declare -A cert_map=(
  # Control planes
  ["controlplane01,controlplane02"]="
    admin.pem:admin.crt admin-key.pem:admin.key
    kubernetes.pem:kube-apiserver.crt kubernetes-key.pem:kube-apiserver.key
    kubernetes.pem:apiserver-kubelet-client.crt kubernetes-key.pem:apiserver-kubelet-client.key
    service-account.pem:service-account.crt service-account-key.pem:service-account.key
    kube-controller-manager.pem:kube-controller-manager.crt kube-controller-manager-key.pem:kube-controller-manager.key
    kube-scheduler.pem:kube-scheduler.crt kube-scheduler-key.pem:kube-scheduler.key
    etcd-server.pem:etcd-server.crt etcd-server-key.pem:etcd-server.key
  "
  
  # Workers
  ["worker01"]="worker01.pem:worker01.crt worker01-key.pem:worker01.key"
  ["worker02"]="worker02.pem:worker02.crt worker02-key.pem:worker02.key"
  
  # Todos los nodos
  ["controlplane01,controlplane02,worker01,worker02"]="
    kube-proxy.pem:kube-proxy.crt kube-proxy-key.pem:kube-proxy.key
  "
)

# 4. Distribuir según mapa
for nodes in "${!cert_map[@]}"; do
  IFS=',' read -r -a node_array <<< "$nodes"
  cert_list="${cert_map[$nodes]}"
  
  for cert_pair in $cert_list; do
    IFS=':' read -r source dest <<< "$cert_pair"
    
    if [ -f "$source" ]; then
      for node in "${node_array[@]}"; do
        echo "Copiando $source -> $dest en $node"
        cat "$source" | vagrant ssh $node -c "sudo tee /var/lib/kubernetes/pki/$dest > /dev/null"
        
        # Si es .key, asegurar permisos
        if [[ "$dest" == *.key ]]; then
          vagrant ssh $node -c "sudo chmod 600 /var/lib/kubernetes/pki/$dest"
        fi
      done
    fi
  done
done

# 5. Enlaces simbólicos para etcd
for node in controlplane01 controlplane02; do
  vagrant ssh $node -c "sudo ln -sf /var/lib/kubernetes/pki/ca.crt /etc/etcd/ca.crt"
  vagrant ssh $node -c "sudo cp /var/lib/kubernetes/pki/etcd-server.crt /etc/etcd/"
  vagrant ssh $node -c "sudo cp /var/lib/kubernetes/pki/etcd-server.key /etc/etcd/"
done

echo "✓ Certificados distribuidos"
DISTRIBUTE

chmod +x distribute-certs.sh
./distribute-certs.sh

# ============================================
# FASE 6: KUBECONFIGS
# ============================================
echo -e "\n${YELLOW}--- FASE 6: Creando kubeconfigs ---${NC}"

KUBERNETES_PUBLIC_ADDRESS="192.168.56.11"

# Función para crear kubeconfig
create_kubeconfig() {
  local name=$1
  local user=$2
  local cert=$3
  local key=$4
  local server=$5
  
  kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=ca.pem \
    --embed-certs=true \
    --server=https://${server}:6443 \
    --kubeconfig=${name}.kubeconfig

  kubectl config set-credentials ${user} \
    --client-certificate=${cert} \
    --client-key=${key} \
    --embed-certs=true \
    --kubeconfig=${name}.kubeconfig

  kubectl config set-context default \
    --cluster=kubernetes-the-hard-way \
    --user=${user} \
    --kubeconfig=${name}.kubeconfig

  kubectl config use-context default --kubeconfig=${name}.kubeconfig
}

# Crear todos los kubeconfigs
create_kubeconfig "admin" "admin" "admin.pem" "admin-key.pem" "${KUBERNETES_PUBLIC_ADDRESS}"
create_kubeconfig "kube-controller-manager" "system:kube-controller-manager" "kube-controller-manager.pem" "kube-controller-manager-key.pem" "127.0.0.1"
create_kubeconfig "kube-scheduler" "system:kube-scheduler" "kube-scheduler.pem" "kube-scheduler-key.pem" "127.0.0.1"
create_kubeconfig "kube-proxy" "system:kube-proxy" "kube-proxy.pem" "kube-proxy-key.pem" "${KUBERNETES_PUBLIC_ADDRESS}"

for i in 1 2; do
  create_kubeconfig "worker0${i}" "system:node:worker0${i}" "worker0${i}.pem" "worker0${i}-key.pem" "${KUBERNETES_PUBLIC_ADDRESS}"
done

# ============================================
# FASE 7: ENCRYPTION CONFIG
# ============================================
echo -e "\n${YELLOW}--- FASE 7: Configuración de encriptación ---${NC}"

ENCRYPTION_KEY=$(head -c 32 /dev/urandom | base64)

cat > encryption-config.yaml <<EOF
kind: EncryptionConfig
apiVersion: v1
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: ${ENCRYPTION_KEY}
      - identity: {}
EOF

# Distribuir a control planes
for node in controlplane01 controlplane02; do
  cat encryption-config.yaml | vagrant ssh $node -c "sudo tee /var/lib/kubernetes/encryption-config.yaml > /dev/null"
done

# ============================================
# MENÚ INTERACTIVO
# ============================================
echo -e "\n${GREEN}=== SETUP COMPLETADO ===${NC}"
echo -e "\n${YELLOW}¿Qué quieres hacer ahora?${NC}"
echo "1. Continuar con etcd (FASE 8)"
echo "2. Verificar estado actual"
echo "3. Salir y continuar manualmente"
echo -n "Selecciona una opción (1-3): "

read choice

case $choice in
  1)
    echo "Continuando con etcd..."
    # Aquí continuarías con los pasos de etcd
    ;;
  2)
    echo -e "\n${YELLOW}=== VERIFICACIÓN ===${NC}"
    echo "VMs:"
    vagrant status
    echo -e "\nCertificados generados:"
    ls -la *.pem | wc -l
    echo " archivos .pem"
    echo -e "\nKubeconfigs:"
    ls -la *.kubeconfig
    ;;
  3)
    echo "Saliendo. Puedes continuar manualmente."
    ;;
  *)
    echo "Opción no válida"
    ;;
esac

echo -e "\n${GREEN}Recuerda:${NC}"
echo "1. Los certificados están en: ~/k8s-lab/"
echo "2. Comandos útiles:"
echo "   vagrant ssh controlplane01"
echo "   kubectl --kubeconfig=admin.kubeconfig cluster-info"
echo "3. Siguiente paso: Configurar etcd cluster"
