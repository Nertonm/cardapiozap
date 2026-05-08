"""Configuracao centralizada. Tudo por variaveis de ambiente."""

import os
from dataclasses import dataclass, field


class ConfigError(Exception):
    """Falta variavel obrigatoria ou valor invalido."""


def _safe_int(value: str, default: int) -> int:
    try:
        return int(value)
    except (ValueError, TypeError):
        return default


def _safe_float(value: str, default: float) -> float:
    try:
        return float(value)
    except (ValueError, TypeError):
        return default


@dataclass(frozen=True)
class Config:
    cardapio_url: str
    evolution_api_url: str = ""
    evolution_api_key: str = ""
    evolution_instance: str = ""
    recipients: list[str] = field(default_factory=list)
    log_level: str = "INFO"
    request_timeout: int = 30
    sender_max_retries: int = 3
    sender_retry_delay: float = 2.0

    def validate(self) -> None:
        if not self.cardapio_url:
            raise ConfigError("CARDAPIO_URL e obrigatoria")
        if not self.evolution_api_url:
            raise ConfigError("EVOLUTION_API_URL e obrigatoria")
        if not self.evolution_api_key:
            raise ConfigError("EVOLUTION_API_KEY e obrigatoria")
        if not self.evolution_instance:
            raise ConfigError("EVOLUTION_INSTANCE e obrigatoria")
        if not self.recipients:
            raise ConfigError("RECIPIENTS e obrigatoria")
        if self.request_timeout <= 0:
            raise ConfigError("REQUEST_TIMEOUT deve ser positivo")
        if self.sender_max_retries < 0:
            raise ConfigError("SENDER_MAX_RETRIES nao pode ser negativo")


def _parse_recipients(raw: str) -> list[str]:
    if not raw or not raw.strip():
        return []
    return [r.strip() for r in raw.split(",") if r.strip()]


def load_config() -> Config:
    cfg = Config(
        cardapio_url=os.environ.get(
            "CARDAPIO_URL",
            "https://www.ufca.edu.br/assuntos-estudantis/refeitorio-universitario/cardapios/",
        ),
        evolution_api_url=os.environ.get("EVOLUTION_API_URL", ""),
        evolution_api_key=os.environ.get("EVOLUTION_API_KEY", ""),
        evolution_instance=os.environ.get("EVOLUTION_INSTANCE", ""),
        recipients=_parse_recipients(os.environ.get("RECIPIENTS", "")),
        log_level=os.environ.get("LOG_LEVEL", "INFO"),
        request_timeout=_safe_int(os.environ.get("REQUEST_TIMEOUT", "30"), 30),
        sender_max_retries=_safe_int(os.environ.get("SENDER_MAX_RETRIES", "3"), 3),
        sender_retry_delay=_safe_float(os.environ.get("SENDER_RETRY_DELAY", "2.0"), 2.0),
    )
    cfg.validate()
    return cfg
