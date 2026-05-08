# Deploy do Homelab em LXC no Proxmox

## Criar o container

No shell do Proxmox:

```bash
pct create 200 \
  local:vztmpl/ubuntu-24.04-standard_24.04-1_amd64.tar.zst \
  --hostname cardapiozap \
  --cores 2 \
  --memory 2048 \
  --swap 512 \
  --rootfs local-lvm:20 \
  --net0 name=eth0,bridge=vmbr0,ip=dhcp \
  --unprivileged 1 \
  --onboot 1
```

Iniciar e acessar:

```bash
pct start 200
pct enter 200
```

## Instalar

O script `setup-baremetal.sh` automatiza tudo: Node.js, Evolution API,
instancia WhatsApp, Cloudflare Tunnel e opcionalmente auto-update do
GitHub Secret.

```bash
apt update && apt install -y git
git clone https://github.com/seu-usuario/cardapiozap.git /opt/cardapiozap
cd /opt/cardapiozap/homelab

# Com dominio proprio:
./setup-baremetal.sh cardapiozap.seu-dominio.com suachavemestra

# Sem dominio (Quick Tunnel trycloudflare.com):
./setup-baremetal.sh --quick suachavemestra

# Com auto-update do GitHub Secret (recomendado para Quick Tunnel):
./setup-baremetal.sh --quick suachavemestra "" seu-usuario/cardapiozap ghp_seutoken
```

### Argumentos do script

| Posicao | Nome | Obrigatorio | Descricao |
|---------|------|-------------|-----------|
| 1 | Dominio ou `--quick` | Sim | Dominio proprio ou flag Quick Tunnel |
| 2 | API key global | Sim | Chave mestra da Evolution API |
| 3 | Instance key | Nao | Chave da instancia (gerada automatico) |
| 4 | GitHub repo | Nao | `usuario/repo` para auto-update do secret |
| 5 | GitHub token | Nao | PAT com permissao `repo` |

### O que o script faz

1. Instala dependencias (curl, git, openssl)
2. Instala Node.js 22
3. Clona Evolution API, instala deps, cria servico systemd
4. Cria instancia WhatsApp e gera QR Code em `/root/qrcode.png`
5. Instala cloudflared, cria tunnel, configura systemd
6. Se fornecido token GitHub: instala `gh` CLI e cria timer que atualiza
   `EVOLUTION_API_URL` automaticamente a cada 5 minutos

### Apos o script

Transfira o QR Code e escaneie com o WhatsApp:

```bash
scp root@<ip-do-lxc>:/root/qrcode.png .
```

Configure os GitHub Secrets com os valores exibidos no final do script.

## Chaves da Evolution API

| Chave | Funcao | Onde vai |
|-------|--------|----------|
| Global (`AUTHENTICATION_API_KEY`) | Mestra: cria/deleta instancias, acessa `/manager` | `.env` no servidor |
| Instancia (`AUTHENTICATION_INSTANCE_API_KEY`) | Usada pelo bot pra enviar mensagens | GitHub Secret `EVOLUTION_API_KEY` |

## Auto-update do GitHub Secret

Quando o LXC reinicia com Quick Tunnel, a URL `*.trycloudflare.com` muda.
O timer systemd `cardapiozap-secret.timer` resolve isso:

1. A cada 5 minutos, le a URL atual do tunnel nos logs do systemd
2. Se mudou, atualiza `EVOLUTION_API_URL` no GitHub via `gh secret set`
3. O workflow do GitHub Actions sempre usa a URL correta

Pra funcionar, precisa de um [GitHub PAT](https://github.com/settings/tokens)
com escopo `repo`. Passe no 5o argumento do script.

Verificar:

```bash
systemctl status cardapiozap-secret.timer
journalctl -u cardapiozap-secret.service
```

## Troubleshooting

### Docker nao inicia no LXC (apenas se usar Docker)

Se optar por Docker em vez de baremetal, o LXC precisa de:

```bash
pct stop 200
pct set 200 --features nesting=1,keyctl=1
pct start 200
```

### Evolution API nao sobe

```bash
systemctl status evolution-api
journalctl -u evolution-api -n 50 --no-pager
cd /opt/evolution-api && npm run start:prod  # teste manual
```

### Sessao WhatsApp caiu

```bash
curl -X PUT -H "apikey: sua-instance-key" \
  http://localhost:8080/instance/restart/cardapiozap

# Recriar se necessario
curl -X DELETE -H "apikey: sua-instance-key" \
  http://localhost:8080/instance/delete/cardapiozap
# Depois rodar o script novamente
```

### Tunnel offline

```bash
systemctl status cloudflared
journalctl -u cloudflared -n 30
cloudflared tunnel list
```

### Auto-update falhando

```bash
systemctl status cardapiozap-secret.timer
journalctl -u cardapiozap-secret.service
gh auth status  # verificar autenticacao
```

### Container nao inicia apos reboot

O `--onboot 1` na criacao do LXC garante a inicializacao. Os systemd
services tem `WantedBy=multi-user.target` e sobem automaticamente.

## Manutencao

```bash
# Atualizar sistema
apt update && apt upgrade -y

# Atualizar Evolution API
cd /opt/evolution-api
git pull
npm install
systemctl restart evolution-api

# Atualizar cloudflared
LATEST=$(curl -s https://api.github.com/repos/cloudflare/cloudflared/releases/latest | \
    grep tag_name | cut -d'"' -f4)
curl -L "https://github.com/cloudflare/cloudflared/releases/download/${LATEST}/cloudflared-linux-amd64" \
    -o /usr/local/bin/cloudflared
chmod +x /usr/local/bin/cloudflared
systemctl restart cloudflared

# Verificar disco
df -h /
du -sh /opt/evolution-api/instances/
```
