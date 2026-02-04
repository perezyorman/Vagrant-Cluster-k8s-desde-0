#!/bin/bash
set -e

export KUBECONFIG=/etc/kubernetes/admin.conf

echo "Instalando Cilium..."

# Esperar nodo
until kubectl get nodes | grep -q "Ready"; do
    echo "Esperando nodo..."
    sleep 5
done

# Instalar Cilium CLI
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
curl -sL --fail https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-amd64.tar.gz | tar xzvfC - /usr/local/bin

# Instalar Cilium con recursos mínimos
cilium install \
    --version 1.15.0 \
    --set ipam.mode=kubernetes \
    --set kubeProxyReplacement=true \
    --set k8sServiceHost=192.168.1.150 \
    --set k8sServicePort=6443 \
    --set hubble.enabled=true \
    --set hubble.relay.enabled=true \
    --set hubble.ui.enabled=true \
    --set operator.resources.requests.cpu=100m \
    --set operator.resources.requests.memory=128Mi \
    --set operator.resources.limits.cpu=500m \
    --set operator.resources.limits.memory=256Mi \

# Habilitar Hubble
cilium hubble enable --ui

echo "Cilium instalado"
cilium status
