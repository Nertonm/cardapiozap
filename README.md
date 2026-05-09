# CardapioZap

Captura o PDF do cardapio do Restaurante Universitario da UFCA, converte em
imagem e envia via WhatsApp.

## Fluxo

Scraper (baixa PDF) → pdf_converter (PDF → PNG) → Sender (Evolution API)

- **GitHub Actions** processa o cardapio (scraping, conversao, envio)
- **Homelab** mantem a sessao WhatsApp (Evolution API + Cloudflare Tunnel)

## Estrutura

```
bot/                    Codigo do bot
  main.py               Orquestrador
  scraper.py            Download do PDF
  pdf_converter.py      PDF → PNG
  whatsapp_sender.py    Envio via Evolution API
  config.py             Variaveis de ambiente
  logging_setup.py      Logging
  requirements.txt      requests, beautifulsoup4, pdfplumber
.github/workflows/
  cardapio.yml          Execucao seg-sex 07:30 BRT
  keepalive.yml         Heartbeat mensal
homelab/
  docker-compose.yml    Evolution API + Cloudflare Tunnel
  setup.sh              Instalacao automatizada
  healthcheck.sh        Verificacao de saude
  cloudflare-tunnel.md  Guia do tunnel
  proxmox.md            Deploy em LXC no Proxmox
  .env.example          Template de credenciais
docs/
  architecture.md       Detalhes tecnicos
  operations.md         Guia de operacao
  troubleshooting.md    Solucao de problemas
  security.md           Seguranca
  decisions/            Registro de decisoes
```

## Configuracao

### Homelab (LXC/VM com Docker)

```bash
cd homelab
cp .env.example .env
# Preencher AUTHENTICATION_API_KEY e AUTHENTICATION_INSTANCE_API_KEY
./setup.sh
```

O script instala Docker, sobe Evolution API + Cloudflare Tunnel, cria instancia
WhatsApp e gera QR Code. Veja `homelab/proxmox.md` para deploy em Proxmox.

### GitHub Secrets

| Secret | Descricao |
|--------|-----------|
| `EVOLUTION_API_URL` | URL da Evolution API via tunnel |
| `EVOLUTION_API_KEY` | API key da instancia |
| `EVOLUTION_INSTANCE` | Nome da instancia |
| `RECIPIENTS` | Destinatarios separados por virgula |

Variaveis opcionais (Settings → Variables → Actions):

| Variable | Padrao | Descricao |
|----------|--------|-----------|
| `CARDAPIO_URL` | URL oficial UFCA | Pagina de cardapios |
| `LOG_LEVEL` | INFO | DEBUG, INFO, WARNING, ERROR |

### Execucao local

```bash
pip install -r bot/requirements.txt
export EVOLUTION_API_URL="https://cardapiozap.exemplo.com"
export EVOLUTION_API_KEY="..."
export EVOLUTION_INSTANCE="cardapiozap"
export RECIPIENTS="5585999999999"
python -m bot.main
```

## Destinatarios

- Individual: `5585999999999` (codigo pais + DDD + numero)
- Grupo: `5585888888888@g.us`

## Agendamento

Segunda a sexta 07:30 BRT. Para alterar, editar o cron em
`.github/workflows/cardapio.yml`.

## Falhas

| Situacao | Comportamento |
|----------|---------------|
| Sem cardapio publicado | Erro, codigo de saida 1 |
| PDF com estrutura diferente | Erro na conversao |
| Evolution API offline | Retry com backoff (3 tentativas) |
| API key invalida | Erro imediato, sem retry |

## Seguranca

Credenciais apenas via variaveis de ambiente e GitHub Secrets.
API keys nunca aparecem em logs. Evolution API exposta via Cloudflare Tunnel (HTTPS).
Ver `docs/security.md`.
