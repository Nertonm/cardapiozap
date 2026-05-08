# ADR-0001: GitHub Actions para job agendado

## Status

Aceito

## Contexto

O bot precisa executar automaticamente em dias uteis. Opcoes consideradas:

1. GitHub Actions com schedule trigger
2. Cron no homelab
3. Servico externo (n8n, Zapier)

## Decisao

GitHub Actions.

## Justificativa

- Separacao de responsabilidades: homelab mantem sessao WhatsApp,
  processamento roda em ambiente efemero
- Alta disponibilidade gerenciada pelo GitHub
- Ambiente reprodutivel definido por codigo (ubuntu-latest, Python 3.12)
- Custo zero para repositorios publicos
- Logs centralizados com notificacao de falha
- Keepalive mensal evita desativacao de crons inativos

## Alternativas rejeitadas

- **Cron no homelab**: Acopla processamento ao servidor. Se offline,
  perde-se execucao e sessao
- **Servicos externos**: Custo e complexidade desnecessarios
