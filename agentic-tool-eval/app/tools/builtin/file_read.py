"""File read tool - reads from a mounted read-only directory.

For security, only reads from a configured base directory.
Used for tasks that require the agent to extract information from files.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any

from app.tools.base import BaseTool, ToolResult

# Default base directory for file reads (within the container/resources)
DEFAULT_BASE_DIR = str(Path(__file__).parent.parent.parent / "resources")


class FileReadTool(BaseTool):
    name = "file_read"
    description = (
        "Read the contents of a file from the data directory. "
        "Provide a relative path within the data directory. "
        "Only text files can be read."
    )
    parameters_schema = {
        "type": "object",
        "properties": {
            "path": {
                "type": "string",
                "description": "Relative path to the file within the data directory",
            },
            "max_lines": {
                "type": "integer",
                "description": "Maximum number of lines to read (default: 100)",
                "default": 100,
                "minimum": 1,
                "maximum": 1000,
            },
        },
        "required": ["path"],
    }
    cost = 0.5
    latency_ms = 50.0

    def __init__(self, base_dir: str | None = None) -> None:
        self._base_dir = Path(base_dir or DEFAULT_BASE_DIR)

    def execute(self, args: dict[str, Any], context: dict[str, Any] | None = None) -> ToolResult:
        rel_path = args.get("path", "")
        max_lines = args.get("max_lines", 100)

        # Resolve and validate path
        try:
            full_path = (self._base_dir / rel_path).resolve()
            # Security: ensure path is within base directory
            if not str(full_path).startswith(str(self._base_dir.resolve())):
                return ToolResult(
                    success=False,
                    error="Access denied: path is outside the allowed directory.",
                )
        except (ValueError, OSError):
            return ToolResult(success=False, error="Invalid file path.")

        if not full_path.is_file():
            return ToolResult(
                success=False,
                error=f"File not found: {rel_path}",
            )

        try:
            with open(full_path, "r", errors="replace") as f:
                lines = []
                for i, line in enumerate(f):
                    if i >= max_lines:
                        lines.append(f"... (truncated at {max_lines} lines)")
                        break
                    lines.append(line.rstrip("\n"))

            content = "\n".join(lines)
            return ToolResult(
                success=True,
                output=content,
                structured_output={"path": rel_path, "line_count": len(lines)},
            )
        except Exception as e:
            return ToolResult(success=False, error=f"Error reading file: {str(e)}")


def get_tools() -> list[BaseTool]:
    return [FileReadTool()]
