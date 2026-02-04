#!/bin/bash
set -e

echo "Configurando sistema base..."

export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get upgrade -y

# Instalar solo lo esencial
apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    software-properties-common \
    vim \
    net-tools \
    conntrack \
    socat

# Kernel tuning mínimo para Kubernetes
cat <<EOF > /etc/sysctl.d/99-kubernetes-k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
net.ipv4.conf.all.forwarding = 1
vm.swappiness = 0
vm.overcommit_memory = 1
fs.inotify.max_user_watches = 524288
EOF

sysctl --system

# Cargar módulos esenciales
cat <<EOF > /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

# Deshabilitar swap
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

echo "Base configurada"
