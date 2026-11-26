#!/usr/bin/env bash
# Descarga una copia de la base de datos a ./backups
set -euo pipefail
SERVER="${SERVER:-148.113.252.74}"; USER_SSH="${USER_SSH:-root}"; APP_DIR="${APP_DIR:-/opt/inventario}"
L="$(cd "$(dirname "$0")" && pwd)"; mkdir -p "$L/backups"
ssh "$USER_SSH@$SERVER" "cd $APP_DIR && node -e \"const {DatabaseSync}=require('node:sqlite');new DatabaseSync('database/inventario.db').exec(\\\"VACUUM INTO '/tmp/inv.db'\\\")\" && cat /tmp/inv.db && rm /tmp/inv.db" > "$L/backups/inventario-$(date +%F_%H%M).db"
echo "✔ Respaldo guardado en backups/"
