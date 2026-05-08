#!/usr/bin/env bash
# ============================================================
# update-github-secret.sh
# Atualiza EVOLUTION_API_URL no GitHub quando o tunnel Quick
# muda de URL.
#
# Dependencias: gh CLI + token
#   gh auth login  (uma vez)
#   ou GITHUB_TOKEN=ghp_xxx no ambiente
# ============================================================
set -euo pipefail

REPO="${GITHUB_REPO:-seu-usuario/cardapiozap}"

# Descobre URL atual do tunnel
TUNNEL_URL=$(journalctl -u cloudflared --no-pager -n 50 2>/dev/null | \
    grep -oP 'https://[a-z0-9-]+\.trycloudflare\.com' | tail -1 || true)

if [ -z "$TUNNEL_URL" ]; then
    echo "URL do tunnel nao encontrada nos logs."
    exit 1
fi

echo "Tunnel: $TUNNEL_URL"

# Atualiza o secret
if [ -n "${GITHUB_TOKEN:-}" ]; then
    export GH_TOKEN="$GITHUB_TOKEN"
fi

echo "$TUNNEL_URL" | gh secret set EVOLUTION_API_URL --repo "$REPO"
echo "EVOLUTION_API_URL atualizado em $REPO"
