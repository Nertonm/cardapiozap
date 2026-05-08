# Guia de Operacoes

## Setup inicial

### 1. Homelab

**Baremetal (recomendado para LXC/VM):**

```bash
cd homelab

# Com dominio proprio:
./setup-baremetal.sh cardapiozap.seu-dominio.com suachaveglobal

# Sem dominio (Quick Tunnel):
./setup-baremetal.sh --quick suachaveglobal

# Com auto-update do GitHub Secret:
./setup-baremetal.sh --quick suachaveglobal "" seu-usuario/repo ghp_token
```

O script instala tudo e exibe as credenciais no final. Veja `homelab/proxmox.md`.

**Docker:**

```bash
cd homelab
cp .env.example .env
docker compose up -d
```

### 2. Instancia WhatsApp

O script baremetal cria a instancia automaticamente. Para Docker, faca manualmente:

Acesse o painel: `http://localhost:8080/manager`

Ou via API:

```bash
curl -X POST http://localhost:8080/instance/create \
  -H "Content-Type: application/json" \
  -H "apikey: SUA_API_KEY_GLOBAL" \
  -d '{
    "instanceName": "cardapiozap",
    "token": "SUA_API_KEY_DA_INSTANCIA",
    "qrcode": true
  }'
```

### 3. Escanear QR Code

```bash
curl http://localhost:8080/instance/connect/cardapiozap \
  -H "apikey: SUA_API_KEY_DA_INSTANCIA"
```

Copie a string base64 do campo `qrcode` e converta para imagem:

```bash
echo "STRING_BASE64" | base64 -d > qrcode.png
```

Escaneie o QR Code com o WhatsApp no celular.

### 4. Configurar Cloudflare Tunnel

Siga `homelab/cloudflare-tunnel.md`.

### 5. Configurar GitHub Secrets

No repositório GitHub, vá em Settings → Secrets and variables → Actions:

| Secret | Descrição |
|--------|-----------|
| `EVOLUTION_API_URL` | URL da Evolution API via tunnel. Ex: `https://cardapiozap.seu-dominio.com` |
| `EVOLUTION_API_KEY` | API key da instância (token definido na criação) |
| `EVOLUTION_INSTANCE` | Nome da instância. Ex: `cardapiozap` |
| `RECIPIENTS` | Destinatários separados por vírgula. Ex: `5585999999999,5585888888888@g.us` |

### 6. Testar

Execute o workflow manualmente: Actions → Enviar Cardápio → Run workflow.

## Operação diária

O fluxo é totalmente automatizado:

1. GitHub Actions executa o workflow em dias úteis às 07:30 BRT
2. O bot faz scraping da página da UFCA
3. Se houver cardapio publicado, processa e envia
4. Se não houver, falha com erro claro nos logs

## Mudar horário do cron

Edite `.github/workflows/cardapio.yml`:

```yaml
schedule:
  # Formato: minuto hora dia-mês mês dia-semana (UTC)
  - cron: "30 10 * * 1-5"  # 10:30 UTC = 07:30 BRT
```

## Adicionar/remover destinatários

Atualize o secret `RECIPIENTS` no GitHub. Formato:

- Número individual: `5585999999999` (código do país + DDD + número)
- Grupo: `5585888888888@g.us`

Para descobrir o JID de um grupo, veja a seção abaixo.

## Descobrir JID de um grupo

1. Envie uma mensagem qualquer para o grupo
2. Consulte a Evolution API:

```bash
curl -X POST https://cardapiozap.seu-dominio.com/chat/findChats/cardapiozap \
  -H "Content-Type: application/json" \
  -H "apikey: SUA_API_KEY" \
  -d '{"where": {"isGroup": true}}'
```

3. O campo `id` no resultado contém o JID do grupo (ex: `5585888888888@g.us`)

## Recuperar sessão do WhatsApp

Se a sessão cair (WhatsApp Web desconectado):

1. Verifique se o volume `evolution_instances` está íntegro:
   ```bash
   docker exec evolution-api ls -la /evolution/instances/
   ```

2. Se a instância ainda existir, tente reconectar:
   ```bash
   curl -X PUT https://cardapiozap.seu-dominio.com/instance/restart/cardapiozap \
     -H "apikey: SUA_API_KEY"
   ```

3. Se precisar recriar, delete a instância e crie novamente (será necessário
   escanear o QR Code novamente).

## Atualizar dependências do bot

```bash
cd bot
pip install --upgrade -r requirements.txt
# Testar antes de fazer deploy
python -m bot.main
```

## Reiniciar stack do homelab

```bash
cd homelab
docker-compose down
docker-compose up -d
```
