#!/bin/bash
# cleanup-lab.sh

echo "=== LIMPIANDO LABORATORIO ANTERIOR ==="

# 1. Destruir VMs de Vagrant
vagrant destroy -f

# 2. Eliminar archivos de Vagrant
rm -rf .vagrant Vagrantfile

# 3. Eliminar certificados (si estás en ~/k8s-lab)
cd ~/k8s-lab 2>/dev/null && rm -rf *.pem *.csr *.json *.kubeconfig *.yaml

# 4. Eliminar configuración de kubectl
rm -rf ~/.kube/config

# 5. Eliminar de /etc/hosts
sudo sed -i '/192.168.56/d' /etc/hosts

echo "✓ Laboratorio limpiado"
