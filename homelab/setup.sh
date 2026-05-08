#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "Setup do Homelab - CardapioZap"

for cmd in docker docker-compose curl; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "ERRO: $cmd nao encontrado"
        exit 1
    fi
done

if [ ! -f .env ]; then
    cp .env.example .env
    echo ".env criado. Edite com suas credenciais e rode novamente."
    exit 1
fi

docker-compose up -d evolution-api

echo "Aguardando Evolution API..."
for i in $(seq 1 30); do
    if curl -sf http://localhost:8080/ >/dev/null 2>&1; then
        echo "Evolution API respondendo."
        break
    fi
    sleep 2
done

echo ""
echo "Acesse http://localhost:8080/manager para criar a instancia."
echo "Siga homelab/cloudflare-tunnel.md para configurar o tunnel."
