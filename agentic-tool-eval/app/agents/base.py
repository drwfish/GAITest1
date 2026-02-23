"""Base agent interface.

All agents must implement the BaseAgent interface.
The evaluator calls respond() with an AgentRequest and expects an AgentResponse.
"""

from __future__ import annotations

from abc import ABC, abstractmethod

from app.schemas.agent_protocol import AgentRequest, AgentResponse


class BaseAgent(ABC):
    """Base class for all agent adapters."""

    agent_id: str = "base"

    @abstractmethod
    def respond(self, request: AgentRequest) -> AgentResponse:
        """Process a request and return a response.

        Args:
            request: The evaluation request with messages and available tools.

        Returns:
            AgentResponse with either final_answer or tool_calls.
        """
        ...
