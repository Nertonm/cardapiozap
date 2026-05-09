# Guia de Segurança

## Princípios

1. **Nenhum segredo no código** — todas as credenciais vêm de variáveis de ambiente
2. **Defesa em profundidade** — múltiplas camadas de proteção
3. **Menor privilégio** — cada componente só acessa o que precisa
4. **Fail secure** — em caso de dúvida estrutural, o sistema falha em vez de
   enviar dados potencialmente errados

## Segredos e onde ficam

| Secret | Onde fica | Quem acessa |
|--------|-----------|-------------|
| `EVOLUTION_API_URL` | GitHub Secrets | Workflow `cardapio.yml` |
| `EVOLUTION_API_KEY` | GitHub Secrets | Workflow `cardapio.yml` |
| `EVOLUTION_INSTANCE` | GitHub Secrets | Workflow `cardapio.yml` |
| `RECIPIENTS` | GitHub Secrets | Workflow `cardapio.yml` |
| `AUTHENTICATION_API_KEY` | `.env` no homelab | Docker Compose |
| `AUTHENTICATION_INSTANCE_API_KEY` | `.env` no homelab | Docker Compose |

**Importante:** O arquivo `.env` do homelab NUNCA deve ser commitado.
O `.gitignore` deve incluir:
```
homelab/.env
homelab/cloudflared/*.json
homelab/cloudflared/cert.pem
```

## Exposição da Evolution API

### Acesso externo

- A porta `8080` da Evolution API faz bind apenas em `127.0.0.1` no container
- O acesso externo é feito exclusivamente via Cloudflare Tunnel
- O túnel cria uma conexão outbound criptografada para a Cloudflare
- Nenhuma porta do roteador precisa ser aberta

### Painel /manager

O painel administrativo em `/manager` está acessível se a API estiver exposta.
Medidas de proteção recomendadas:

1. **Cloudflare Access** (recomendado):
   - Configure uma política de acesso no Cloudflare Zero Trust
   - Exija autenticação por email ou GitHub para acessar `/manager`
   - O endpoint `/message/*` permanece acessível sem autenticação extra

2. **Desabilitar em produção:**
   ```env
   AUTHENTICATION_EXPOSE_IN_FETCH_INSTANCES=false
   ```
   Isso remove o painel, mantendo apenas a API REST.

3. **API key forte:**
   - Use uma chave aleatória longa (mínimo 32 caracteres)
   - Gere com: `openssl rand -hex 32`

## Variáveis de ambiente

### Validação

O módulo `config.py` valida todas as variáveis obrigatórias antes de iniciar:
- URLs válidas
- Recipients não vazios
- Valores numéricos dentro de intervalos esperados

### Proteção em logs

- API keys NUNCA aparecem em logs
- Corpos de resposta HTTP sao truncados (200 chars no scraper, 300 no sender)
- Dados binários (PDF, imagem) nunca são logados integralmente
- Destinatários são exibidos parcialmente em logs (últimos dígitos ocultos)

## Dependências

Bibliotecas utilizadas e suas justificativas de segurança:

| Biblioteca | Uso | Avaliação de segurança |
|------------|-----|----------------------|
| `requests` | HTTP client | Biblioteca mais popular do Python, mantida ativamente |
| `beautifulsoup4` | Parsing HTML | Consolidada, usada em milhões de projetos |
| `pdfplumber` | Conversao PDF → PNG | Mantida ativamente, baseada em `pdfminer.six` |

### Estratégia de atualização

- Dependências declaradas com range de versão compatível (ex: `>=2.31,<3.0`)
- GitHub Actions sempre instala a versão mais recente dentro do range
- Recomenda-se revisar e atualizar manualmente a cada 3-6 meses

## Resiliência

### Princípio "fail secure"

O sistema é conservador — prefere falhar a enviar dados errados:

- Se o PDF nao for encontrado → erro, sem envio
- Se a conversao PDF → PNG falhar → erro, sem envio
- Erro de autenticacao na API → aborta imediatamente, sem retry

### Retry controlado

- Apenas para falhas de rede (timeout, connection error)
- Máximo de 3 tentativas por destinatário
- Backoff linear: 2s, 4s, 6s
- Erros de autenticação NUNCA fazem retry

### Timeouts

- Todas as requisições HTTP têm timeout configurável (padrão: 30s)
- O workflow do GitHub Actions tem timeout total de 10 minutos
