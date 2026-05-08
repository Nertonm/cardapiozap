# ADR-0002: Evolution API

## Status

Aceito

## Contexto

Envio de mensagens WhatsApp. Opcoes:

1. WhatsApp Business API (Meta) — oficial, requer aprovacao
2. Evolution API — nao-oficial, baseada em WhatsApp Web

## Decisao

Evolution API no homelab.

## Justificativa

- Sem processo de aprovacao da Meta
- Suporte a envio para grupos (limitado na API oficial)
- Open source (Apache 2.0), sem custo por mensagem
- Sessao no proprio hardware, sem intermediarios
- API REST simples

## Riscos

| Risco | Mitigacao |
|-------|-----------|
| Sessao pode cair | Volume persistente + doc de recuperacao |
| API pode quebrar com updates do WhatsApp | Imagem `:latest` atualizada |
| Exposicao da API | Cloudflare Tunnel + API key |

## Alternativas rejeitadas

- **WhatsApp Business API**: Burocracia excessiva para projeto pessoal
