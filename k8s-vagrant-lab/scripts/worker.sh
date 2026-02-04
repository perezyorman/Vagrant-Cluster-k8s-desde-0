#!/bin/bash
set -e

echo "Uniendo Worker..."

# Instalar containerd
apt-get install -y containerd
mkdir -p /etc/containerd
containerd config default | sed 's/SystemdCgroup = false/SystemdCgroup = true/' > /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd

# Instalar solo kubelet y kubeadm
mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /' > /etc/apt/sources.list.d/kubernetes.list

apt-get update
apt-get install -y kubelet=1.34.3-1.1 kubeadm=1.34.3-1.1
apt-mark hold kubelet kubeadm

# Configurar kubelet
NODE_IP=$(hostname -I | awk '{print $2}')
cat <<EOF > /etc/default/kubelet
KUBELET_EXTRA_ARGS=--node-ip=$NODE_IP --system-reserved=cpu=100m,memory=200Mi --kube-reserved=cpu=100m,memory=200Mi
EOF
systemctl daemon-reload

# Esperar
until [ -f /vagrant/join-worker.sh ]; do sleep 10; done
until curl -sk https://192.168.1.150:6443/healthz | grep -q "ok"; do sleep 5; done
sleep 30

# Unirse
bash /vagrant/join-worker.sh --v=5

echo "Worker unido"
