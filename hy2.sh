#!/bin/bash
set -e

#################### НАСТРОЙКИ ########################################
EMAIL=""                                   # для уведомлений Let's Encrypt; можно оставить пустым
DEFAULT_MASQ_URL="https://www.bing.com/"   # значение по умолчанию для маскарада
#######################################################################

# --- проверка прав ---
[[ $EUID -ne 0 ]] && echo "Запустите от root!" && exit 1

# --- интерактивный ввод ---
echo
read -rp "Введите домен для Hysteria2 (например, s5.example.com): " DOMAIN
DOMAIN=$(echo "$DOMAIN" | tr -d '[:space:]')
if [[ -z "$DOMAIN" ]]; then
    echo "Домен не указан. Прерываю."
    exit 1
fi

read -rp "Введите URL для маскарада [по умолчанию: $DEFAULT_MASQ_URL]: " MASQ_URL
MASQ_URL=$(echo "$MASQ_URL" | tr -d '[:space:]')
[[ -z "$MASQ_URL" ]] && MASQ_URL="$DEFAULT_MASQ_URL"

echo
echo "    Домен:    $DOMAIN"
echo "    Маскарад: $MASQ_URL"
echo
read -rp "Всё верно? Продолжить установку? [y/N]: " CONFIRM
if [[ ! "$CONFIRM" =~ ^[yY]$ ]]; then
    echo "Отмена."
    exit 0
fi
echo

echo ">>> Проверяю, что 443/UDP свободен..."
if ss -ulnp | grep -q ':443 '; then
    echo "ВНИМАНИЕ: порт 443/UDP уже занят. Прерываю."
    ss -ulnp | grep ':443 '
    exit 1
fi

echo ">>> Проверяю DNS (домен должен указывать на этот сервер)..."
SERVER_IP=$(curl -4 -s ifconfig.me)
DOMAIN_IP=$(dig +short "$DOMAIN" | tail -n1)
echo "    IP сервера: $SERVER_IP"
echo "    IP домена:  $DOMAIN_IP"
if [[ "$SERVER_IP" != "$DOMAIN_IP" ]]; then
    echo "ВНИМАНИЕ: домен не указывает на этот сервер. Сертификат не выпустится."
    echo "Поправьте A-запись и запустите снова. Прерываю."
    exit 1
fi

# --- установка hysteria2 ---
echo ">>> Устанавливаю Hysteria2..."
bash <(curl -fsSL https://get.hy2.sh/)

# --- генерация пароля ---
PASSWORD=$(openssl rand -base64 16)
echo ">>> Сгенерирован пароль: $PASSWORD"

# --- сертификат ---
echo ">>> Выпускаю сертификат Let's Encrypt..."
EMAIL_ARG="--register-unsafely-without-email"
[[ -n "$EMAIL" ]] && EMAIL_ARG="-m $EMAIL --no-eff-email"

# Если 80 занят nginx - на время выпуска останавливаем его
NGINX_WAS_RUNNING=0
if systemctl is-active --quiet nginx; then
    NGINX_WAS_RUNNING=1
    systemctl stop nginx
fi

certbot certonly --standalone --non-interactive --agree-tos $EMAIL_ARG -d "$DOMAIN"

[[ $NGINX_WAS_RUNNING -eq 1 ]] && systemctl start nginx

if [[ ! -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]]; then
    echo "ОШИБКА: сертификат не выпустился. Прерываю."
    exit 1
fi

# --- копируем сертификаты в папку для hysteria (решает permission denied) ---
echo ">>> Копирую сертификаты для пользователя hysteria..."
mkdir -p /etc/hysteria/certs
cp "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" /etc/hysteria/certs/
cp "/etc/letsencrypt/live/$DOMAIN/privkey.pem"   /etc/hysteria/certs/
chmod 644 /etc/hysteria/certs/fullchain.pem
chmod 600 /etc/hysteria/certs/privkey.pem
chown hysteria:hysteria /etc/hysteria/certs/fullchain.pem /etc/hysteria/certs/privkey.pem

# --- генерация конфига ---
echo ">>> Пишу конфиг сервера..."
cat > /etc/hysteria/config.yaml <<EOF
listen: :443

tls:
  cert: /etc/hysteria/certs/fullchain.pem
  key: /etc/hysteria/certs/privkey.pem

auth:
  type: password
  password: $PASSWORD

# Маскарад: при заходе обычным браузером сервер притворяется веб-сайтом.
masquerade:
  type: proxy
  proxy:
    url: $MASQ_URL
    rewriteHost: true
EOF

# --- firewall ---
echo ">>> Открываю порт 443/udp..."
ufw allow 443/udp 2>/dev/null || true

# --- запуск ---
echo ">>> Запускаю сервис..."
systemctl enable --now hysteria-server.service
systemctl restart hysteria-server.service
sleep 2

# --- автообновление сертификата ---
echo ">>> Настраиваю хук автообновления сертификата..."
RENEWAL_CONF="/etc/letsencrypt/renewal/$DOMAIN.conf"
sed -i '/renew_hook/d' "$RENEWAL_CONF"
cat >> "$RENEWAL_CONF" <<EOF
renew_hook = cp /etc/letsencrypt/live/$DOMAIN/fullchain.pem /etc/hysteria/certs/ && cp /etc/letsencrypt/live/$DOMAIN/privkey.pem /etc/hysteria/certs/ && chmod 644 /etc/hysteria/certs/fullchain.pem && chmod 600 /etc/hysteria/certs/privkey.pem && chown hysteria:hysteria /etc/hysteria/certs/*.pem && systemctl restart hysteria-server
EOF

# --- итог ---
echo
echo "====================================================================="
if systemctl is-active --quiet hysteria-server.service; then
    echo "  ГОТОВО! Hysteria2 работает на $DOMAIN:443 (UDP)"
else
    echo "  ВНИМАНИЕ: сервис не запустился. Проверьте: journalctl -u hysteria-server -n 30"
fi
echo "====================================================================="
echo
echo "Клиентский блок для Mihomo/Clash.Meta (вставьте в proxies):"
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
echo "Пароль (сохраните!): $PASSWORD"
echo "====================================================================="
