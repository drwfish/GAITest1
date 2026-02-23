"""HTTP result sink - POSTs results to an ingestion endpoint.

Enabled by environment variables:
- HTTP_INGEST_URL
- HTTP_INGEST_AUTH_HEADER + HTTP_INGEST_AUTH_VALUE
  OR HTTP_INGEST_BEARER_TOKEN
"""

from __future__ import annotations

import os

import httpx
import structlog

from app.schemas.results_schema import EvalRunResult
from app.sinks.base import ResultSink

logger = structlog.get_logger()


class HttpSink(ResultSink):
    """POST results to an HTTP endpoint."""

    def __init__(
        self,
        url: str | None = None,
        auth_header: str | None = None,
        auth_value: str | None = None,
        bearer_token: str | None = None,
        timeout_seconds: float = 30.0,
    ) -> None:
        self._url = url or os.environ.get("HTTP_INGEST_URL", "")
        self._auth_header = auth_header or os.environ.get("HTTP_INGEST_AUTH_HEADER", "")
        self._auth_value = auth_value or os.environ.get("HTTP_INGEST_AUTH_VALUE", "")
        self._bearer_token = bearer_token or os.environ.get("HTTP_INGEST_BEARER_TOKEN", "")
        self._timeout = timeout_seconds

    def write(self, result: EvalRunResult) -> None:
        if not self._url:
            logger.warning("http_sink_no_url", msg="HTTP_INGEST_URL not configured, skipping HTTP sink")
            return

        headers: dict[str, str] = {"Content-Type": "application/json"}

        if self._bearer_token:
            headers["Authorization"] = f"Bearer {self._bearer_token}"
        elif self._auth_header and self._auth_value:
            headers[self._auth_header] = self._auth_value

        data = result.model_dump(mode="json")

        try:
            with httpx.Client(timeout=self._timeout) as client:
                response = client.post(self._url, json=data, headers=headers)
                response.raise_for_status()
                logger.info("http_sink_written", url=self._url, status=response.status_code)
        except httpx.HTTPStatusError as e:
            logger.error("http_sink_error", url=self._url, status=e.response.status_code)
            raise
        except Exception as e:
            logger.error("http_sink_exception", url=self._url, error=str(e))
            raise
