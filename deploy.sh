#!/usr/bin/env bash
# Uso:  ./deploy.sh            -> sube sitio + servidor y reinicia (NO toca la base de datos)
#       ./deploy.sh --setup    -> primera vez: instala nginx, Node y el servicio
#       DOMINIO=midominio.com AUTH_USER=admin AUTH_PASS=clave ./deploy.sh --setup
set -euo pipefail
SERVER="${SERVER:-148.113.252.74}"
USER_SSH="${USER_SSH:-root}"
APP_DIR="${APP_DIR:-/opt/inventario}"
DOMINIO="${DOMINIO:-_}"
L="$(cd "$(dirname "$0")" && pwd)"
T="$USER_SSH@$SERVER"
SUDO=""; [ "$USER_SSH" != "root" ] && SUDO="sudo"
[ -f "$L/site/index.html" ] || { echo "Falta site/index.html"; exit 1; }

if [ "${1:-}" = "--setup" ]; then
  echo "→ Configurando servidor ..."
  scp "$L/setup-nginx.sh" "$T:/tmp/setup-nginx.sh"
  ssh "$T" "$SUDO env APP_DIR='$APP_DIR' AUTH_USER='${AUTH_USER:-}' AUTH_PASS='${AUTH_PASS:-}' bash /tmp/setup-nginx.sh '$DOMINIO'"
fi

echo "→ Subiendo archivos ..."
ssh "$T" "$SUDO mkdir -p $APP_DIR/site $APP_DIR/server && $SUDO chown -R $USER_SSH $APP_DIR/site $APP_DIR/server"
if command -v rsync >/dev/null; then
  rsync -az --delete "$L/site/" "$T:$APP_DIR/site/"
  rsync -az --delete "$L/server/" "$T:$APP_DIR/server/"
else
  scp -r "$L/site/." "$T:$APP_DIR/site/"; scp -r "$L/server/." "$T:$APP_DIR/server/"
fi
ssh "$T" "$SUDO chmod -R a+rX $APP_DIR/site $APP_DIR/server && $SUDO systemctl restart inventario && $SUDO nginx -t && $SUDO systemctl reload nginx"
echo "✔ Publicado: http://$SERVER   (datos en $APP_DIR/database/inventario.db)"
