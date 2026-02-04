#!/bin/bash
set -e

echo "=========================================="
echo "FASE 2: Configurando Nodo HAProxy"
echo "=========================================="

# Instalar HAProxy
apt-get install -y haproxy

# Backup configuración
cp /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.backup

# Configuración HAProxy para Kubernetes API
cat <<'EOF' > /etc/haproxy/haproxy.cfg
global
    log /dev/log local0
    log /dev/log local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin expose-fd listeners
    stats timeout 30s
    user haproxy
    group haproxy
    daemon
    maxconn 4096
    nbthread 4

defaults
    log global
    mode tcp
    option tcplog
    option dontlognull
    timeout connect 5000
    timeout client 50000
    timeout server 50000
    timeout tunnel 1h

# Stats page
frontend stats
    bind *:8404
    mode http
    stats enable
    stats uri /stats
    stats refresh 10s
    stats admin if TRUE
    stats show-desc "K8s HAProxy Load Balancer"

# Frontend principal - Escucha en TODAS las interfaces
# El VIP será asignado por Keepalived
frontend kubernetes-apiserver
    bind *:6443
    default_backend kubernetes-apiserver

# Backend con los 3 masters
backend kubernetes-apiserver
    balance roundrobin
    option tcp-check
    tcp-check connect port 6443
    default-server inter 2s downinter 5s rise 2 fall 3 slowstart 60s maxconn 250 maxqueue 256 weight 100
    
    server master1 192.168.1.151:6443 check
    server master2 192.168.1.152:6443 check
    server master3 192.168.1.153:6443 check
EOF

# Validar configuración
haproxy -c -f /etc/haproxy/haproxy.cfg

# Habilitar y reiniciar
systemctl restart haproxy
systemctl enable haproxy

echo "HAProxy configurado"
echo "Estado de backends:"
echo "show stat" | nc -U /var/run/haproxy/admin.sock 2>/dev/null || echo "Socket no disponible todavía"
