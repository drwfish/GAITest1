"""Time tool - returns a deterministic "current time" from configuration.

For reproducible evaluations, the time is not taken from the system clock
but from a configured value (default: 2025-01-15T10:30:00Z).
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from app.tools.base import BaseTool, ToolResult

# Default deterministic time for reproducible evaluations
DEFAULT_TIME = "2025-01-15T10:30:00Z"


class TimeTool(BaseTool):
    name = "time"
    description = (
        "Get the current date and time. "
        "Can return time in various formats: iso, unix, human-readable."
    )
    parameters_schema = {
        "type": "object",
        "properties": {
            "format": {
                "type": "string",
                "enum": ["iso", "unix", "human", "date_only", "time_only"],
                "description": "Output format (default: iso)",
                "default": "iso",
            },
            "timezone": {
                "type": "string",
                "description": "Timezone offset like '+05:30' or 'UTC' (default: UTC)",
                "default": "UTC",
            },
        },
        "required": [],
    }
    cost = 0.1
    latency_ms = 10.0

    def __init__(self, fixed_time: str | None = None) -> None:
        self._fixed_time_str = fixed_time or DEFAULT_TIME

    def _get_time(self) -> datetime:
        return datetime.fromisoformat(self._fixed_time_str.replace("Z", "+00:00"))

    def execute(self, args: dict[str, Any], context: dict[str, Any] | None = None) -> ToolResult:
        fmt = args.get("format", "iso")
        dt = self._get_time()

        if fmt == "iso":
            output = dt.isoformat()
        elif fmt == "unix":
            output = str(int(dt.timestamp()))
        elif fmt == "human":
            output = dt.strftime("%A, %B %d, %Y at %I:%M %p UTC")
        elif fmt == "date_only":
            output = dt.strftime("%Y-%m-%d")
        elif fmt == "time_only":
            output = dt.strftime("%H:%M:%S")
        else:
            output = dt.isoformat()

        return ToolResult(
            success=True,
            output=output,
            structured_output={
                "iso": dt.isoformat(),
                "unix": int(dt.timestamp()),
                "date": dt.strftime("%Y-%m-%d"),
                "time": dt.strftime("%H:%M:%S"),
            },
        )


def get_tools() -> list[BaseTool]:
    return [TimeTool()]
