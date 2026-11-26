#!/usr/bin/env bash
# Ejecutar UNA vez EN EL SERVIDOR como root:  bash setup-nginx.sh [dominio] 
# Variables opcionales: APP_DIR (def. /opt/inventario)  AUTH_USER / AUTH_PASS (protege el sitio con usuario y clave)
set -euo pipefail
DOMINIO="${1:-_}"
APP_DIR="${APP_DIR:-/opt/inventario}"
CONF="/etc/nginx/sites-available/inventario"

apt-get update -y && apt-get install -y nginx curl ca-certificates
# Node 22+ (necesario para SQLite integrado)
if ! command -v node >/dev/null || [ "$(node -p 'process.versions.node.split(".")[0]')" -lt 22 ]; then
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  apt-get install -y nodejs
fi

mkdir -p "$APP_DIR"/{site,server,database,backups}
id -u inventario >/dev/null 2>&1 || useradd --system --home "$APP_DIR" --shell /usr/sbin/nologin inventario
chown -R inventario:inventario "$APP_DIR/database" "$APP_DIR/backups"

# --- servicio de la API (guarda en $APP_DIR/database/inventario.db) ---
cat > /etc/systemd/system/inventario.service <<SVC
[Unit]
Description=Sistema de Inventario (API + SQLite)
After=network.target
[Service]
User=inventario
WorkingDirectory=$APP_DIR/server
Environment=PORT=3000
Environment=DB_DIR=$APP_DIR/database
ExecStart=/usr/bin/node --disable-warning=ExperimentalWarning $APP_DIR/server/server.js
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
SVC
systemctl daemon-reload
systemctl enable inventario >/dev/null

# --- clave opcional de acceso al sitio ---
AUTH=""
if [ -n "${AUTH_USER:-}" ] && [ -n "${AUTH_PASS:-}" ]; then
  printf '%s:%s\n' "$AUTH_USER" "$(openssl passwd -apr1 "$AUTH_PASS")" > /etc/nginx/.htpasswd-inventario
  AUTH='auth_basic "Inventario"; auth_basic_user_file /etc/nginx/.htpasswd-inventario;'
fi

cat > "$CONF" <<NGX
server {
    listen 80;
    listen [::]:80;
    server_name $DOMINIO;
    root $APP_DIR/site;
    index index.html;
    client_max_body_size 50m;
    $AUTH
    gzip on;
    gzip_types text/html text/css application/javascript application/json;
    add_header X-Content-Type-Options nosniff always;

    location /api/ {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$remote_addr;
    }
    location / { try_files \$uri \$uri/ /index.html; }
    location = /index.html { add_header Cache-Control "no-cache"; }
}
NGX
ln -sf "$CONF" /etc/nginx/sites-enabled/inventario
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl enable --now nginx
systemctl reload nginx

# --- respaldo diario de la base de datos (conserva 30 días) ---
cat > /etc/cron.d/inventario-backup <<CRON
30 3 * * * inventario bash $APP_DIR/server/backup.sh
CRON

if command -v ufw >/dev/null && ufw status | grep -q active; then ufw allow 'Nginx Full' || true; fi
echo "Nginx y servicio configurados. Ahora suba los archivos con ./deploy.sh"
echo "HTTPS con dominio:  apt install -y certbot python3-certbot-nginx && certbot --nginx -d <dominio>"
