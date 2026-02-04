#!/bin/bash
set -e

echo "Uniendo Master al cluster..."

# Instalar containerd
apt-get install -y containerd
mkdir -p /etc/containerd
containerd config default | sed 's/SystemdCgroup = false/SystemdCgroup = true/' > /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd

# Instalar Kubernetes
mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /' > /etc/apt/sources.list.d/kubernetes.list

apt-get update
apt-get install -y kubelet=1.34.3-1.1 kubeadm=1.34.3-1.1 kubectl=1.34.3-1.1
apt-mark hold kubelet kubeadm kubectl

# Configurar kubelet con reservas mínimas
NODE_IP=$(hostname -I | awk '{print $2}')
cat <<EOF > /etc/default/kubelet
KUBELET_EXTRA_ARGS=--node-ip=$NODE_IP --system-reserved=cpu=100m,memory=200Mi --kube-reserved=cpu=100m,memory=200Mi
EOF
systemctl daemon-reload

# Esperar archivos y estabilidad
until [ -f /vagrant/join-master.sh ]; do sleep 10; done
until curl -sk https://192.168.1.150:6443/healthz | grep -q "ok"; do sleep 5; done

# Delay crítico para etcd
echo "Esperando 90 segundos para sincronización de etcd..."
sleep 90

# Intentar unirse con retry
for i in {1..2}; do
    if bash /vagrant/join-master.sh --v=5; then
        echo "Unión exitosa"
        break
    fi
    echo "Reintentando en 30 segundos... ($i/2)"
    sleep 150
done

# Configurar kubectl
mkdir -p /root/.kube /home/vagrant/.kube
cp /etc/kubernetes/admin.conf /root/.kube/config
cp /etc/kubernetes/admin.conf /home/vagrant/.kube/config
chown $(id -u):$(id -g) /root/.kube/config
chown vagrant:vagrant /home/vagrant/.kube/config

echo "Master unido"
