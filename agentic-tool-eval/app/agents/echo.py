"""Echo agent - baseline test agent that echoes back the prompt.

This agent is used for sanity checks. It:
- Never calls any tools
- Returns the user prompt as the final answer
- Useful for testing the abstention scorer (should fail on tasks that require tools)
  and for testing the harness itself
"""

from __future__ import annotations

from app.agents.base import BaseAgent
from app.schemas.agent_protocol import AgentRequest, AgentResponse


class EchoAgent(BaseAgent):
    """Agent that echoes the user prompt without calling any tools."""

    agent_id: str = "echo"

    def respond(self, request: AgentRequest) -> AgentResponse:
        # Find the last user message
        last_user_msg = ""
        for msg in reversed(request.messages):
            if msg.role == "user":
                last_user_msg = msg.content
                break

        return AgentResponse(
            final_answer=last_user_msg,
            reasoning="Echo agent: returning user prompt as-is.",
        )
