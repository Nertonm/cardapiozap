# Arquitetura

## Componentes

```
[ufca.edu.br]  ←  [GitHub Actions: Scraper → PDF→PNG → Sender]  →  [Homelab: Evolution API]
                                                                      ↕
                                                                 [Cloudflare Tunnel]
                                                                      ↕
                                                                 [WhatsApp Web]
```

## Modulos

| Arquivo | Funcao |
|---------|--------|
| `scraper.py` | Acessa a pagina de cardapios, encontra o link, resolve redirects, baixa o PDF |
| `pdf_converter.py` | Converte PDF para PNG usando `pdfplumber.Page.to_image()` |
| `whatsapp_sender.py` | Envia imagem via Evolution API com retry e backoff |
| `config.py` | Le e valida variaveis de ambiente |
| `logging_setup.py` | Formata saida de log com timestamp UTC |
| `main.py` | Orquestra o pipeline |

## Fluxo de dados

1. **Scraper** faz GET na pagina de cardapios da UFCA
2. Extrai links para `documentos.ufca.edu.br/?post_type=doc&p=N`
3. Segue a cadeia de redirects (301) ate o PDF final
4. Confirma que o conteudo e PDF checando magic bytes `%PDF-`
5. **pdf_converter** renderiza a pagina do PDF como PNG (150 DPI)
6. **Sender** codifica em base64 e faz POST para Evolution API

## Decisoes

- **Conversao visual em vez de parsing de texto**: Mais simples, nao quebra
  quando a UFCA muda a estrutura da tabela, preserva formatacao original
- **GitHub Actions para processamento**: Ambiente efemero e reprodutivel,
  sem dependencia do homelab estar online
- **Homelab so para sessao WhatsApp**: Separacao clara entre estado
  (sessao persistente) e processamento (stateless)
- **Duas opcoes de deploy no homelab**: Baremetal (Node.js direto, sem Docker)
  ou Docker Compose. O script `setup-baremetal.sh` automatiza a instalacao
  baremetal completa
- **Cloudflare Tunnel**: Sem port-forward, HTTPS automatico, protecao DDoS
