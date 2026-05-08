"""Conversao de PDF para imagem PNG via pdfplumber."""

import io
import logging

import pdfplumber

logger = logging.getLogger(__name__)

RESOLUTION = 150


class ConversionError(Exception):
    """Falha na conversao PDF -> PNG."""


def pdf_to_png(pdf_bytes: bytes, resolution: int = RESOLUTION) -> bytes:
    try:
        pdf_file = io.BytesIO(pdf_bytes)
        pdf = pdfplumber.open(pdf_file)
    except Exception as e:
        raise ConversionError(f"Falha ao abrir PDF: {e}") from e

    if len(pdf.pages) == 0:
        raise ConversionError("PDF sem paginas")

    try:
        page = pdf.pages[0]
        page_image = page.to_image(resolution=resolution)
        pil_image = page_image.original

        output = io.BytesIO()
        pil_image.save(output, format="PNG", optimize=True)
        png_bytes = output.getvalue()

        logger.info(
            "PDF convertido: %dx%d px, %d bytes",
            pil_image.width,
            pil_image.height,
            len(png_bytes),
        )
        return png_bytes
    except Exception as e:
        raise ConversionError(f"Falha ao renderizar pagina: {e}") from e
    finally:
        pdf.close()
