"""HTTP agent adapter - calls an external agent endpoint.

This adapter is how we integrate with real agents for evaluation.
It sends the agent protocol request via HTTP POST and parses the response.
"""

from __future__ import annotations

from typing import Any

import httpx
import structlog

from app.agents.base import BaseAgent
from app.schemas.agent_protocol import AgentRequest, AgentResponse

logger = structlog.get_logger()


class HTTPAgentAdapter(BaseAgent):
    """Agent adapter that calls an external HTTP endpoint.

    The endpoint must accept POST requests with AgentRequest JSON body
    and return AgentResponse JSON.
    """

    agent_id: str = "http"

    def __init__(
        self,
        url: str,
        timeout_seconds: float = 60.0,
        headers: dict[str, str] | None = None,
        agent_id: str | None = None,
    ) -> None:
        self._url = url
        self._timeout = timeout_seconds
        self._headers = headers or {}
        if agent_id:
            self.agent_id = agent_id

    def respond(self, request: AgentRequest) -> AgentResponse:
        """Send request to external agent and parse response."""
        payload = request.model_dump(mode="json")

        try:
            with httpx.Client(timeout=self._timeout) as client:
                response = client.post(
                    self._url,
                    json=payload,
                    headers={
                        "Content-Type": "application/json",
                        **self._headers,
                    },
                )
                response.raise_for_status()
                data = response.json()
                return AgentResponse(**data)

        except httpx.TimeoutException:
            logger.error("http_agent_timeout", url=self._url, timeout=self._timeout)
            return AgentResponse(
                final_answer="Error: Agent endpoint timed out.",
                reasoning=f"HTTP request to {self._url} timed out after {self._timeout}s.",
            )
        except httpx.HTTPStatusError as e:
            logger.error("http_agent_error", url=self._url, status=e.response.status_code)
            return AgentResponse(
                final_answer=f"Error: Agent endpoint returned status {e.response.status_code}.",
                reasoning=f"HTTP error from {self._url}: {e.response.status_code}",
            )
        except Exception as e:
            logger.error("http_agent_exception", url=self._url, error=str(e))
            return AgentResponse(
                final_answer=f"Error: Failed to communicate with agent endpoint.",
                reasoning=f"Exception communicating with {self._url}: {str(e)}",
            )


def create_http_agent(config: dict[str, Any]) -> HTTPAgentAdapter:
    """Factory to create an HTTPAgentAdapter from configuration dict."""
    return HTTPAgentAdapter(
        url=config["url"],
        timeout_seconds=config.get("timeout_seconds", 60.0),
        headers=config.get("headers"),
        agent_id=config.get("agent_id", "http"),
    )
