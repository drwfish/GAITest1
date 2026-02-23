"""Base tool definition and ToolResult.

All tools inherit from BaseTool and implement execute().
ToolResult is the standard return type for tool execution.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Any

from pydantic import BaseModel, Field


class ToolResult(BaseModel):
    """Result of a tool execution."""
    success: bool = True
    output: str = ""
    structured_output: dict[str, Any] = Field(default_factory=dict)
    error: str | None = None


class BaseTool(ABC):
    """Base class for all tools in the evaluation framework.

    Attributes:
        name: Unique identifier for the tool.
        description: Human-readable description of what the tool does.
        parameters_schema: JSON Schema for the tool's arguments.
        cost: Numeric cost metadata (arbitrary units, for cost-aware eval).
        latency_ms: Expected latency in milliseconds (for simulation).
    """

    name: str = ""
    description: str = ""
    parameters_schema: dict[str, Any] = {}
    cost: float = 1.0
    latency_ms: float = 100.0

    @abstractmethod
    def execute(self, args: dict[str, Any], context: dict[str, Any] | None = None) -> ToolResult:
        """Execute the tool with given arguments.

        Args:
            args: Tool arguments matching parameters_schema.
            context: Optional execution context (environment state, etc.).

        Returns:
            ToolResult with output and/or error.
        """
        ...

    def get_schema(self) -> dict[str, Any]:
        """Return the tool's parameter schema for agent consumption."""
        return {
            "name": self.name,
            "description": self.description,
            "parameters": self.parameters_schema,
            "cost": self.cost,
            "latency_hint": (
                "fast" if self.latency_ms < 200
                else "medium" if self.latency_ms < 1000
                else "slow"
            ),
        }
