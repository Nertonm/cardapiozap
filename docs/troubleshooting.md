# Troubleshooting

## Cardapio nao encontrado

**Sintoma:** Log mostra "Nenhum link de cardapio encontrado".

A UFCA pode nao ter publicado o cardapio da semana. Acesse manualmente:
https://www.ufca.edu.br/assuntos-estudantis/refeitorio-universitario/cardapios/

Se houver cardapio na pagina mas o bot nao encontrou, execute com `LOG_LEVEL=DEBUG`
para ver os links candidatos e ajustar o scraper se necessario.

## PDF nao convertido

**Sintoma:** Log mostra "Falha ao abrir PDF" ou "Falha ao renderizar pagina".

1. Verifique se o PDF foi baixado corretamente. O log mostra o tamanho em bytes.
2. Teste a conversao localmente:
   ```python
   from bot.pdf_converter import pdf_to_png
   with open("cardapio.pdf", "rb") as f:
       png = pdf_to_png(f.read())
   ```
3. Se o PDF tiver estrutura incomum, aumente a resolucao: `pdf_to_png(pdf_bytes, resolution=200)`.
4. Verifique se `pdfplumber` esta atualizado: `pip install --upgrade pdfplumber`.

## Sessao WhatsApp expirada

**Sintoma:** Evolution API retorna estado "disconnected".

```bash
# Verificar status
curl -H "apikey: SUA_API_KEY" \
  https://cardapiozap.exemplo.com/instance/connectionState/cardapiozap

# Tentar reconectar
curl -X PUT -H "apikey: SUA_API_KEY" \
  https://cardapiozap.exemplo.com/instance/restart/cardapiozap

# Se necessario, recriar a instancia
curl -X DELETE -H "apikey: SUA_API_KEY" \
  https://cardapiozap.exemplo.com/instance/delete/cardapiozap
```

Depois acesse o painel `/manager` para criar nova instancia e escanear QR Code.

## Tunnel indisponivel

**Sintoma:** GitHub Actions nao conecta na Evolution API.

```bash
docker logs cloudflare-tunnel
docker exec cloudflare-tunnel wget -qO- http://evolution-api:8080/
docker compose restart cloudflare-tunnel
```

Se usar Quick Tunnel (trycloudflare), a URL efemera muda a cada reinicio.
Atualize `EVOLUTION_API_URL` no GitHub Secrets.

## API key invalida

**Sintoma:** Log mostra "Erro de autenticacao (HTTP 401)".

Teste a chave manualmente:
```bash
curl -H "apikey: SUA_API_KEY" \
  https://cardapiozap.exemplo.com/instance/connectionState/cardapiozap
```

Se falhar, atualize `EVOLUTION_API_KEY` no GitHub Secrets.

## Destinatario invalido

**Sintoma:** Log mostra "Payload invalido para DESTINATARIO".

Verifique o formato:
- Individual: `5585999999999` (codigo pais + DDD + numero, sem `+`)
- Grupo: `5585888888888@g.us`

Teste manualmente:
```bash
curl -X POST https://cardapiozap.exemplo.com/message/sendMedia/cardapiozap \
  -H "Content-Type: application/json" \
  -H "apikey: SUA_API_KEY" \
  -d '{"number":"5585999999999","mediatype":"image","mimetype":"image/png",
       "caption":"Teste","media":"'$(echo -n "teste" | base64)'","fileName":"test.png"}'
```

## Cron desativado pelo GitHub

O workflow `keepalive.yml` faz um commit mensal para evitar desativacao.
Se ainda assim parou, execute o workflow manualmente: Actions → Enviar Cardapio → Run workflow.
Verifique se `.github/HEARTBEAT` esta sendo atualizado.

## Debug local

```bash
LOG_LEVEL=DEBUG python -m bot.main
```

Para testar apenas a conversao com um PDF salvo:
```python
from bot.pdf_converter import pdf_to_png
with open("cardapio.pdf", "rb") as f:
    png_bytes = pdf_to_png(f.read())
with open("output.png", "wb") as f:
    f.write(png_bytes)
```
