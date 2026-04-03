#!/bin/bash
#################### x-ui-pro + Nextcloud Snap + Hysteria2 + MTProto ## based on x-ui-pro v2.4.3 ##########
[[ $EUID -ne 0 ]] && echo "not root!" && sudo su -
##############################INFO######################################################################
msg_ok() { echo -e "\e[1;42m $1 \e[0m";}
msg_err() { echo -e "\e[1;41m $1 \e[0m";}
msg_inf() { echo -e "\e[1;34m$1\e[0m";}
echo;msg_inf '           ___    _   _   _  '    ;
msg_inf          ' \/ __ | |  | __ |_) |_) / \ '        ;
msg_inf          ' /\    |_| _|_   |   | \ \_/ '        ;
msg_inf      ' + Nextcloud + Hysteria2 + MTProto '   ; echo
##################################Variables#############################################################
XUIDB="/etc/x-ui/x-ui.db";domain="";UNINSTALL="x";INSTALL="n";PNLNUM=1;CFALLOW="n";CLASH=0;CUSTOMWEBSUB=0
INSTALL_HYSTERIA=""
INSTALL_MTPROTO=""
Pak=$(type apt &>/dev/null && echo "apt" || echo "yum")
systemctl stop x-ui 2>/dev/null
rm -rf /etc/systemd/system/x-ui.service
rm -rf /usr/local/x-ui
rm -rf /etc/x-ui
rm -rf /etc/nginx/sites-enabled/*
rm -rf /etc/nginx/sites-available/*
rm -rf /etc/nginx/stream-enabled/*

##################################generate ports and paths##############################################
get_port() {
    echo $(( ((RANDOM<<15)|RANDOM) % 49152 + 10000 ))
}

gen_random_string() {
    local length="$1"
    head -c 4096 /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c "$length"
    echo
}

check_free() {
    local port=$1
    nc -z 127.0.0.1 $port &>/dev/null
    return $?
}

make_port() {
    while true; do
        PORT=$(get_port)
        if ! check_free $PORT; then
            echo $PORT
            break
        fi
    done
}

sub_port=$(make_port)
panel_port=$(make_port)
web_path=$(gen_random_string 10)
sub2singbox_path=$(gen_random_string 10)
sub_path=$(gen_random_string 10)
json_path=$(gen_random_string 10)
panel_path=$(gen_random_string 10)
ws_port=$(make_port)
trojan_port=$(make_port)
ws_path=$(gen_random_string 10)
trojan_path=$(gen_random_string 10)
xhttp_path=$(gen_random_string 10)
config_username=$(gen_random_string 10)
config_password=$(gen_random_string 10)
AUTODOMAIN="n"
NC_PORT=8181

# Hysteria2 password (safe for sed - no special chars)
hy2_password=$(head -c 4096 /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c 32)

################################Get arguments###########################################################
while [ "$#" -gt 0 ]; do
  case "$1" in
    -auto_domain) AUTODOMAIN="$2"; shift 2;;
    -install) INSTALL="$2"; shift 2;;
    -panel) PNLNUM="$2"; shift 2;;
    -subdomain) domain="$2"; shift 2;;
    -reality_domain) reality_domain="$2"; shift 2;;
    -ONLY_CF_IP_ALLOW) CFALLOW="$2"; shift 2;;
    -websub) CUSTOMWEBSUB="$2"; shift 2;;
    -clash) CLASH="$2"; shift 2;;
    -uninstall) UNINSTALL="$2"; shift 2;;
    -hysteria) INSTALL_HYSTERIA="$2"; shift 2;;
    -mtproto) INSTALL_MTPROTO="$2"; shift 2;;
    -mtproto_domain) mtproto_domain="$2"; shift 2;;
    *) shift 1;;
  esac
done

##############################Ask about Hysteria2#######################################################
if [[ "${INSTALL_HYSTERIA}" != "y" && "${INSTALL_HYSTERIA}" != "n" ]]; then
    echo ""
    msg_inf "Установить Hysteria2 для Telegram звонков?"
    msg_inf "Hysteria2 работает на UDP:443 параллельно с VLESS Reality на TCP:443"
    echo ""
    echo -en "Установить Hysteria2? (y/n, default: n): " && read INSTALL_HYSTERIA
    INSTALL_HYSTERIA=${INSTALL_HYSTERIA:-n}
fi

##############################Ask about MTProto#########################################################
if [[ "${INSTALL_MTPROTO}" != "y" && "${INSTALL_MTPROTO}" != "n" ]]; then
    echo ""
    msg_inf "Установить MTProto прокси для Telegram?"
    msg_inf "MTProto работает на TCP:443 через SNI-маршрутизацию nginx (nineseconds/mtg:2)"
    msg_inf "Требуется дополнительный поддомен (например cdn.example.com)"
    echo ""
    echo -en "Установить MTProto прокси? (y/n, default: n): " && read INSTALL_MTPROTO
    INSTALL_MTPROTO=${INSTALL_MTPROTO:-n}
fi

if [[ ${INSTALL_MTPROTO} == *"y"* ]]; then
    while true; do
        if [[ -n "$mtproto_domain" ]]; then break; fi
        echo -en "Enter subdomain for MTProto (e.g. cdn.s3cloud.cc): " && read mtproto_domain
    done
    mtproto_domain=$(echo "$mtproto_domain" 2>&1 | tr -d '[:space:]')
fi

##############################Uninstall#################################################################
UNINSTALL_XUI(){
    printf 'y\n' | x-ui uninstall 2>/dev/null
    rm -rf "/etc/x-ui/" "/usr/local/x-ui/" "/usr/bin/x-ui/"
    $Pak -y remove nginx nginx-common nginx-core nginx-full python3-certbot-nginx
    $Pak -y purge nginx nginx-common nginx-core nginx-full python3-certbot-nginx
    $Pak -y autoremove
    $Pak -y autoclean
    rm -rf "/var/www/html/" "/etc/nginx/" "/usr/share/nginx/"
    snap remove nextcloud 2>/dev/null
    # Uninstall Hysteria2
    systemctl stop hysteria-server 2>/dev/null
    systemctl disable hysteria-server 2>/dev/null
    rm -f /usr/local/bin/hysteria
    rm -rf /etc/hysteria
    rm -f /etc/systemd/system/hysteria-server.service
    systemctl daemon-reload
    # Uninstall MTProto
    docker stop mtproto-proxy 2>/dev/null
    docker rm mtproto-proxy 2>/dev/null
    docker rmi nineseconds/mtg:2 2>/dev/null
    rm -rf /etc/mtg
}
if [[ ${UNINSTALL} == *"y"* ]]; then
    UNINSTALL_XUI
    clear && msg_ok "Completely Uninstalled!" && exit 1
fi

# --- get public IPv4 early
IP4_REGEX="^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$"
IP4=$(ip route get 8.8.8.8 2>&1 | grep -Po -- 'src \K\S*')
[[ $IP4 =~ $IP4_REGEX ]] || IP4=$(curl -s ipv4.icanhazip.com | tr -d '[:space:]')

if [[ ${AUTODOMAIN} == *"y"* ]]; then
    domain="${IP4}.cdn-one.org"
    reality_domain="${IP4//./-}.cdn-one.org"
fi

##############################Domain Validations########################################################
while true; do
    if [[ -n "$domain" ]]; then break; fi
    echo -en "Enter subdomain for PANEL (e.g. storage.s3cloud.cc): " && read domain
done

domain=$(echo "$domain" 2>&1 | tr -d '[:space:]' )
SubDomain=$(echo "$domain" 2>&1 | sed 's/^[^ ]* \|\..*//g')
MainDomain=$(echo "$domain" 2>&1 | sed 's/.*\.\([^.]*\..*\)$/\1/')
if [[ "${SubDomain}.${MainDomain}" != "${domain}" ]] ; then
    MainDomain=${domain}
fi

while true; do
    if [[ -n "$reality_domain" ]]; then break; fi
    echo -en "Enter subdomain for REALITY / Nextcloud (e.g. s3cloud.cc): " && read reality_domain
done

reality_domain=$(echo "$reality_domain" 2>&1 | tr -d '[:space:]' )

###############################Install Packages#########################################################
ufw disable 2>/dev/null
if [[ ${INSTALL} == *"y"* ]]; then
    $Pak -y update
    $Pak -y install curl wget jq bash sudo nginx-full certbot python3-certbot-nginx sqlite3 ufw snapd
    # Install Docker if MTProto requested
    if [[ ${INSTALL_MTPROTO} == *"y"* ]]; then
        $Pak -y install docker.io
    fi
    systemctl daemon-reload && systemctl enable --now nginx
fi
systemctl stop nginx
fuser -k 80/tcp 80/udp 443/tcp 443/udp 2>/dev/null

##################################GET SERVER IPv4-6#####################################################
IP4_REGEX="^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$"
IP6_REGEX="([a-f0-9:]+:+)+[a-f0-9]+"
IP4=$(ip route get 8.8.8.8 2>&1 | grep -Po -- 'src \K\S*')
IP6=$(ip route get 2620:fe::fe 2>&1 | grep -Po -- 'src \K\S*')
[[ $IP4 =~ $IP4_REGEX ]] || IP4=$(curl -s ipv4.icanhazip.com);
[[ $IP6 =~ $IP6_REGEX ]] || IP6=$(curl -s ipv6.icanhazip.com);

##############################Install SSL###############################################################
resolve_to_ip () {
    local host="$1"
    local a
    a=$(getent ahostsv4 "$host" 2>/dev/null | awk 'NR==1{print $1}')
    [[ -n "$a" ]] && [[ "$a" == "$IP4" ]]
}

certbot certonly --standalone --non-interactive --agree-tos --register-unsafely-without-email -d "$domain"
if [[ ! -d "/etc/letsencrypt/live/${domain}/" ]]; then
    systemctl start nginx >/dev/null 2>&1
    msg_err "$domain SSL could not be generated!" && exit 1
fi

certbot certonly --standalone --non-interactive --agree-tos --register-unsafely-without-email -d "$reality_domain"
if [[ ! -d "/etc/letsencrypt/live/${reality_domain}/" ]]; then
    systemctl start nginx >/dev/null 2>&1
    msg_err "$reality_domain SSL could not be generated!" && exit 1
fi

##############################Fix SSL permissions for Hysteria2#########################################
chmod 755 /etc/letsencrypt/
chmod 755 /etc/letsencrypt/live/
chmod 755 /etc/letsencrypt/archive/
chmod -R 755 /etc/letsencrypt/live/${reality_domain}/ 2>/dev/null
chmod -R 755 /etc/letsencrypt/archive/${reality_domain}/ 2>/dev/null
chmod 644 /etc/letsencrypt/archive/${reality_domain}/*.pem 2>/dev/null
chmod -R 755 /etc/letsencrypt/live/${domain}/ 2>/dev/null
chmod -R 755 /etc/letsencrypt/archive/${domain}/ 2>/dev/null
chmod 644 /etc/letsencrypt/archive/${domain}/*.pem 2>/dev/null

###################################Get Installed XUI Port/Path##########################################
if [[ -f $XUIDB ]]; then
    XUIPORT=$(sqlite3 -list $XUIDB 'SELECT "value" FROM settings WHERE "key"="webPort" LIMIT 1;' 2>&1)
    XUIPATH=$(sqlite3 -list $XUIDB 'SELECT "value" FROM settings WHERE "key"="webBasePath" LIMIT 1;' 2>&1)
    if [[ $XUIPORT -gt 0 && $XUIPORT != "54321" && $XUIPORT != "2053" ]] && [[ ${#XUIPORT} -gt 4 ]]; then
        RNDSTR=$(echo "$XUIPATH" 2>&1 | tr -d '/')
        PORT=$XUIPORT
        sqlite3 $XUIDB <<EOF
        DELETE FROM "settings" WHERE ( "key"="webCertFile" ) OR ( "key"="webKeyFile" );
        INSERT INTO "settings" ("key", "value") VALUES ("webCertFile",  "");
        INSERT INTO "settings" ("key", "value") VALUES ("webKeyFile", "");
EOF
    fi
fi

#################################Nginx Config###########################################################
mkdir -p /etc/nginx/stream-enabled
mkdir -p /etc/nginx/snippets

# Build stream.conf dynamically based on installed components
MTPROTO_MAP=""
MTPROTO_UPSTREAM=""
if [[ ${INSTALL_MTPROTO} == *"y"* ]]; then
    MTPROTO_MAP="    ${mtproto_domain}      mtproto;"
    MTPROTO_UPSTREAM="
upstream mtproto {
    server 127.0.0.1:8444;
}"
fi

cat > "/etc/nginx/stream-enabled/stream.conf" << EOF
map \$ssl_preread_server_name \$sni_name {
    hostnames;
    ${reality_domain}      xray;
    ${domain}              www;
${MTPROTO_MAP}
    default                xray;
}

upstream xray {
    server 127.0.0.1:8443;
}

upstream www {
    server 127.0.0.1:7443;
}
${MTPROTO_UPSTREAM}

server {
    proxy_protocol on;
    set_real_ip_from unix:;
    listen          443;
    proxy_pass      \$sni_name;
    ssl_preread     on;
}
EOF

grep -xqFR "stream { include /etc/nginx/stream-enabled/*.conf; }" /etc/nginx/* || echo "stream { include /etc/nginx/stream-enabled/*.conf; }" >> /etc/nginx/nginx.conf
grep -xqFR "load_module modules/ngx_stream_module.so;" /etc/nginx/* || sed -i '1s/^/load_module \/usr\/lib\/nginx\/modules\/ngx_stream_module.so; /' /etc/nginx/nginx.conf
grep -xqFR "load_module modules/ngx_stream_geoip2_module.so;" /etc/nginx* || sed -i '2s/^/load_module \/usr\/lib\/nginx\/modules\/ngx_stream_geoip2_module.so; /' /etc/nginx/nginx.conf
grep -xqFR "worker_rlimit_nofile 16384;" /etc/nginx/* || echo "worker_rlimit_nofile 16384;" >> /etc/nginx/nginx.conf
sed -i "/worker_connections/c\worker_connections 4096;" /etc/nginx/nginx.conf

cat > "/etc/nginx/sites-available/80.conf" << EOF
server {
    listen 80;
    server_name ${domain} ${reality_domain};
    return 301 https://\$host\$request_uri;
}
EOF

cat > "/etc/nginx/sites-available/${domain}" << EOF
server {
    server_tokens off;
    server_name ${domain};
    listen 7443 ssl http2 proxy_protocol;
    listen [::]:7443 ssl http2 proxy_protocol;
    index index.html index.htm index.php index.nginx-debian.html;
    root /var/www/html/;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!eNULL:!MD5:!DES:!RC4:!ADH:!SSLv3:!EXP:!PSK:!DSS;
    ssl_certificate /etc/letsencrypt/live/$domain/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$domain/privkey.pem;
    if (\$host !~* ^(.+\.)?$(echo $domain | sed 's/\./\\./g')\$ ){return 444;}
    if (\$scheme ~* https) {set \$safe 1;}
    if (\$ssl_server_name !~* ^(.+\.)?$(echo $domain | sed 's/\./\\./g')\$ ) {set \$safe "\${safe}0"; }
    if (\$safe = 10){return 444;}
    if (\$request_uri ~ "(\"|'|\`|~|,|:|--|;|%|\\\$|&&|\?\?|0x00|0X00|\||\\\\|\{|\}|\[|\]|<|>|\.\.\.|\.\.\/|\/\/\/)"){set \$hack 1;}
    error_page 400 401 402 403 500 501 502 503 504 =404 /404;
    proxy_intercept_errors on;

    location /${panel_path}/ {
        proxy_redirect off;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_pass http://127.0.0.1:${panel_port};
        break;
    }
    location /${panel_path} {
        proxy_redirect off;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_pass http://127.0.0.1:${panel_port};
        break;
    }

    include /etc/nginx/snippets/includes.conf;
}
EOF

cat > "/etc/nginx/sites-available/${reality_domain}" << EOF
server {
    server_tokens off;
    server_name ${reality_domain};
    listen 9443 ssl http2;
    listen [::]:9443 ssl http2;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!eNULL:!MD5:!DES:!RC4:!ADH:!SSLv3:!EXP:!PSK:!DSS;
    ssl_certificate /etc/letsencrypt/live/$reality_domain/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$reality_domain/privkey.pem;
    if (\$host !~* ^(.+\.)?$(echo $reality_domain | sed 's/\./\\./g')\$ ){return 444;}
    if (\$scheme ~* https) {set \$safe 1;}
    if (\$ssl_server_name !~* ^(.+\.)?$(echo $reality_domain | sed 's/\./\\./g')\$ ) {set \$safe "\${safe}0"; }
    if (\$safe = 10){return 444;}
    error_page 400 401 402 403 500 501 502 503 504 =404 /404;
    proxy_intercept_errors on;

    location / {
        proxy_pass http://127.0.0.1:${NC_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Port 443;
        proxy_buffering off;
        proxy_request_buffering off;
        client_max_body_size 10G;
        proxy_read_timeout 3600;
        proxy_connect_timeout 3600;
        proxy_send_timeout 3600;
    }

    location /${panel_path}/ {
        proxy_redirect off;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_pass http://127.0.0.1:${panel_port};
        break;
    }
    location /${panel_path} {
        proxy_redirect off;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_pass http://127.0.0.1:${panel_port};
        break;
    }
}
EOF

cat > "/etc/nginx/snippets/includes.conf" << EOF
    #sub2sing-box
    location /${sub2singbox_path}/ {
        proxy_redirect off;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_pass http://127.0.0.1:8080/;
    }
    location ~ ^/${web_path}/clashmeta/(.+)\$ {
        default_type text/plain;
        ssi on;
        ssi_types text/plain;
        set \$subid \$1;
        root /var/www/subpage;
        try_files /clash.yaml =404;
    }
    location ~ ^/${web_path} {
        root /var/www/subpage;
        index index.html;
        try_files \$uri \$uri/ /index.html =404;
    }
    location /${sub_path} {
        if (\$hack = 1) {return 404;}
        proxy_redirect off;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_pass http://127.0.0.1:${sub_port};
        break;
    }
    location /${sub_path}/ {
        if (\$hack = 1) {return 404;}
        proxy_redirect off;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_pass http://127.0.0.1:${sub_port};
        break;
    }
    location /assets/ {
        if (\$hack = 1) {return 404;}
        proxy_redirect off;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_pass http://127.0.0.1:${sub_port};
        break;
    }
    location /assets {
        if (\$hack = 1) {return 404;}
        proxy_redirect off;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_pass http://127.0.0.1:${sub_port};
        break;
    }
    location /${json_path} {
        if (\$hack = 1) {return 404;}
        proxy_redirect off;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_pass http://127.0.0.1:${sub_port};
        break;
    }
    location /${json_path}/ {
        if (\$hack = 1) {return 404;}
        proxy_redirect off;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_pass http://127.0.0.1:${sub_port};
        break;
    }
    #XHTTP
    location /${xhttp_path} {
        proxy_pass http://unix:/dev/shm/uds2023.sock;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 1h;
        proxy_send_timeout 1h;
        proxy_buffering off;
        proxy_request_buffering off;
        client_max_body_size 0;
    }
    #Xray Config Path
    location ~ ^/(?<fwdport>\d+)/(?<fwdpath>.*)\$ {
        if (\$hack = 1) {return 404;}
        client_max_body_size 0;
        client_body_timeout 1d;
        grpc_read_timeout 1d;
        grpc_socket_keepalive on;
        proxy_read_timeout 1d;
        proxy_http_version 1.1;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_socket_keepalive on;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        if (\$content_type ~* "GRPC") {
            grpc_pass grpc://127.0.0.1:\$fwdport\$is_args\$args;
            break;
        }
        if (\$http_upgrade ~* "(WEBSOCKET|WS)") {
            proxy_pass http://127.0.0.1:\$fwdport\$is_args\$args;
            break;
        }
        if (\$request_method ~* ^(PUT|POST|GET)\$) {
            proxy_pass http://127.0.0.1:\$fwdport\$is_args\$args;
            break;
        }
    }
    location / { try_files \$uri \$uri/ =404; }
EOF

##################################Check Nginx status####################################################
if [[ -f "/etc/nginx/sites-available/${domain}" ]]; then
    unlink "/etc/nginx/sites-enabled/default" >/dev/null 2>&1
    rm -f "/etc/nginx/sites-enabled/default" "/etc/nginx/sites-available/default"
    ln -s "/etc/nginx/sites-available/${domain}" "/etc/nginx/sites-enabled/" 2>/dev/null
    ln -s "/etc/nginx/sites-available/${reality_domain}" "/etc/nginx/sites-enabled/" 2>/dev/null
    ln -s "/etc/nginx/sites-available/80.conf" "/etc/nginx/sites-enabled/" 2>/dev/null
else
    msg_err "${domain} nginx config not exist!" && exit 1
fi

if [[ $(nginx -t 2>&1 | grep -o 'successful') != "successful" ]]; then
    msg_err "nginx config is not ok!" && exit 1
else
    systemctl start nginx
fi

##############################generate uri's###########################################################
sub_uri=https://${domain}/${sub_path}/
json_uri=https://${domain}/${web_path}?name=

##############################generate keys############################################################
shor=($(openssl rand -hex 8) $(openssl rand -hex 8) $(openssl rand -hex 8) $(openssl rand -hex 8) $(openssl rand -hex 8) $(openssl rand -hex 8) $(openssl rand -hex 8) $(openssl rand -hex 8))

########################################Update X-UI Port/Path##########################################
UPDATE_XUIDB(){
if [[ -f $XUIDB ]]; then
    x-ui stop
    output=$(/usr/local/x-ui/bin/xray-linux-amd64 x25519)
    private_key=$(echo "$output" | grep "^PrivateKey:" | awk '{print $2}')
    public_key=$(echo "$output" | grep "^Password:" | awk '{print $2}')
    client_id=$(/usr/local/x-ui/bin/xray-linux-amd64 uuid)
    client_id2=$(/usr/local/x-ui/bin/xray-linux-amd64 uuid)
    client_id3=$(/usr/local/x-ui/bin/xray-linux-amd64 uuid)
    trojan_pass=$(gen_random_string 10)
    emoji_flag=$(LC_ALL=en_US.UTF-8 curl -s https://ipwho.is/ | jq -r '.flag.emoji')
    sqlite3 $XUIDB <<EOF
         INSERT INTO "settings" ("key", "value") VALUES ("subPort",  '${sub_port}');
         INSERT INTO "settings" ("key", "value") VALUES ("subPath",  '/${sub_path}/');
         INSERT INTO "settings" ("key", "value") VALUES ("subURI",  '${sub_uri}');
         INSERT INTO "settings" ("key", "value") VALUES ("subJsonPath",  '${json_path}');
         INSERT INTO "settings" ("key", "value") VALUES ("subJsonURI",  '${json_uri}');
         INSERT INTO "settings" ("key", "value") VALUES ("subEnable",  'true');
         INSERT INTO "settings" ("key", "value") VALUES ("webListen",  '');
         INSERT INTO "settings" ("key", "value") VALUES ("webDomain",  '');
         INSERT INTO "settings" ("key", "value") VALUES ("webCertFile",  '');
         INSERT INTO "settings" ("key", "value") VALUES ("webKeyFile",  '');
         INSERT INTO "settings" ("key", "value") VALUES ("sessionMaxAge",  '60');
         INSERT INTO "settings" ("key", "value") VALUES ("pageSize",  '50');
         INSERT INTO "settings" ("key", "value") VALUES ("expireDiff",  '0');
         INSERT INTO "settings" ("key", "value") VALUES ("trafficDiff",  '0');
         INSERT INTO "settings" ("key", "value") VALUES ("remarkModel",  '-ieo');
         INSERT INTO "settings" ("key", "value") VALUES ("tgBotEnable",  'false');
         INSERT INTO "settings" ("key", "value") VALUES ("tgBotToken",  '');
         INSERT INTO "settings" ("key", "value") VALUES ("tgBotProxy",  '');
         INSERT INTO "settings" ("key", "value") VALUES ("tgBotAPIServer",  '');
         INSERT INTO "settings" ("key", "value") VALUES ("tgBotChatId",  '');
         INSERT INTO "settings" ("key", "value") VALUES ("tgRunTime",  '@daily');
         INSERT INTO "settings" ("key", "value") VALUES ("tgBotBackup",  'false');
         INSERT INTO "settings" ("key", "value") VALUES ("tgBotLoginNotify",  'true');
         INSERT INTO "settings" ("key", "value") VALUES ("tgCpu",  '80');
         INSERT INTO "settings" ("key", "value") VALUES ("tgLang",  'en-US');
         INSERT INTO "settings" ("key", "value") VALUES ("timeLocation",  'Europe/Moscow');
         INSERT INTO "settings" ("key", "value") VALUES ("secretEnable",  'false');
         INSERT INTO "settings" ("key", "value") VALUES ("subDomain",  '');
         INSERT INTO "settings" ("key", "value") VALUES ("subCertFile",  '');
         INSERT INTO "settings" ("key", "value") VALUES ("subKeyFile",  '');
         INSERT INTO "settings" ("key", "value") VALUES ("subUpdates",  '12');
         INSERT INTO "settings" ("key", "value") VALUES ("subEncrypt",  'true');
         INSERT INTO "settings" ("key", "value") VALUES ("subShowInfo",  'true');
         INSERT INTO "settings" ("key", "value") VALUES ("subJsonFragment",  '');
         INSERT INTO "settings" ("key", "value") VALUES ("subJsonNoises",  '');
         INSERT INTO "settings" ("key", "value") VALUES ("subJsonMux",  '');
         INSERT INTO "settings" ("key", "value") VALUES ("subJsonRules",  '');
         INSERT INTO "settings" ("key", "value") VALUES ("datepicker",  'gregorian');
         INSERT INTO "client_traffics" ("inbound_id","enable","email","up","down","expiry_time","total","reset") VALUES ('1','1','first','0','0','0','0','0');
         INSERT INTO "client_traffics" ("inbound_id","enable","email","up","down","expiry_time","total","reset") VALUES ('2','1','first_1','0','0','0','0','0');
         INSERT INTO "client_traffics" ("inbound_id","enable","email","up","down","expiry_time","total","reset") VALUES ('3','1','firstX','0','0','0','0','0');
         INSERT INTO "client_traffics" ("inbound_id","enable","email","up","down","expiry_time","total","reset") VALUES ('4','1','firstT','0','0','0','0','0');
         INSERT INTO "inbounds" ("user_id","up","down","total","remark","enable","expiry_time","listen","port","protocol","settings","stream_settings","tag","sniffing") VALUES (
         '1','0','0','0',
         '${emoji_flag} reality','1','0','',
         '8443','vless',
         '{
  "clients": [
    {
      "id": "${client_id}",
      "flow": "xtls-rprx-vision",
      "email": "first",
      "limitIp": 0,
      "totalGB": 0,
      "expiryTime": 0,
      "enable": true,
      "tgId": "",
      "subId": "first",
      "reset": 0
    }
  ],
  "decryption": "none",
  "fallbacks": []
}',
         '{
  "network": "tcp",
  "security": "reality",
  "externalProxy": [
    {
      "forceTls": "same",
      "dest": "${domain}",
      "port": 443,
      "remark": ""
    }
  ],
  "realitySettings": {
    "show": false,
    "xver": 0,
    "target": "127.0.0.1:9443",
    "serverNames": [
      "$reality_domain"
    ],
    "privateKey": "${private_key}",
    "minClient": "",
    "maxClient": "",
    "maxTimediff": 0,
    "shortIds": [
      "${shor[0]}","${shor[1]}","${shor[2]}","${shor[3]}",
      "${shor[4]}","${shor[5]}","${shor[6]}","${shor[7]}"
    ],
    "settings": {
      "publicKey": "${public_key}",
      "fingerprint": "random",
      "serverName": "",
      "spiderX": "/"
    }
  },
  "tcpSettings": {
    "acceptProxyProtocol": true,
    "header": {
      "type": "none"
    }
  }
}',
         'inbound-8443',
         '{
  "enabled": false,
  "destOverride": ["http","tls","quic","fakedns"],
  "metadataOnly": false,
  "routeOnly": false
}'
         );
  INSERT INTO "inbounds" ("user_id","up","down","total","remark","enable","expiry_time","listen","port","protocol","settings","stream_settings","tag","sniffing") VALUES (
         '1','0','0','0',
         '${emoji_flag} ws','1','0','',
         '${ws_port}','vless',
         '{
  "clients": [
    {
      "id": "${client_id2}",
      "flow": "",
      "email": "first_1",
      "limitIp": 0,
      "totalGB": 0,
      "expiryTime": 0,
      "enable": true,
      "tgId": "",
      "subId": "first",
      "reset": 0
    }
  ],
  "decryption": "none",
  "fallbacks": []
}',
         '{
  "network": "ws",
  "security": "none",
  "externalProxy": [
    {
      "forceTls": "tls",
      "dest": "${domain}",
      "port": 443,
      "remark": ""
    }
  ],
  "wsSettings": {
    "acceptProxyProtocol": false,
    "path": "/${ws_port}/${ws_path}",
    "host": "${domain}",
    "headers": {}
  }
}',
         'inbound-${ws_port}',
         '{
  "enabled": false,
  "destOverride": ["http","tls","quic","fakedns"],
  "metadataOnly": false,
  "routeOnly": false
}'
         );
  INSERT INTO "inbounds" ("user_id","up","down","total","remark","enable","expiry_time","listen","port","protocol","settings","stream_settings","tag","sniffing") VALUES (
         '1','0','0','0',
         '${emoji_flag} xhttp','1','0',
         '/dev/shm/uds2023.sock,0666',
         '0','vless',
         '{
  "clients": [
    {
      "id": "${client_id3}",
      "flow": "",
      "email": "firstX",
      "limitIp": 0,
      "totalGB": 0,
      "expiryTime": 0,
      "enable": true,
      "tgId": "",
      "subId": "first",
      "reset": 0
    }
  ],
  "decryption": "none",
  "fallbacks": []
}',
         '{
  "network": "xhttp",
  "security": "none",
  "externalProxy": [
    {
      "forceTls": "tls",
      "dest": "${domain}",
      "port": 443,
      "remark": ""
    }
  ],
  "xhttpSettings": {
    "path": "/${xhttp_path}",
    "host": "",
    "headers": {},
    "scMaxBufferedPosts": 30,
    "scMaxEachPostBytes": "1000000",
    "noSSEHeader": false,
    "xPaddingBytes": "100-1000",
    "mode": "packet-up"
  },
  "sockopt": {
    "acceptProxyProtocol": false,
    "tcpFastOpen": true,
    "mark": 0,
    "tproxy": "off",
    "tcpMptcp": true,
    "tcpNoDelay": true,
    "domainStrategy": "UseIP",
    "tcpMaxSeg": 1440,
    "dialerProxy": "",
    "tcpKeepAliveInterval": 0,
    "tcpKeepAliveIdle": 300,
    "tcpUserTimeout": 10000,
    "tcpcongestion": "bbr",
    "V6Only": false,
    "tcpWindowClamp": 600,
    "interface": ""
  }
}',
         'inbound-/dev/shm/uds2023.sock,0666:0|',
         '{
  "enabled": true,
  "destOverride": ["http","tls","quic","fakedns"],
  "metadataOnly": false,
  "routeOnly": false
}'
         );
  INSERT INTO "inbounds" ("user_id","up","down","total","remark","enable","expiry_time","listen","port","protocol","settings","stream_settings","tag","sniffing") VALUES (
         '1','0','0','0',
         '${emoji_flag} trojan-grpc','1','0','',
         '${trojan_port}','trojan',
         '{
  "clients": [
    {
      "comment": "",
      "email": "firstT",
      "enable": true,
      "expiryTime": 0,
      "limitIp": 0,
      "password": "${trojan_pass}",
      "reset": 0,
      "subId": "first",
      "tgId": 0,
      "totalGB": 0
    }
  ],
  "fallbacks": []
}',
         '{
  "network": "grpc",
  "security": "none",
  "externalProxy": [
    {
      "forceTls": "tls",
      "dest": "${domain}",
      "port": 443,
      "remark": ""
    }
  ],
  "grpcSettings": {
    "serviceName": "/${trojan_port}/${trojan_path}",
    "authority": "${domain}",
    "multiMode": false
  }
}',
         'inbound-${trojan_port}',
         '{
  "enabled": false,
  "destOverride": ["http","tls","quic","fakedns"],
  "metadataOnly": false,
  "routeOnly": false
}'
         );
EOF
/usr/local/x-ui/x-ui setting -username "${config_username}" -password "${config_password}" -port "${panel_port}" -webBasePath "${panel_path}"
x-ui start
else
    msg_err "x-ui.db file not exist! Maybe x-ui isn't installed." && exit 1;
fi
}

arch() {
    case "$(uname -m)" in
        x86_64 | x64 | amd64) echo 'amd64' ;;
        i*86 | x86) echo '386' ;;
        armv8* | armv8 | arm64 | aarch64) echo 'arm64' ;;
        armv7* | armv7 | arm) echo 'armv7' ;;
        armv6* | armv6) echo 'armv6' ;;
        armv5* | armv5) echo 'armv5' ;;
        s390x) echo 's390x' ;;
        *) echo -e "Unsupported CPU architecture!" && exit 1 ;;
    esac
}

config_after_install() {
    /usr/local/x-ui/x-ui setting -username "asdfasdf" -password "asdfasdf" -port "2096" -webBasePath "asdfasdf"
    /usr/local/x-ui/x-ui migrate
}

install_panel() {
    apt-get update && apt-get install -y -q wget curl tar tzdata
    cd /usr/local/
    tag_version=$(curl -Ls "https://api.github.com/repos/MHSanaei/3x-ui/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    if [[ ! -n "$tag_version" ]]; then
        tag_version=$(curl -4 -Ls "https://api.github.com/repos/MHSanaei/3x-ui/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        if [[ ! -n "$tag_version" ]]; then
            echo -e "Failed to fetch x-ui version!" && exit 1
        fi
    fi
    echo -e "Got x-ui latest version: ${tag_version}"
    wget -N -O /usr/local/x-ui-linux-$(arch).tar.gz https://github.com/MHSanaei/3x-ui/releases/download/${tag_version}/x-ui-linux-$(arch).tar.gz
    [[ $? -ne 0 ]] && echo "Downloading x-ui failed!" && exit 1
    wget -O /usr/bin/x-ui-temp https://raw.githubusercontent.com/MHSanaei/3x-ui/main/x-ui.sh
    [[ $? -ne 0 ]] && echo "Failed to download x-ui.sh" && exit 1
    if [[ -e /usr/local/x-ui/ ]]; then
        systemctl stop x-ui
        rm /usr/local/x-ui/ -rf
    fi
    tar zxvf x-ui-linux-$(arch).tar.gz
    rm x-ui-linux-$(arch).tar.gz -f
    cd x-ui
    chmod +x x-ui x-ui.sh
    chmod +x bin/xray-linux-$(arch)
    mv -f /usr/bin/x-ui-temp /usr/bin/x-ui
    chmod +x /usr/bin/x-ui
    config_after_install
    if [[ -f x-ui.service.debian ]]; then
        cp -f x-ui.service.debian /etc/systemd/system/x-ui.service
    elif [[ -f x-ui.service ]]; then
        cp -f x-ui.service /etc/systemd/system/x-ui.service
    else
        cat > /etc/systemd/system/x-ui.service << 'SVCEOF'
[Unit]
Description=x-ui Service
After=network.target
Wants=network.target
[Service]
Environment="XRAY_VMESS_AEAD_FORCED=false"
Type=simple
WorkingDirectory=/usr/local/x-ui/
ExecStart=/usr/local/x-ui/x-ui
Restart=on-failure
RestartSec=5s
LimitNOFILE=1048576
LimitNPROC=512
[Install]
WantedBy=multi-user.target
SVCEOF
    fi
    systemctl daemon-reload
    systemctl enable x-ui
    systemctl start x-ui
}

###################################Install X-UI#########################################################
if systemctl is-active --quiet x-ui; then
    x-ui restart
else
    install_panel
    UPDATE_XUIDB
    if ! systemctl is-enabled --quiet x-ui; then
        systemctl daemon-reload && systemctl enable x-ui.service
    fi
    x-ui restart
fi

######################enable bbr########################################################################
apt-get install -yqq --no-install-recommends ca-certificates
echo "net.core.default_qdisc=fq" | tee -a /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" | tee -a /etc/sysctl.conf
echo "fs.file-max=2097152" | tee -a /etc/sysctl.conf
echo "net.core.rmem_max = 16777216" | tee -a /etc/sysctl.conf
echo "net.core.wmem_max = 16777216" | tee -a /etc/sysctl.conf
echo "net.ipv4.tcp_rmem = 4096 87380 16777216" | tee -a /etc/sysctl.conf
echo "net.ipv4.tcp_wmem = 4096 65536 16777216" | tee -a /etc/sysctl.conf
sysctl -p

######################install Nextcloud Snap############################################################
msg_inf "Installing Nextcloud via Snap..."
if ! snap list nextcloud &>/dev/null; then
    snap install nextcloud
fi

msg_inf "Setting Nextcloud ports..."
snap set nextcloud ports.http=${NC_PORT}
snap set nextcloud ports.https=8182

NC_PASS=$(gen_random_string 12)
msg_inf "Installing Nextcloud with admin user..."
nextcloud.manual-install admin "${NC_PASS}"

msg_inf "Waiting for Nextcloud to initialize..."
for i in $(seq 1 30); do
    if nextcloud.occ status 2>/dev/null | grep -q "installed: true"; then
        msg_ok "Nextcloud is ready!"
        break
    fi
    sleep 5
done

msg_inf "Configuring Nextcloud..."
nextcloud.occ config:system:set overwriteprotocol --value="https"
nextcloud.occ config:system:set overwritehost --value="${reality_domain}"
nextcloud.occ config:system:set overwrite.cli.url --value="https://${reality_domain}"
nextcloud.occ config:system:set trusted_domains 0 --value="${reality_domain}"
nextcloud.occ config:system:set trusted_domains 1 --value="127.0.0.1"
nextcloud.occ config:system:set trusted_proxies 0 --value="127.0.0.1"
snap restart nextcloud
msg_ok "Nextcloud Snap installed and configured!"

######################install Hysteria2 (optional)######################################################
if [[ ${INSTALL_HYSTERIA} == *"y"* ]]; then
    msg_inf "Installing Hysteria2..."

    bash <(curl -fsSL https://get.hy2.sh/)

    mkdir -p /etc/hysteria
    cat > /etc/hysteria/config.yaml << EOF
listen: :443

tls:
  cert: /etc/letsencrypt/live/${reality_domain}/fullchain.pem
  key: /etc/letsencrypt/live/${reality_domain}/privkey.pem

auth:
  type: password
  password: ${hy2_password}

bandwidth:
  up: 100 mbps
  down: 100 mbps
EOF

    systemctl enable hysteria-server
    systemctl start hysteria-server

    sleep 2
    if systemctl is-active --quiet hysteria-server; then
        msg_ok "Hysteria2 installed and running on UDP:443!"
    else
        msg_err "Hysteria2 failed to start! Check: journalctl -u hysteria-server -f"
    fi

    (crontab -l 2>/dev/null; echo '@monthly systemctl restart hysteria-server > /dev/null 2>&1;') | crontab -
fi

######################install MTProto proxy (optional)##################################################
if [[ ${INSTALL_MTPROTO} == *"y"* ]]; then
    msg_inf "Installing MTProto proxy (nineseconds/mtg:2)..."

    # Install Docker if not present
    if ! command -v docker &>/dev/null; then
        msg_inf "Installing Docker..."
        $Pak -y install docker.io
        systemctl enable --now docker
    fi

    # Generate secret
    MTPROTO_SECRET=$(docker run --rm nineseconds/mtg:2 generate-secret --hex "$mtproto_domain")
    msg_inf "MTProto secret: ${MTPROTO_SECRET}"

    # Create config with proxy-protocol support
    mkdir -p /etc/mtg
    cat > /etc/mtg/config.toml << EOF
secret = "${MTPROTO_SECRET}"
bind-to = "0.0.0.0:3128"
proxy-protocol-listener = true
EOF

    # Stop old container if exists
    docker stop mtproto-proxy 2>/dev/null
    docker rm mtproto-proxy 2>/dev/null

    # Run container
    docker run -d \
      --name mtproto-proxy \
      --restart unless-stopped \
      -p 127.0.0.1:8444:3128 \
      -v /etc/mtg/config.toml:/config.toml \
      nineseconds/mtg:2 run /config.toml

    sleep 3
    if docker ps | grep -q mtproto-proxy; then
        msg_ok "MTProto proxy installed and running on TCP:443 (via nginx SNI)!"
    else
        msg_err "MTProto proxy failed to start! Check: docker logs mtproto-proxy"
    fi
fi

######################install_sub2sing-box##############################################################
if pgrep -x "sub2sing-box" > /dev/null; then
    pkill -x "sub2sing-box"
fi
rm -f /usr/bin/sub2sing-box
wget -P /root/ https://github.com/legiz-ru/sub2sing-box/releases/download/v0.0.9/sub2sing-box_0.0.9_linux_amd64.tar.gz
tar -xvzf /root/sub2sing-box_0.0.9_linux_amd64.tar.gz -C /root/ --strip-components=1 sub2sing-box_0.0.9_linux_amd64/sub2sing-box
mv /root/sub2sing-box /usr/bin/
chmod +x /usr/bin/sub2sing-box
rm /root/sub2sing-box_0.0.9_linux_amd64.tar.gz
su -c "/usr/bin/sub2sing-box server --bind 127.0.0.1 --port 8080 & disown" root

######################install_web_sub_page##############################################################
URL_SUB_PAGE=( "https://github.com/legiz-ru/x-ui-pro/raw/master/sub-3x-ui.html"
               "https://github.com/legiz-ru/x-ui-pro/raw/master/sub-3x-ui-classical.html" )
URL_CLASH_SUB=( "https://github.com/legiz-ru/x-ui-pro/raw/master/clash/clash.yaml"
                "https://github.com/legiz-ru/x-ui-pro/raw/master/clash/clash_skrepysh.yaml"
                "https://github.com/legiz-ru/x-ui-pro/raw/master/clash/clash_fullproxy_without_ru.yaml"
                "https://github.com/legiz-ru/x-ui-pro/raw/master/clash/clash_refilter_ech.yaml" )
DEST_DIR_SUB_PAGE="/var/www/subpage"
DEST_FILE_SUB_PAGE="$DEST_DIR_SUB_PAGE/index.html"
DEST_FILE_CLASH_SUB="$DEST_DIR_SUB_PAGE/clash.yaml"
sudo mkdir -p "$DEST_DIR_SUB_PAGE"
sudo curl -L "${URL_CLASH_SUB[$CLASH]}" -o "$DEST_FILE_CLASH_SUB"
sudo curl -L "${URL_SUB_PAGE[$CUSTOMWEBSUB]}" -o "$DEST_FILE_SUB_PAGE"
sed -i "s/\${DOMAIN}/$domain/g" "$DEST_FILE_SUB_PAGE"
sed -i "s/\${DOMAIN}/$domain/g" "$DEST_FILE_CLASH_SUB"
sed -i "s#\${SUB_JSON_PATH}#$json_path#g" "$DEST_FILE_SUB_PAGE"
sed -i "s#\${SUB_PATH}#$sub_path#g" "$DEST_FILE_SUB_PAGE"
sed -i "s#\${SUB_PATH}#$sub_path#g" "$DEST_FILE_CLASH_SUB"
sed -i "s|sub.legiz.ru|$domain/$sub2singbox_path|g" "$DEST_FILE_SUB_PAGE"

######################cronjob###########################################################################
crontab -l | grep -v "certbot\|x-ui\|cloudflareips\|sub2sing-box\|hysteria" | crontab -
(crontab -l 2>/dev/null; echo '@reboot /usr/bin/sub2sing-box server --bind 127.0.0.1 --port 8080 > /dev/null 2>&1') | crontab -
(crontab -l 2>/dev/null; echo '@daily x-ui restart > /dev/null 2>&1 && nginx -s reload;') | crontab -
(crontab -l 2>/dev/null; echo '@monthly certbot renew --nginx --non-interactive --post-hook "nginx -s reload" > /dev/null 2>&1;') | crontab -

##################################ufw###################################################################
ufw disable
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
if [[ ${INSTALL_HYSTERIA} == *"y"* ]]; then
    ufw allow 443/udp
fi
ufw --force enable

##################################Show Details##########################################################
if systemctl is-active --quiet x-ui; then clear
    printf '0\n' | x-ui | grep --color=never -i ':'
    msg_inf "====================================================================="
    msg_inf "                      SAVE THIS SCREEN!"
    msg_inf "====================================================================="
    msg_inf ""
    msg_inf "X-UI Panel: https://${domain}/${panel_path}/"
    echo -e "Username:  ${config_username}"
    echo -e "Password:  ${config_password}"
    msg_inf "- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"
    msg_inf "Web Sub Page: https://${domain}/${web_path}?name=first"
    msg_inf "Sub2sing-box: https://${domain}/$sub2singbox_path/"
    msg_inf "- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"
    msg_inf "Nextcloud: https://${reality_domain}"
    msg_inf "Nextcloud admin: admin"
    msg_inf "Nextcloud password: ${NC_PASS}"
    msg_inf "- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"
    if [[ ${INSTALL_HYSTERIA} == *"y"* ]]; then
    msg_inf "====================================================================="
    msg_inf "                    HYSTERIA2 (Telegram calls)"
    msg_inf "====================================================================="
    msg_inf ""
    msg_inf "Server: ${reality_domain}"
    msg_inf "Port: 443 (UDP)"
    msg_inf "Password: ${hy2_password}"
    msg_inf ""
    msg_inf "For Mihomo .yaml:"
    msg_inf "  - name: NL-hysteria2"
    msg_inf "    type: hysteria2"
    msg_inf "    server: ${reality_domain}"
    msg_inf "    port: 443"
    msg_inf "    password: ${hy2_password}"
    msg_inf "    sni: ${reality_domain}"
    msg_inf "    alpn:"
    msg_inf "      - h3"
    msg_inf "    udp: true"
    msg_inf ""
    msg_inf "Clients URI:"
    msg_inf "hy2://${hy2_password}@${reality_domain}:443?sni=${reality_domain}&alpn=h3#Hysteria2"
    msg_inf ""
    msg_inf "- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"
    fi
    if [[ ${INSTALL_MTPROTO} == *"y"* ]]; then
    msg_inf "====================================================================="
    msg_inf "                    MTPROTO PROXY (Telegram)"
    msg_inf "====================================================================="
    msg_inf ""
    msg_inf "Docker image: nineseconds/mtg:2"
    msg_inf "Domain: ${mtproto_domain}"
    msg_inf "Port: 443 (TCP, via nginx SNI)"
    msg_inf "Secret: ${MTPROTO_SECRET}"
    msg_inf ""
    msg_inf "Telegram proxy URL:"
    msg_inf "tg://proxy?server=${IP4}&port=443&secret=${MTPROTO_SECRET}"
    msg_inf ""
    msg_inf "t.me link:"
    msg_inf "https://t.me/proxy?server=${IP4}&port=443&secret=${MTPROTO_SECRET}"
    msg_inf ""
    msg_inf "Config: /etc/mtg/config.toml"
    msg_inf "Logs: docker logs mtproto-proxy"
    msg_inf ""
    msg_inf "- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"
    fi
    msg_inf "SSL Certificates:"
    certbot certificates 2>/dev/null | grep -i 'Domains:\|Expiry Date:'
    msg_inf "- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"
    msg_inf ""
    msg_inf "====================================================================="
    msg_inf "  CHANGE SSH PORT (recommended):"
    msg_inf "====================================================================="
    msg_inf ""
    msg_inf "  1. Change SSH port (replace 2222 with your preferred port):"
    msg_inf "     sed -i 's/^#\\?Port 22/Port 2222/' /etc/ssh/sshd_config"
    msg_inf ""
    msg_inf "  2. Open new port in firewall BEFORE restarting SSH:"
    msg_inf "     ufw allow 2222/tcp"
    msg_inf ""
    msg_inf "  3. Restart SSH:"
    msg_inf "     systemctl restart sshd"
    msg_inf ""
    msg_inf "  4. Test new port (in NEW terminal, keep old one open!):"
    msg_inf "     ssh -p 2222 root@${IP4}"
    msg_inf ""
    msg_inf "  5. Only after successful login, close old port:"
    msg_inf "     ufw delete allow 22/tcp"
    msg_inf "     ufw reload"
    msg_inf ""
    msg_inf "====================================================================="
    msg_inf "  SAVE THIS SCREEN!!"
    msg_inf "====================================================================="
else
    nginx -t && printf '0\n' | x-ui | grep --color=never -i ':'
    msg_err "sqlite and x-ui to be checked, try on a new clean linux!"
fi
