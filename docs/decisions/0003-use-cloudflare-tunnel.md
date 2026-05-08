# ADR-0003: Cloudflare Tunnel

## Status

Aceito

## Contexto

Evolution API no homelab precisa ser acessivel pela internet. Opcoes:

1. Port-forward no roteador
2. Cloudflare Tunnel
3. VPN (Tailscale/WireGuard)

## Decisao

Cloudflare Tunnel via `cloudflared`.

## Justificativa

- Conexao outbound, sem abrir portas no roteador
- TLS automatico entre Cloudflare e servidor
- Nao requer IP fixo ou DDNS
- Cloudflare Access permite autenticacao extra no painel `/manager`
- Gratuito

## Riscos

| Risco | Mitigacao |
|-------|-----------|
| Tunnel pode cair | Container com `restart: unless-stopped` |
| Cloudflare como ponto unico de falha | Fallback manual via port-forward temporario |

## Alternativas rejeitadas

- **Port-forward**: Exige configuracao de roteador, expoe IP residencial
- **VPN**: GitHub Actions runners nao entram em redes privadas facilmente
