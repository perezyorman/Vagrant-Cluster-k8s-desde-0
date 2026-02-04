#!/bin/bash
set -e

ROLE=$1      # MASTER o BACKUP
PRIORITY=$2  # 101 o 100

echo "=========================================="
echo "FASE 3: Configurando Keepalived en HAProxy"
echo "Role: $ROLE | Priority: $PRIORITY"
echo "=========================================="

apt-get install -y keepalived

# Detectar interfaz
INTERFACE=$(ip -o link show | awk -F': ' '{print $2}' | grep -E '^eth|^ens|^enp' | tail -1)
echo "Interfaz detectada: $INTERFACE"

# Script de check para HAProxy
cat <<'EOF' > /etc/keepalived/check_haproxy.sh
#!/bin/bash
# Verificar que HAProxy está corriendo
if systemctl is-active --quiet haproxy; then
    # Verificar que el proceso responde
    if pgrep -x "haproxy" > /dev/null; then
        exit 0
    fi
fi
exit 1
EOF
chmod +x /etc/keepalived/check_haproxy.sh

# Configuración Keepalived
cat <<EOF > /etc/keepalived/keepalived.conf
vrrp_script check_haproxy {
    script "/etc/keepalived/check_haproxy.sh"
    interval 2
    weight 2
    fall 2
    rise 2
}

vrrp_instance VI_1 {
    state $ROLE
    interface $INTERFACE
    virtual_router_id 51
    priority $PRIORITY
    advert_int 1
    nopreempt
    
    authentication {
        auth_type PASS
        auth_pass K8sHaLab2024!
    }
    
    virtual_ipaddress {
        192.168.1.150/24
    }
    
    track_script {
        check_haproxy
    }
    
    # Notificaciones
    notify_master "/bin/echo 'master' > /var/run/keepalived.state"
    notify_backup "/bin/echo 'backup' > /var/run/keepalived.state"
    notify_fault "/bin/echo 'fault' > /var/run/keepalived.state"
}
EOF

systemctl restart keepalived
systemctl enable keepalived

# Si es MASTER, esperar VIP
if [ "$ROLE" = "MASTER" ]; then
    echo "Esperando asignación de VIP 192.168.1.150..."
    for i in {1..30}; do
        if ip addr show $INTERFACE | grep -q "192.168.1.150"; then
            echo "VIP asignado correctamente:"
            ip addr show $INTERFACE | grep "192.168.1.150"
            break
        fi
        sleep 1
    done
fi

echo "Keepalived configurado como $ROLE"
