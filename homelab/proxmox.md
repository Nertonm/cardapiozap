# Deploy do Homelab em LXC no Proxmox

## Criar o container

No shell do Proxmox (precisa de `nesting=1` pra Docker):

```bash
pct create 200 \
  local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst \
  --hostname cardapiozap \
  --cores 2 \
  --memory 2048 \
  --swap 512 \
  --rootfs local-lvm:20 \
  --net0 name=eth0,bridge=vmbr0,ip=dhcp \
  --unprivileged 1 \
  --features nesting=1,keyctl=1 \
  --onboot 1

pct start 200 && pct enter 200
```

`--features nesting=1,keyctl=1` e obrigatorio pra Docker rodar dentro de LXC.

## Instalar

Dentro do container:

```bash
apt update && apt install -y git curl
git clone https://github.com/nertonm/cardapiozap.git /opt/cardapiozap
cd /opt/cardapiozap/homelab

cp .env.example .env
nano .env   # preencher as duas chaves
./setup.sh
```

### .env minimo

```env
AUTHENTICATION_API_KEY=minhasenha123
AUTHENTICATION_INSTANCE_API_KEY=outra-senha-456
```

As chaves sao strings que voce inventa. Nada pre-existente.

## O que o setup.sh faz

1. Instala Docker
2. Sobe Evolution API + Cloudflare Tunnel via docker compose
3. Cria instancia WhatsApp e gera QR Code em `/root/qrcode.png`
4. Se cloudflared ja estiver autenticado, sobe o tunnel

## Cloudflare Tunnel

Primeira vez, autenticar:

```bash
docker run --rm -v $(pwd)/cloudflared:/home/nonroot/.cloudflared \
  cloudflare/cloudflared tunnel login
```

Abrir o link no navegador, autorizar. Depois rodar `./setup.sh` novamente.

### Com dominio proprio

Adicione no `.env`:

```env
DOMINIO=cardapiozap.seu-dominio.com
```

O setup.sh configura o DNS automaticamente.

### Sem dominio (Quick Tunnel)

Edite `cloudflared/config.yml`:

```yaml
tunnel: <UUID>
credentials-file: /etc/cloudflared/<UUID>.json
ingress:
  - hostname: "*"
    service: http://evolution-api:8080
  - service: http_status:404
```

A URL efemera aparece nos logs. Atualize `EVOLUTION_API_URL` no GitHub quando reiniciar.

## QR Code

```bash
# Verificar se foi gerado
ls -la /root/qrcode.png

# Transferir pra sua maquina
scp root@<ip-do-lxc>:/root/qrcode.png .
```

O QR expira rapido (em poucos segundos). Se o WhatsApp acusar codigo invalido:

```bash
cd /opt/cardapiozap/homelab
./setup.sh
ls -lah /root/qrcode.png
scp root@<ip-do-lxc>:/root/qrcode.png .
```

Escaneie imediatamente apos copiar o arquivo.

Escaneie com WhatsApp (Configuracoes → Dispositivos conectados).

## GitHub Secrets

| Secret | Valor |
|--------|-------|
| `EVOLUTION_API_URL` | URL do tunnel (dominio ou trycloudflare) |
| `EVOLUTION_API_KEY` | `AUTHENTICATION_INSTANCE_API_KEY` do .env |
| `EVOLUTION_INSTANCE` | `cardapiozap` |
| `RECIPIENTS` | Numeros separados por virgula |

## Troubleshooting

### Docker nao inicia

```bash
# Precisa de nesting=1,keyctl=1 no LXC
pct stop 200
pct set 200 --features nesting=1,keyctl=1
pct start 200
```

### Evolution API nao sobe

```bash
docker compose logs evolution-api
docker compose restart evolution-api
```

### Sessao WhatsApp caiu

```bash
docker compose restart evolution-api
# Se nao resolver, deletar e recriar:
docker compose exec evolution-api rm -rf /evolution/instances/cardapiozap
docker compose restart evolution-api
# Depois criar instancia novamente e escanear QR Code
```

### Container nao inicia apos reboot

O `--onboot 1` resolve. Docker e os containers sobem automaticamente.

### Manutencao

```bash
cd /opt/cardapiozap/homelab
docker compose pull    # atualizar imagens
docker compose up -d
docker system prune -af  # limpar imagens antigas
```
