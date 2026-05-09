# Configuração do Cloudflare Tunnel

## Pré-requisitos

- Conta no Cloudflare (gratuita)
- Um domínio gerenciado pelo Cloudflare (opcional, mas recomendado)
- `cloudflared` instalado localmente para autenticação inicial

## Passo a passo

### 1. Autenticar o cloudflared

No servidor do homelab, execute uma vez:

```bash
docker run --rm -v $(pwd)/cloudflared:/home/nonroot/.cloudflared \
    cloudflare/cloudflared tunnel login
```

Siga o link gerado para autorizar o túnel na sua conta Cloudflare.

### 2. Criar o túnel

```bash
docker run --rm -v $(pwd)/cloudflared:/home/nonroot/.cloudflared \
    cloudflare/cloudflared tunnel create cardapiozap
```

Isso gera o arquivo de credenciais em `cloudflared/<UUID>.json`.

### 3. Criar arquivo de configuracao

Crie `cloudflared/config.yml` (a partir do diretorio `homelab/`):

```yaml
tunnel: <UUID_DO_TUNEL>
credentials-file: /etc/cloudflared/<UUID>.json

ingress:
  # Expor a Evolution API
  - hostname: cardapiozap.seu-dominio.com
    service: http://evolution-api:8080

  # Serviço padrão (nega acesso não mapeado)
  - service: http_status:404
```

Substitua:
- `<UUID_DO_TUNEL>` pelo UUID gerado no passo 2
- `cardapiozap.seu-dominio.com` pelo seu domínio (ou use `*.seu-dominio.com`)

### 4. Criar registro DNS (opcional se usar quick tunnel)

```bash
cloudflared tunnel route dns cardapiozap cardapiozap.seu-dominio.com
```

Ou faça manualmente no painel do Cloudflare (DNS → CNAME apontando para `<UUID>.cfargotunnel.com`).

### 5. Subir os containers

```bash
docker compose up -d
```

### 6. Testar

```bash
curl -H "apikey: sua-api-key" https://cardapiozap.seu-dominio.com/
```

## Sem dominio proprio (Quick Tunnel)

Edite `homelab/cloudflared/config.yml` com `hostname: "*"`:

```yaml
tunnel: <UUID_DO_TUNEL>
credentials-file: /etc/cloudflared/<UUID>.json

ingress:
  - hostname: "*"
    service: http://evolution-api:8080
  - service: http_status:404
```

Suba com `docker compose up -d cloudflare-tunnel` e veja a URL efemera
nos logs: `docker logs cloudflare-tunnel`.

URLs efemeras mudam a cada reinicio. Atualize `EVOLUTION_API_URL` no
GitHub Secrets sempre que reiniciar.

## Segurança adicional

### Proteger o /manager com Cloudflare Access

1. No painel Cloudflare, vá em Zero Trust → Access → Applications
2. Crie uma aplicação Self-hosted
3. Configure:
   - **Application domain:** `cardapiozap.seu-dominio.com/manager`
   - **Identity providers:** GitHub, Google, ou Email OTP
   - **Policy:** Allow apenas seu email

Isso garante que apenas você acesse o painel administrativo.

### Desabilitar /manager completamente

Se não precisar do painel administrativo após setup:

```yaml
No `docker-compose.yml`, adicione a configuracao do evolution-api:
environment:
  AUTHENTICATION_EXPOSE_IN_FETCH_INSTANCES: "false"
```

Ou configure no `.env`:

```env
AUTHENTICATION_EXPOSE_IN_FETCH_INSTANCES=false
```

## Troubleshooting

### Tunnel não conecta

```bash
docker logs cloudflare-tunnel
```

Verifique se:
- O arquivo de credenciais existe em `cloudflared/`
- O UUID no `config.yml` corresponde ao criado
- A máquina tem acesso à internet (HTTPS outbound na porta 7844)

### Evolution API não responde via tunnel

```bash
# Teste localmente primeiro
curl http://localhost:8080/

# Verifique a rede entre containers
docker exec cloudflare-tunnel wget -qO- http://evolution-api:8080/
```
