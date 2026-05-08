"""Scraper da pagina de cardapios da UFCA.

Acessa a pagina, localiza o link do PDF mais recente, resolve redirects
e baixa os bytes. Nao depende do nome do arquivo PDF.
"""

import logging
import re
import urllib.parse
from datetime import date
from typing import Optional

import requests
from bs4 import BeautifulSoup, Tag

from bot.config import Config

logger = logging.getLogger(__name__)

USER_AGENT = "Mozilla/5.0 (compatible; CardapioBot/1.0)"
DOCUMENTOS_HOSTS = {"documentos.ufca.edu.br"}


class ScraperError(Exception):
    """Erro durante o scraping."""


class NoMenuFoundError(ScraperError):
    """Nenhum link de cardapio encontrado."""


class PDFDownloadError(ScraperError):
    """Falha ao baixar o PDF."""


def _truncate(text: str, max_len: int = 200) -> str:
    if len(text) <= max_len:
        return text
    return text[:max_len] + f"... [truncado, total={len(text)} chars]"


def _safe_log_body(body: bytes, max_len: int = 200) -> str:
    try:
        text = body.decode("utf-8", errors="replace")
    except Exception:
        return f"<binary, {len(body)} bytes>"
    return _truncate(text, max_len)


def _extract_date(text: str) -> Optional[date]:
    dates: list[date] = []
    for pattern in [r"(\d{2})/(\d{2})/(\d{4})", r"(\d{2})-(\d{2})-(\d{4})"]:
        for m in re.finditer(pattern, text):
            try:
                d, mo, y = int(m.group(1)), int(m.group(2)), int(m.group(3))
                dates.append(date(y, mo, d))
            except ValueError:
                continue
        if dates:
            break
    return max(dates) if dates else None


def _is_documento_link(url: str) -> bool:
    parsed = urllib.parse.urlparse(url)
    return parsed.hostname in DOCUMENTOS_HOSTS and "post_type=doc" in (parsed.query or "")


def _extract_document_id(url: str) -> Optional[str]:
    parsed = urllib.parse.urlparse(url)
    qs = urllib.parse.parse_qs(parsed.query)
    return qs.get("p", [None])[0]


def _safe_int(value: str) -> int:
    try:
        return int(value)
    except (ValueError, TypeError):
        return 0


class Scraper:
    def __init__(self, config: Config):
        self._config = config
        self._session = requests.Session()
        self._session.headers.update({"User-Agent": USER_AGENT})

    def _get(self, url: str) -> requests.Response:
        resp = None
        try:
            resp = self._session.get(url, timeout=self._config.request_timeout)
            resp.raise_for_status()
            return resp
        except requests.Timeout as e:
            raise ScraperError(f"Timeout: {url}") from e
        except requests.ConnectionError as e:
            raise ScraperError(f"Conexao: {url}") from e
        except requests.HTTPError as e:
            status = resp.status_code if resp is not None else "?"
            body = _safe_log_body(resp.content) if resp is not None else "<sem resposta>"
            raise ScraperError(f"HTTP {status} {url}: {body}") from e

    def _resolve(self, url: str) -> str:
        current = url
        for _ in range(5):
            resp = self._session.head(
                current, allow_redirects=False, timeout=self._config.request_timeout
            )
            if resp.status_code in (301, 302, 303, 307, 308):
                location = resp.headers.get("Location", "")
                if not location:
                    raise ScraperError(f"Redirect sem Location em {current}")
                current = urllib.parse.urljoin(current, location)
                continue

            if resp.status_code != 200:
                raise ScraperError(f"Status {resp.status_code} em {current}")

            content_type = resp.headers.get("Content-Type", "")
            if "pdf" in content_type.lower() or "octet-stream" in content_type.lower():
                return current

            try:
                get_resp = self._session.get(current, timeout=self._config.request_timeout)
            except requests.RequestException as e:
                raise ScraperError(f"Falha ao verificar {current}: {e}") from e

            body = get_resp.content
            if body[:5] == b"%PDF-":
                return current

            soup = BeautifulSoup(body, "html.parser")
            for a in soup.find_all("a", href=True):
                href = str(a["href"])
                if href.lower().endswith(".pdf"):
                    return urllib.parse.urljoin(current, href)

            if b"%PDF-" in body[:1024]:
                return current
            return current

        raise ScraperError(f"Muitos redirects: {url}")

    def _find_candidates(self, html: str, source_url: str) -> list[dict]:
        soup = BeautifulSoup(html, "html.parser")
        candidates: list[dict] = []
        seen: set[str] = set()

        for a in soup.find_all("a", href=True):
            href = str(a.get("href", ""))
            if not href or href.startswith("#"):
                continue

            absolute = urllib.parse.urljoin(source_url, href)

            if _is_documento_link(absolute) or (
                any(h in absolute for h in DOCUMENTOS_HOSTS)
                and absolute.lower().endswith(".pdf")
            ):
                if absolute in seen:
                    continue
                seen.add(absolute)

                text = a.get_text(strip=True)
                parent_text = ""
                parent = a.parent
                for _ in range(3):
                    if parent:
                        parent_text += " " + (
                            parent.get_text(strip=True) if isinstance(parent, Tag) else ""
                        )
                        parent = parent.parent

                combined = f"{text} {parent_text}"
                candidates.append(
                    {
                        "url": absolute,
                        "text": text,
                        "date": _extract_date(combined),
                        "doc_id": _extract_document_id(absolute),
                    }
                )

            elif absolute.lower().endswith(".pdf"):
                if absolute in seen:
                    continue
                seen.add(absolute)

                text = a.get_text(strip=True)
                parent_text = a.parent.get_text(strip=True) if a.parent else ""
                combined = f"{text} {parent_text}"
                candidates.append(
                    {
                        "url": absolute,
                        "text": text,
                        "date": _extract_date(combined),
                        "doc_id": None,
                    }
                )

        return candidates

    def _choose(self, candidates: list[dict]) -> dict:
        if not candidates:
            raise NoMenuFoundError(
                "Nenhum link de cardapio encontrado. "
                "A UFCA pode nao ter publicado o cardapio desta semana."
            )

        dated = [c for c in candidates if c["date"] is not None]
        if dated:
            dated.sort(key=lambda c: c["date"], reverse=True)
            return dated[0]

        with_ids = [c for c in candidates if c["doc_id"] is not None]
        if with_ids:
            with_ids.sort(key=lambda c: _safe_int(c["doc_id"]), reverse=True)
            return with_ids[0]

        return candidates[0]

    def fetch_pdf(self) -> tuple[bytes, str]:
        source = self._config.cardapio_url
        logger.info("Acessando %s", source)

        resp = self._get(source)
        html = resp.text
        logger.info("Pagina fonte: %d bytes", len(html))

        candidates = self._find_candidates(html, source)
        logger.info("Candidatos encontrados: %d", len(candidates))
        for i, c in enumerate(candidates):
            logger.debug(
                "  [%d] doc_id=%s date=%s text=%s",
                i + 1, c["doc_id"], c["date"], _truncate(c["text"], 80),
            )

        chosen = self._choose(candidates)
        logger.info(
            "Escolhido: doc_id=%s date=%s url=%s",
            chosen["doc_id"], chosen["date"], _truncate(chosen["url"], 120),
        )

        final_url = self._resolve(chosen["url"])
        logger.info("URL final: %s", _truncate(final_url, 200))

        try:
            pdf_resp = self._session.get(final_url, timeout=self._config.request_timeout)
            pdf_resp.raise_for_status()
        except Exception as e:
            raise PDFDownloadError(f"Falha ao baixar PDF: {e}") from e

        pdf_bytes = pdf_resp.content
        if not pdf_bytes.startswith(b"%PDF-"):
            raise PDFDownloadError(
                f"Conteudo nao e PDF. Primeiros bytes: {pdf_bytes[:50]!r}"
            )

        logger.info("PDF baixado: %d bytes", len(pdf_bytes))
        return pdf_bytes, final_url
