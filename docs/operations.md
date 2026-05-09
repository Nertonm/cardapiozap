# Guia de Operacoes

## Setup inicial

### 1. Homelab

```bash
cd homelab
cp .env.example .env
# Preencher AUTHENTICATION_API_KEY e AUTHENTICATION_INSTANCE_API_KEY
./setup.sh
```

O script instala Docker, sobe Evolution API + Cloudflare Tunnel, cria instancia
WhatsApp e gera QR Code em `/root/qrcode.png`. Veja `homelab/proxmox.md` para
deploy em Proxmox.

### 2. QR Code

Transfira e escaneie com WhatsApp:

```bash
scp root@<ip>:/root/qrcode.png .
```

### 3. Cloudflare Tunnel

Se for primeira execucao, o script pausa para autenticar o cloudflared.
Siga `homelab/cloudflare-tunnel.md` e rode `./setup.sh` novamente.

### 4. GitHub Secrets

| Secret | Descricao |
|--------|-----------|
| `EVOLUTION_API_URL` | URL do tunnel (dominio ou trycloudflare.com) |
| `EVOLUTION_API_KEY` | `AUTHENTICATION_INSTANCE_API_KEY` do .env |
| `EVOLUTION_INSTANCE` | `cardapiozap` |
| `RECIPIENTS` | Destinatarios separados por virgula |

Variaveis opcionais (Settings → Variables):

| Variable | Padrao | Descricao |
|----------|--------|-----------|
| `CARDAPIO_URL` | URL oficial UFCA | Pagina de cardapios |
| `LOG_LEVEL` | INFO | DEBUG, INFO, WARNING, ERROR |

### 5. Testar

Execute o workflow manualmente: Actions → Enviar Cardapio → Run workflow.

## Operacao diaria

1. GitHub Actions executa seg-sex 07:30 BRT
2. Scraper baixa o PDF mais recente da pagina da UFCA
3. Converte para PNG e envia para os destinatarios configurados

## Mudar horario

Edite `.github/workflows/cardapio.yml`:

```yaml
schedule:
  - cron: "30 10 * * 1-5"  # UTC: 10:30 = 07:30 BRT
```

## Adicionar/remover destinatarios

Atualize o secret `RECIPIENTS` no GitHub:
- Individual: `5585999999999` (codigo pais + DDD + numero)
- Grupo: `5585888888888@g.us`

## Descobrir JID de um grupo

```bash
curl -X POST https://cardapiozap.exemplo.com/chat/findChats/cardapiozap \
  -H "Content-Type: application/json" \
  -H "apikey: SUA_API_KEY" \
  -d '{"where": {"isGroup": true}}'
```

O campo `id` e o JID do grupo.

## Recuperar sessao WhatsApp

```bash
# Ver estado
curl -H "apikey: SUA_API_KEY" \
  https://cardapiozap.exemplo.com/instance/connectionState/cardapiozap

# Reconectar
curl -X PUT -H "apikey: SUA_API_KEY" \
  https://cardapiozap.exemplo.com/instance/restart/cardapiozap
```

Se nao resolver:

```bash
# Deletar sessao
docker compose exec evolution-api rm -rf /evolution/instances/cardapiozap
docker compose restart evolution-api

# Recriar instancia e escanear QR Code novamente
./setup.sh
```

## Atualizar stack

```bash
cd homelab
docker compose pull
docker compose up -d
```

## Reiniciar

```bash
cd homelab
docker compose down
docker compose up -d
```
