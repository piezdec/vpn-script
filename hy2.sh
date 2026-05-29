#!/bin/bash
set -e

[[ $EUID -ne 0 ]] && echo "Run as root!" && exit 1

echo
read -rp "Enter the domain for Hysteria2 (e.g. cdn.example.com): " DOMAIN
DOMAIN=$(echo "$DOMAIN" | tr -d '[:space:]')
if [[ -z "$DOMAIN" ]]; then
    echo "No domain provided. Aborting."
    exit 1
fi

read -rp "Enter the masquerade URL (e.g. example.com): " MASQ_URL
MASQ_URL=$(echo "$MASQ_URL" | tr -d '[:space:]')
if [[ -z "$MASQ_URL" ]]; then
    echo "No masquerade URL provided. Aborting."
    exit 1
fi

echo
echo "    Domain:     $DOMAIN"
echo "    Masquerade: $MASQ_URL"
echo
read -rp "Is this correct? Continue with installation? [y/N]: " CONFIRM
if [[ ! "$CONFIRM" =~ ^[yY]$ ]]; then
    echo "Cancelled."
    exit 0
fi
echo

echo ">>> Checking that 443/UDP is free..."
if ss -ulnp | grep -q ':443 '; then
    echo "WARNING: port 443/UDP is already in use. Aborting."
    ss -ulnp | grep ':443 '
    exit 1
fi

echo ">>> Checking DNS..."
SERVER_IP=$(curl -4 -s ifconfig.me)
DOMAIN_IP=$(dig +short "$DOMAIN" | tail -n1)
echo "    Server IP: $SERVER_IP"
echo "    Domain IP: $DOMAIN_IP"
if [[ "$SERVER_IP" != "$DOMAIN_IP" ]]; then
    echo "WARNING: domain does not point to this server. Certificate cannot be issued."
    echo "Fix the A record and run again. Aborting."
    exit 1
fi

echo ">>> Installing Hysteria2..."
bash <(curl -fsSL https://get.hy2.sh/)

PASSWORD=$(openssl rand -base64 16)
echo ">>> Generated password: $PASSWORD"

echo ">>> Issuing Let's Encrypt certificate..."
NGINX_WAS_RUNNING=0
if systemctl is-active --quiet nginx; then
    NGINX_WAS_RUNNING=1
    systemctl stop nginx
fi

certbot certonly --standalone --non-interactive --agree-tos \
    --register-unsafely-without-email -d "$DOMAIN"

[[ $NGINX_WAS_RUNNING -eq 1 ]] && systemctl start nginx

if [[ ! -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]]; then
    echo "ERROR: certificate was not issued. Aborting."
    exit 1
fi

echo ">>> Copying certificates for the hysteria user..."
mkdir -p /etc/hysteria/certs
cp "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" /etc/hysteria/certs/
cp "/etc/letsencrypt/live/$DOMAIN/privkey.pem"   /etc/hysteria/certs/
chmod 644 /etc/hysteria/certs/fullchain.pem
chmod 600 /etc/hysteria/certs/privkey.pem
chown hysteria:hysteria /etc/hysteria/certs/fullchain.pem /etc/hysteria/certs/privkey.pem

echo ">>> Writing server config..."
cat > /etc/hysteria/config.yaml <<EOF
listen: :443

tls:
  cert: /etc/hysteria/certs/fullchain.pem
  key: /etc/hysteria/certs/privkey.pem

auth:
  type: password
  password: $PASSWORD

masquerade:
  type: proxy
  proxy:
    url: $MASQ_URL
    rewriteHost: true
EOF

echo ">>> Opening port 443/udp..."
ufw allow 443/udp 2>/dev/null || true

echo ">>> Starting service..."
systemctl enable --now hysteria-server.service
systemctl restart hysteria-server.service
sleep 2

echo ">>> Setting up certificate renewal hook..."
RENEWAL_CONF="/etc/letsencrypt/renewal/$DOMAIN.conf"
sed -i '/renew_hook/d' "$RENEWAL_CONF"
cat >> "$RENEWAL_CONF" <<EOF
renew_hook = cp /etc/letsencrypt/live/$DOMAIN/fullchain.pem /etc/hysteria/certs/ && cp /etc/letsencrypt/live/$DOMAIN/privkey.pem /etc/hysteria/certs/ && chmod 644 /etc/hysteria/certs/fullchain.pem && chmod 600 /etc/hysteria/certs/privkey.pem && chown hysteria:hysteria /etc/hysteria/certs/*.pem && systemctl restart hysteria-server
EOF

echo
echo "====================================================================="
if systemctl is-active --quiet hysteria-server.service; then
    echo "  DONE! Hysteria2 is running on $DOMAIN:443 (UDP)"
else
    echo "  WARNING: service failed to start. Check: journalctl -u hysteria-server -n 30"
fi
echo "====================================================================="
echo
echo "Client block for Mihomo/Clash.Meta (paste into proxies):"
echo
cat <<EOF
  - name: LV-hy2
    type: hysteria2
    server: $DOMAIN
    port: 443
    password: $PASSWORD
    sni: $DOMAIN
    skip-cert-verify: false
    udp: true
EOF
echo
echo "Password (save this!): $PASSWORD"
echo "====================================================================="
