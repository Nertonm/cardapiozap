"""Configuracao de logging."""

import logging
import sys
from datetime import datetime, timezone


def setup_logging(level: str = "INFO") -> None:
    numeric_level = getattr(logging, level.upper(), logging.INFO)

    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(_Formatter())
    handler.setLevel(numeric_level)

    root = logging.getLogger()
    root.setLevel(numeric_level)
    root.handlers.clear()
    root.addHandler(handler)

    logging.getLogger("urllib3").setLevel(logging.WARNING)
    logging.getLogger("pdfminer").setLevel(logging.WARNING)


class _Formatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        return f"{ts} [{record.levelname:<7}] {record.getMessage()}"
