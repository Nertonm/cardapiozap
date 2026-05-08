"""Orquestrador do Bot de Cardapio UFCA.

Fluxo: scrape do PDF → conversao para PNG → envio via Evolution API.
"""

import logging
import sys
from datetime import date, datetime, timezone

from bot.config import ConfigError, load_config
from bot.logging_setup import setup_logging
from bot.pdf_converter import ConversionError, pdf_to_png
from bot.scraper import (
    NoMenuFoundError,
    PDFDownloadError,
    Scraper,
    ScraperError,
)
from bot.whatsapp_sender import AuthError, send_to_all

logger = logging.getLogger(__name__)

DIA_SEMANA = [
    "Segunda-feira",
    "Terça-feira",
    "Quarta-feira",
    "Quinta-feira",
    "Sexta-feira",
    "Sabado",
    "Domingo",
]


def _is_weekday(d: date) -> bool:
    return d.weekday() < 5


def main() -> int:
    try:
        config = load_config()
    except ConfigError as e:
        print(f"ERRO DE CONFIGURACAO: {e}", file=sys.stderr)
        return 1

    setup_logging(config.log_level)
    logger.info("Iniciando execucao — %s", datetime.now(timezone.utc).isoformat())

    hoje = date.today()

    if not _is_weekday(hoje):
        logger.info("%s nao e dia util, abortando sem erro", hoje.isoformat())
        return 0

    try:
        scraper = Scraper(config)
        pdf_bytes, _pdf_url = scraper.fetch_pdf()
    except NoMenuFoundError as e:
        logger.error("Cardapio nao encontrado: %s", e)
        logger.error("Verifique manualmente: %s", config.cardapio_url)
        return 1
    except PDFDownloadError as e:
        logger.error("Falha no download do PDF: %s", e)
        return 1
    except ScraperError as e:
        logger.error("Erro no scraping: %s", e)
        return 1

    try:
        image_bytes = pdf_to_png(pdf_bytes)
    except ConversionError as e:
        logger.error("Erro na conversao PDF → PNG: %s", e)
        return 1

    legenda = f"Cardapio do RU / {DIA_SEMANA[hoje.weekday()]}, {hoje.strftime('%d/%m/%Y')}"

    try:
        results = send_to_all(config, image_bytes, legenda)
    except AuthError as e:
        logger.error("Falha de autenticacao: %s", e)
        return 1

    sucessos = sum(1 for v in results.values() if v)
    total = len(results)

    if sucessos == 0:
        logger.error("Nenhum destinatario recebeu o cardapio (%d tentativas)", total)
        return 1

    if sucessos < total:
        logger.warning("Envio parcial: %d/%d destinatarios", sucessos, total)
        return 1

    logger.info("Envio completo: %d/%d destinatarios", sucessos, total)
    return 0


if __name__ == "__main__":
    sys.exit(main())
