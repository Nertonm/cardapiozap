#!/usr/bin/env bash
set -euo pipefail

EVOLUTION_URL="${EVOLUTION_URL:-http://localhost:8080}"
TUNNEL_URL="${TUNNEL_URL:-}"

healthy=true

echo -n "Evolution API ($EVOLUTION_URL): "
if curl -sf -o /dev/null "$EVOLUTION_URL/" 2>/dev/null; then
    echo "OK"
else
    echo "FALHA"
    healthy=false
fi

if [ -n "$TUNNEL_URL" ]; then
    echo -n "Tunnel ($TUNNEL_URL): "
    if curl -sf -o /dev/null "$TUNNEL_URL/" 2>/dev/null; then
        echo "OK"
    else
        echo "FALHA"
        healthy=false
    fi
fi

echo ""
docker ps --filter "name=evolution-api" --filter "name=cloudflare-tunnel" \
    --format "  {{.Names}}: {{.Status}}" 2>/dev/null || true

if $healthy; then
    echo "Status: OK"
    exit 0
else
    echo "Status: FALHA"
    exit 1
fi
