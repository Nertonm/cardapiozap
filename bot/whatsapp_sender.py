"""Envio de mensagens via Evolution API."""

import base64
import logging
import time
from typing import Optional

import requests

from bot.config import Config

logger = logging.getLogger(__name__)

MAX_CAPTION = 1024


class SenderError(Exception):
    """Erro durante o envio."""


class AuthError(SenderError):
    """Erro de autenticacao (sem retry)."""


class NetworkError(SenderError):
    """Erro de rede (com retry)."""


class PayloadError(SenderError):
    """Erro no payload ou destinatario invalido (sem retry)."""


def _url(config: Config) -> str:
    base = config.evolution_api_url.rstrip("/")
    return f"{base}/message/sendMedia/{config.evolution_instance}"


def _headers(config: Config) -> dict[str, str]:
    return {
        "apikey": config.evolution_api_key,
        "Content-Type": "application/json",
    }


def _payload(recipient: str, image_b64: str, caption: str) -> dict:
    return {
        "number": recipient,
        "mediatype": "image",
        "mimetype": "image/png",
        "caption": caption[:MAX_CAPTION],
        "media": image_b64,
        "fileName": "cardapio_ru_ufca.png",
    }


def send_to_recipient(
    config: Config,
    image_bytes: bytes,
    caption: str,
    recipient: str,
) -> bool:
    url = _url(config)
    headers = _headers(config)
    image_b64 = base64.b64encode(image_bytes).decode("ascii")
    payload = _payload(recipient, image_b64, caption)

    for attempt in range(1, config.sender_max_retries + 1):
        try:
            resp = requests.post(
                url, json=payload, headers=headers, timeout=config.request_timeout
            )

            if resp.status_code in (401, 403):
                raise AuthError(
                    f"Erro de autenticacao (HTTP {resp.status_code}). "
                    f"Verifique EVOLUTION_API_KEY e EVOLUTION_INSTANCE."
                )

            if resp.status_code == 400:
                body = resp.text[:300]
                raise PayloadError(
                    f"Payload invalido para {recipient}: {body}"
                )

            if resp.status_code == 404:
                raise PayloadError(
                    f"Instancia '{config.evolution_instance}' nao encontrada."
                )

            if resp.status_code >= 500:
                raise NetworkError(
                    f"Erro do servidor (HTTP {resp.status_code})"
                )

            resp.raise_for_status()
            return True

        except AuthError:
            raise
        except PayloadError:
            raise
        except requests.Timeout as e:
            last_error = NetworkError(f"Timeout: {e}")
        except requests.ConnectionError as e:
            last_error = NetworkError(f"Conexao: {e}")
        except NetworkError as e:
            last_error = e
        except requests.RequestException as e:
            last_error = NetworkError(f"Erro HTTP: {e}")

        if attempt < config.sender_max_retries:
            delay = config.sender_retry_delay * attempt
            logger.warning(
                "Tentativa %d/%d falhou para %s, retry em %.1fs",
                attempt, config.sender_max_retries,
                recipient[:10] + "***" if len(recipient) > 10 else recipient,
                delay,
            )
            time.sleep(delay)

    raise SenderError(
        f"Falha apos {config.sender_max_retries} tentativas para {recipient[:10]}***"
    ) from last_error


def send_to_all(
    config: Config,
    image_bytes: bytes,
    caption: str,
) -> dict[str, bool]:
    results: dict[str, bool] = {}
    total = len(config.recipients)
    logger.info("Enviando para %d destinatario(s)", total)

    for recipient in config.recipients:
        try:
            send_to_recipient(config, image_bytes, caption, recipient)
            results[recipient] = True
            logger.info("OK: %s", recipient[:10] + "***" if len(recipient) > 10 else recipient)
        except AuthError as e:
            logger.error("AUTH: %s", e)
            results[recipient] = False
            raise
        except PayloadError as e:
            logger.error("PAYLOAD: %s", str(e)[:200])
            results[recipient] = False
        except (SenderError, NetworkError) as e:
            logger.error("ERRO: %s", str(e)[:200])
            results[recipient] = False

    sucessos = sum(1 for v in results.values() if v)
    logger.info("Envio: %d/%d sucesso", sucessos, total)
    return results
