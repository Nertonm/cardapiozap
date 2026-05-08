#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# setup-baremetal.sh — Deploy baremetal do CardapioZap no LXC
# Execute DENTRO do container LXC como root.
#
# Com dominio proprio:
#   ./setup-baremetal.sh cardapiozap.seu-dominio.com suachaveglobal
#
# Sem dominio (Quick Tunnel trycloudflare.com):
#   ./setup-baremetal.sh --quick suachaveglobal
#
# Com auto-update do secret no GitHub (recomendado para Quick):
#   ./setup-baremetal.sh --quick suachaveglobal "" seu-usuario/cardapiozap ghp_seutoken
# ============================================================

QUICK=false
DOMINIO=""
GITHUB_REPO="${GITHUB_REPO:-}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"

# Parse argumentos
case "${1:-}" in
    --quick)
        QUICK=true
        API_KEY="${2:-}"
        INSTANCE_KEY="${3:-}"
        GITHUB_REPO="${4:-$GITHUB_REPO}"
        GITHUB_TOKEN="${5:-$GITHUB_TOKEN}"
        ;;
    *)
        DOMINIO="${1:-}"
        API_KEY="${2:-}"
        INSTANCE_KEY="${3:-}"
        GITHUB_REPO="${4:-$GITHUB_REPO}"
        GITHUB_TOKEN="${5:-$GITHUB_TOKEN}"
        ;;
esac

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[ERRO]${NC} $*" >&2; exit 1; }
info() { echo ">>> $*"; }

if [ -z "$API_KEY" ]; then
    echo "Uso:"
    echo "  $0 <dominio> <api-key-global> [instance-key] [github-repo] [github-token]"
    echo "  $0 --quick <api-key-global> [instance-key] [github-repo] [github-token]"
    echo ""
    echo "Argumentos:"
    echo "  api-key-global  Chave mestra da Evolution API (qualquer string longa)"
    echo "  instance-key    Chave da instancia WhatsApp (gerado se omitido)"
    echo "  github-repo     Ex: seu-usuario/cardapiozap (para auto-update do secret)"
    echo "  github-token    GitHub PAT com permissao repo (para auto-update)"
    echo ""
    echo "Exemplos:"
    echo "  $0 cardapiozap.meudominio.com minhachave"
    echo "  $0 --quick minhachave '' seu-usuario/cardapiozap ghp_xxx"
    exit 1
fi

INSTANCE_KEY="${INSTANCE_KEY:-$(openssl rand -hex 32)}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ============================================================
# 1. Dependencias de sistema
# ============================================================
info "Instalando dependencias..."
apt update -qq && apt install -y -qq curl git openssl

# ============================================================
# 2. Node.js
# ============================================================
if ! command -v node &>/dev/null; then
    info "Instalando Node.js 22..."
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
    apt install -y -qq nodejs
fi
log "Node $(node --version)"

# ============================================================
# 3. Evolution API
# ============================================================
if [ ! -d /opt/evolution-api ]; then
    info "Clonando Evolution API..."
    git clone --depth 1 https://github.com/EvolutionAPI/evolution-api.git /opt/evolution-api
fi

info "Instalando dependencias npm..."
cd /opt/evolution-api
npm install --quiet

info "Configurando..."
cat > /opt/evolution-api/.env << EOF
AUTHENTICATION_API_KEY=${API_KEY}
AUTHENTICATION_INSTANCE_NAME=cardapiozap
AUTHENTICATION_INSTANCE_API_KEY=${INSTANCE_KEY}
SERVER_PORT=8080
SERVER_URL=http://localhost:8080
LANGUAGE=pt-BR
AUTHENTICATION_EXPOSE_IN_FETCH_INSTANCES=false
EOF

cat > /etc/systemd/system/evolution-api.service << 'UNIT'
[Unit]
Description=Evolution API
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/evolution-api
ExecStart=/usr/bin/npm run start:prod
Restart=always
RestartSec=10
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now evolution-api

for i in $(seq 1 15); do
    if curl -sf http://localhost:8080/ >/dev/null 2>&1; then break; fi
    sleep 2
done
curl -sf http://localhost:8080/ >/dev/null 2>&1 || \
    err "Evolution API nao subiu. journalctl -u evolution-api -n 30"
log "Evolution API :8080"

# ============================================================
# 4. Instancia WhatsApp
# ============================================================
info "Criando instancia WhatsApp..."
if curl -sf -H "apikey: $INSTANCE_KEY" http://localhost:8080/instance/connect/cardapiozap >/dev/null 2>&1; then
    log "Instancia cardapiozap ja existe"
else
    curl -sf -X POST http://localhost:8080/instance/create \
        -H "Content-Type: application/json" \
        -H "apikey: $API_KEY" \
        -d "{\"instanceName\":\"cardapiozap\",\"token\":\"$INSTANCE_KEY\",\"qrcode\":true}" \
        >/dev/null
    log "Instancia criada"
fi

QR_BASE64=$(curl -sf -H "apikey: $INSTANCE_KEY" \
    http://localhost:8080/instance/connect/cardapiozap | grep -o '"qrcode":"[^"]*"' | cut -d'"' -f4)

if [ -n "$QR_BASE64" ] && [ "$QR_BASE64" != "null" ]; then
    echo "$QR_BASE64" | base64 -d > /root/qrcode.png
    log "QR Code: /root/qrcode.png"
else
    warn "Nao foi possivel obter QR Code. Rode manualmente:"
    echo "  curl -H 'apikey: $INSTANCE_KEY' http://localhost:8080/instance/connect/cardapiozap"
fi

# ============================================================
# 5. Cloudflare Tunnel
# ============================================================
if ! command -v cloudflared &>/dev/null; then
    info "Instalando cloudflared..."
    curl -fsSL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 \
        -o /usr/local/bin/cloudflared
    chmod +x /usr/local/bin/cloudflared
fi
log "cloudflared $(cloudflared --version)"

if [ ! -f /root/.cloudflared/cert.pem ]; then
    echo ""
    echo "=============================================="
    echo "  cloudflared ainda nao autenticado"
    echo "=============================================="
    echo ""
    echo "  cloudflared tunnel login"
    echo ""
    echo "Rode o link que aparecer no navegador, depois execute"
    echo "este script novamente."
    echo ""
    exit 0
fi

info "Criando tunnel..."
cloudflared tunnel list 2>/dev/null | grep -q cardapiozap || cloudflared tunnel create cardapiozap

TUNNEL_ID=$(cloudflared tunnel list --output json 2>/dev/null | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
mkdir -p /etc/cloudflared

if $QUICK; then
    info "Modo Quick Tunnel..."
    cat > /etc/cloudflared/config.yml << EOF
tunnel: ${TUNNEL_ID}
credentials-file: /root/.cloudflared/${TUNNEL_ID}.json

ingress:
  - hostname: "*"
    service: http://localhost:8080
  - service: http_status:404
EOF
else
    info "Tunnel para ${DOMINIO}..."
    cat > /etc/cloudflared/config.yml << EOF
tunnel: ${TUNNEL_ID}
credentials-file: /root/.cloudflared/${TUNNEL_ID}.json

ingress:
  - hostname: ${DOMINIO}
    service: http://localhost:8080
  - service: http_status:404
EOF
    cloudflared tunnel route dns cardapiozap "$DOMINIO" 2>/dev/null || \
        warn "Configure o DNS: CNAME ${DOMINIO} -> ${TUNNEL_ID}.cfargotunnel.com"
fi

cat > /etc/systemd/system/cloudflared.service << 'UNIT'
[Unit]
Description=Cloudflare Tunnel
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/cloudflared tunnel --config /etc/cloudflared/config.yml run
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now cloudflared

if $QUICK; then
    sleep 5
    TUNNEL_URL=$(journalctl -u cloudflared --no-pager -n 20 2>/dev/null | \
        grep -oP 'https://[a-z0-9-]+\.trycloudflare\.com' | tail -1 || true)
    if [ -z "$TUNNEL_URL" ]; then
        TUNNEL_URL="https://<veja-logs>.trycloudflare.com"
        warn "Nao detectei a URL. Veja: journalctl -u cloudflared -f"
    fi
    DOMINIO="$TUNNEL_URL"
fi
log "Tunnel rodando"

# ============================================================
# 6. Auto-update do GitHub Secret
# ============================================================
if [ -n "$GITHUB_TOKEN" ] && [ -n "$GITHUB_REPO" ]; then
    info "Configurando auto-update do GitHub Secret..."

    # Instalar gh CLI
    if ! command -v gh &>/dev/null; then
        curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | \
            dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg 2>/dev/null
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
            > /etc/apt/sources.list.d/github-cli.list
        apt update -qq && apt install -y -qq gh
    fi
    log "gh $(gh --version | head -1)"

    # Copiar script de update
    mkdir -p /opt/cardapiozap/homelab
    if [ -f "$SCRIPT_DIR/update-github-secret.sh" ]; then
        cp "$SCRIPT_DIR/update-github-secret.sh" /opt/cardapiozap/homelab/
        chmod +x /opt/cardapiozap/homelab/update-github-secret.sh
    fi

    # Timer systemd (roda a cada 5 min, atualiza se a URL mudou)
    cat > /etc/systemd/system/cardapiozap-secret.service << EOF
[Unit]
Description=Atualizar EVOLUTION_API_URL no GitHub
After=network.target cloudflared.service

[Service]
Type=oneshot
ExecStart=/opt/cardapiozap/homelab/update-github-secret.sh
Environment=GITHUB_REPO=${GITHUB_REPO}
Environment=GITHUB_TOKEN=${GITHUB_TOKEN}
EOF

    cat > /etc/systemd/system/cardapiozap-secret.timer << 'EOF'
[Unit]
Description=Sync tunnel URL para GitHub Secrets

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
Persistent=true

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    systemctl enable --now cardapiozap-secret.timer

    # Executa uma vez agora
    systemctl start cardapiozap-secret.service 2>/dev/null || true

    log "Auto-update ativo (timer a cada 5min)"
else
    warn "Auto-update nao configurado (sem GITHUB_REPO/GITHUB_TOKEN)"
    if $QUICK; then
        echo "  Para ativar, passe o repo e token como argumentos 4 e 5."
        echo "  Ex: $0 --quick suachave '' seu-usuario/cardapiozap ghp_xxx"
    fi
fi

# ============================================================
# Resumo
# ============================================================
echo ""
echo "=============================================="
echo "  Setup concluido"
echo "=============================================="
echo ""
echo "Evolution API : http://localhost:8080"
echo "Tunnel        : ${DOMINIO}"
echo ""
echo "API Key global    : ${API_KEY}"
echo "API Key instancia : ${INSTANCE_KEY}"
echo ""

if $QUICK; then
    echo "Quick Tunnel ativo — a URL muda a cada reinicio."
    if [ -n "$GITHUB_TOKEN" ]; then
        echo "Auto-update do GitHub Secret configurado."
    else
        echo "Atualize EVOLUTION_API_URL manualmente no GitHub quando reiniciar."
    fi
fi

echo "QR Code: /root/qrcode.png"
echo ""
echo "GitHub Secrets:"
echo "  EVOLUTION_API_URL   = ${DOMINIO}"
echo "  EVOLUTION_API_KEY    = ${INSTANCE_KEY}"
echo "  EVOLUTION_INSTANCE   = cardapiozap"
echo "  RECIPIENTS           = 5585999999999"
echo ""
echo "Status:"
echo "  systemctl status evolution-api cloudflared"
echo "  systemctl status cardapiozap-secret.timer   # se auto-update ativo"
echo "=============================================="
