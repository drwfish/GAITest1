"""Agent I/O protocol schema.

Defines the strict contract between the evaluation harness and any agent.
Agents receive messages and available tool schemas, and must respond with
either a final answer or a list of tool calls.

An OpenAPI-compatible JSON schema is provided via get_agent_protocol_schema().
"""

from __future__ import annotations

from enum import Enum
from typing import Any

from pydantic import BaseModel, Field


class MessageRole(str, Enum):
    SYSTEM = "system"
    USER = "user"
    ASSISTANT = "assistant"
    TOOL = "tool"


class Message(BaseModel):
    """A single message in the conversation."""
    role: MessageRole
    content: str
    tool_call_id: str | None = None
    name: str | None = None  # Tool name for tool messages


class ToolSchema(BaseModel):
    """Schema describing an available tool, presented to the agent."""
    name: str
    description: str
    parameters: dict[str, Any] = Field(
        default_factory=dict,
        description="JSON Schema for the tool's arguments",
    )
    cost: float | None = None
    latency_hint: str | None = None  # "fast", "medium", "slow"


class ToolCall(BaseModel):
    """A tool call requested by the agent."""
    id: str = Field(default="", description="Unique ID for this tool call")
    tool_name: str
    arguments: dict[str, Any] = Field(default_factory=dict)


class AgentRequest(BaseModel):
    """Request sent to the agent.

    Contains the conversation history and available tools.
    The agent must respond with an AgentResponse.
    """
    messages: list[Message]
    tools: list[ToolSchema]
    environment_hints: dict[str, Any] = Field(
        default_factory=dict,
        description="Optional hints about the environment (e.g., current time, session id)",
    )
    max_tool_calls: int = 20
    turn_number: int = 0


class AgentResponse(BaseModel):
    """Response from the agent.

    Must contain either a final_answer OR tool_calls, not both.
    If tool_calls is non-empty, the harness will execute them and
    send the results back in the next turn.
    """
    final_answer: str | None = None
    tool_calls: list[ToolCall] = Field(default_factory=list)
    reasoning: str | None = Field(
        default=None,
        description="Optional chain-of-thought or reasoning (not scored, for debugging)",
    )

    def is_final(self) -> bool:
        return self.final_answer is not None and len(self.tool_calls) == 0


def get_agent_protocol_schema() -> dict[str, Any]:
    """Return an OpenAPI-compatible JSON schema for the agent protocol.

    This schema can be served via the API and used by agent implementers
    to validate their integration.
    """
    return {
        "openapi": "3.1.0",
        "info": {
            "title": "Agentic Tool Eval - Agent Protocol",
            "version": "1.0.0",
            "description": (
                "Protocol for agents under evaluation. "
                "The evaluator sends AgentRequest and expects AgentResponse."
            ),
        },
        "components": {
            "schemas": {
                "AgentRequest": AgentRequest.model_json_schema(),
                "AgentResponse": AgentResponse.model_json_schema(),
                "Message": Message.model_json_schema(),
                "ToolSchema": ToolSchema.model_json_schema(),
                "ToolCall": ToolCall.model_json_schema(),
            }
        },
    }
