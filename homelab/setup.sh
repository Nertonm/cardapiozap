#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# setup.sh — Deploy completo com Docker no LXC/VM
#
# Uso:
#   ./setup.sh
#
# Configuracao via .env (copia de .env.example):
#   cp .env.example .env
#   nano .env
#   ./setup.sh
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[ERRO]${NC} $*" >&2; exit 1; }
info() { echo ">>> $*"; }

# -----------------------------------------------------------
# 1. .env
# -----------------------------------------------------------
if [ ! -f .env ]; then
    cp .env.example .env
    warn ".env criado. Edite com suas credenciais e rode novamente."
    echo ""
    cat .env.example
    exit 1
fi

set -a; source .env; set +a

required() {
    local val="${1:-}"
    local name="$2"
    if [ -z "$val" ]; then
        err "$name nao definido no .env"
    fi
}

required "$AUTHENTICATION_API_KEY" "AUTHENTICATION_API_KEY"
required "$AUTHENTICATION_INSTANCE_API_KEY" "AUTHENTICATION_INSTANCE_API_KEY"

# -----------------------------------------------------------
# 2. Docker
# -----------------------------------------------------------
if ! command -v docker &>/dev/null; then
    info "Instalando Docker..."
    curl -fsSL https://get.docker.com | sh
fi
log "Docker $(docker --version)"

# -----------------------------------------------------------
# 3. Subir stack
# -----------------------------------------------------------
info "Subindo containers..."

# Garantir que as portas nao conflitem (bind so em localhost)
export COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"

docker compose pull evolution-api
docker compose up -d

info "Aguardando Evolution API..."
for i in $(seq 1 30); do
    if curl -s http://localhost:8080/ >/dev/null 2>&1; then
        log "Evolution API respondendo"
        break
    fi
    sleep 2
done

if ! curl -s http://localhost:8080/ >/dev/null 2>&1; then
    docker compose logs evolution-api
    err "Evolution API nao subiu"
fi

# -----------------------------------------------------------
# 4. Instancia WhatsApp
# -----------------------------------------------------------
info "Criando instancia WhatsApp..."

API_KEY="$AUTHENTICATION_API_KEY"
INSTANCE_KEY="$AUTHENTICATION_INSTANCE_API_KEY"

if curl -sf -H "apikey: $INSTANCE_KEY" http://localhost:8080/instance/connect/cardapiozap >/dev/null 2>&1; then
    log "Instancia cardapiozap ja existe"
else
    curl -sf -X POST http://localhost:8080/instance/create \
        -H "Content-Type: application/json" \
        -H "apikey: $API_KEY" \
        -d "{\"instanceName\":\"cardapiozap\",\"token\":\"$INSTANCE_KEY\",\"qrcode\":true,\"integration\":\"WHATSAPP-BAILEYS\"}" \
        >/dev/null
    log "Instancia criada"
fi

# QR Code
QR=$(curl -sf -H "apikey: $INSTANCE_KEY" \
    http://localhost:8080/instance/connect/cardapiozap | \
    python3 -c "import sys,json; print(json.load(sys.stdin).get('qrcode',''))" 2>/dev/null || true)

if [ -n "$QR" ]; then
    echo "$QR" | base64 -d > /root/qrcode.png
    log "QR Code: /root/qrcode.png"
    echo "  scp root@<ip>:/root/qrcode.png ."
else
    warn "Nao foi possivel obter QR Code"
    echo "  curl -H 'apikey: $INSTANCE_KEY' http://localhost:8080/instance/connect/cardapiozap"
fi

# -----------------------------------------------------------
# 5. Cloudflare Tunnel
# -----------------------------------------------------------
if [ -n "${DOMINIO:-}" ]; then
  # Named tunnel (com dominio proprio)
  if [ ! -f cloudflared/cert.pem ]; then
    echo ""
    echo "=============================================="
    echo "  Autenticacao Cloudflare Tunnel pendente"
    echo "=============================================="
    echo ""
    echo "  docker run --rm -v \$(pwd)/cloudflared:/home/nonroot/.cloudflared \\"
    echo "    cloudflare/cloudflared tunnel login"
    echo ""
    echo "  Siga o link no navegador. Depois rode este script novamente."
    echo ""
    exit 0
  fi

  if ! docker run --rm -v "$(pwd)/cloudflared:/home/nonroot/.cloudflared" \
      cloudflare/cloudflared tunnel list 2>/dev/null | grep -q cardapiozap; then
      docker run --rm -v "$(pwd)/cloudflared:/home/nonroot/.cloudflared" \
          cloudflare/cloudflared tunnel create cardapiozap
  fi

  TUNNEL_ID=$(docker run --rm -v "$(pwd)/cloudflared:/home/nonroot/.cloudflared" \
      cloudflare/cloudflared tunnel list --output json 2>/dev/null | \
      grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)

  docker run --rm -v "$(pwd)/cloudflared:/home/nonroot/.cloudflared" \
      cloudflare/cloudflared tunnel route dns cardapiozap "$DOMINIO" 2>/dev/null || \
      warn "Configure DNS: CNAME ${DOMINIO} -> ${TUNNEL_ID}.cfargotunnel.com"

  docker compose up -d cloudflare-tunnel
  log "Tunnel rodando"
else
  # Quick Tunnel (URL efemera, sem dominio)
  info "Quick Tunnel — aguardando URL..."
  sleep 5
  TUNNEL_URL=$(docker compose logs cloudflare-tunnel 2>/dev/null | grep -oP 'https://[a-z0-9-]+\.trycloudflare\.com' | tail -1 || true)
  if [ -z "$TUNNEL_URL" ]; then
    warn "Tunnel ainda subindo, verifique: docker compose logs cloudflare-tunnel"
  else
    log "Tunnel URL: ${TUNNEL_URL}"
  fi
fi

# -----------------------------------------------------------
# Resumo
# -----------------------------------------------------------
echo ""
echo "=============================================="
echo "  Setup concluido"
echo "=============================================="
echo ""
echo "Containers:"
docker compose ps --format "  {{.Name}}: {{.Status}}"
echo ""
echo "API Key global    : ${API_KEY}"
echo "API Key instancia : ${INSTANCE_KEY}"
echo ""

if [ -n "${DOMINIO:-}" ]; then
    echo "Tunnel URL: https://${DOMINIO}"
    echo ""
    echo "GitHub Secrets:"
    echo "  EVOLUTION_API_URL   = https://${DOMINIO}"
else
    echo "GitHub Secrets:"
    echo "  EVOLUTION_API_URL   = $(docker compose logs cloudflare-tunnel 2>/dev/null | grep -oP 'https://[a-z0-9-]+\.trycloudflare\.com' | tail -1 || echo '<url-do-quick-tunnel>')"
fi

echo "  EVOLUTION_API_KEY    = ${INSTANCE_KEY}"
echo "  EVOLUTION_INSTANCE   = cardapiozap"
echo "  RECIPIENTS           = 5585999999999"
echo ""
echo "Status:"
echo "  docker compose ps"
echo "  docker compose logs -f"
echo "=============================================="
