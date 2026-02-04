#!/bin/bash
set -e

echo "Inicializando Master1..."

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

# Configurar kubelet con límites de recursos
cat <<EOF > /etc/default/kubelet
KUBELET_EXTRA_ARGS=--node-ip=192.168.1.151 --system-reserved=cpu=100m,memory=200Mi --kube-reserved=cpu=100m,memory=200Mi
EOF
systemctl daemon-reload

# Configuración kubeadm optimizada
cat <<EOF > /root/kubeadm-config.yaml
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: 192.168.1.151
  bindPort: 6443
nodeRegistration:
  criSocket: unix:///var/run/containerd/containerd.sock
  kubeletExtraArgs:
    cgroup-driver: systemd
    node-ip: 192.168.1.151

---
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
kubernetesVersion: v1.34.3
controlPlaneEndpoint: "192.168.1.150:6443"
networking:
  serviceSubnet: "10.96.0.0/12"
  podSubnet: "10.244.0.0/16"
apiServer:
  certSANs:
    - "192.168.1.150"
    - "192.168.1.151"
    - "192.168.1.152"
    - "192.168.1.153"
  extraArgs:
    authorization-mode: "Node,RBAC"
    # Reducir uso de recursos
    request-timeout: "300s"
etcd:
  local:
    dataDir: /var/lib/etcd
    extraArgs:
      listen-client-urls: "https://127.0.0.1:2379,https://192.168.1.151:2379"
      advertise-client-urls: "https://192.168.1.151:2379"
      listen-peer-urls: "https://192.168.1.151:2380"
      initial-advertise-peer-urls: "https://192.168.1.151:2380"
      initial-cluster: "master1=https://192.168.1.151:2380"
      # Límites de recursos para etcd
      quota-backend-bytes: "8589934592"
      auto-compaction-retention: "1h"

---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
systemReserved:
  cpu: "100m"
  memory: "200Mi"
kubeReserved:
  cpu: "100m"
  memory: "200Mi"
evictionHard:
  memory.available: "100Mi"
  nodefs.available: "10%"
EOF

# Inicializar
kubeadm init --config=/root/kubeadm-config.yaml --upload-certs --v=5

# Configurar kubectl
mkdir -p /root/.kube /home/vagrant/.kube /vagrant/.kube
cp /etc/kubernetes/admin.conf /root/.kube/config
cp /etc/kubernetes/admin.conf /home/vagrant/.kube/config
cp /etc/kubernetes/admin.conf /vagrant/.kube/config
chown $(id -u):$(id -g) /root/.kube/config
chown vagrant:vagrant /home/vagrant/.kube/config
chmod 644 /vagrant/.kube/config

# Generar tokens
kubeadm token create --print-join-command > /vagrant/join-worker.sh
chmod +x /vagrant/join-worker.sh

CERT_KEY=$(kubeadm init phase upload-certs --upload-certs 2>/dev/null | tail -1)
JOIN_CMD=$(kubeadm token create --print-join-command)
echo "$JOIN_CMD --control-plane --certificate-key $CERT_KEY" > /vagrant/join-master.sh
chmod +x /vagrant/join-master.sh

echo "Master1 listo"
