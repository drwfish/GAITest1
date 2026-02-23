"""SQLite query tool - queries a packaged SQLite database.

The database is seeded with test tables for evaluation tasks.
Only SELECT queries are allowed (read-only).
"""

from __future__ import annotations

import re
import sqlite3
from pathlib import Path
from typing import Any

from app.tools.base import BaseTool, ToolResult

DEFAULT_DB_PATH = str(Path(__file__).parent.parent.parent / "resources" / "db" / "eval.db")


class SqliteQueryTool(BaseTool):
    name = "sqlite_query"
    description = (
        "Execute a read-only SQL query against a SQLite database. "
        "Only SELECT statements are allowed. "
        "Available tables: employees (id, name, department, salary, hire_date), "
        "products (id, name, category, price, stock), "
        "orders (id, customer_name, product_id, quantity, order_date, total)."
    )
    parameters_schema = {
        "type": "object",
        "properties": {
            "query": {
                "type": "string",
                "description": "SQL SELECT query to execute",
            },
        },
        "required": ["query"],
    }
    cost = 2.0
    latency_ms = 150.0

    def __init__(self, db_path: str | None = None) -> None:
        self._db_path = db_path or DEFAULT_DB_PATH

    def execute(self, args: dict[str, Any], context: dict[str, Any] | None = None) -> ToolResult:
        query = args.get("query", "").strip()

        # Security: only allow SELECT
        if not re.match(r"^\s*SELECT\b", query, re.IGNORECASE):
            return ToolResult(
                success=False,
                error="Only SELECT queries are allowed.",
            )

        # Block dangerous patterns
        dangerous = re.search(
            r"\b(INSERT|UPDATE|DELETE|DROP|CREATE|ALTER|ATTACH|DETACH|PRAGMA)\b",
            query,
            re.IGNORECASE,
        )
        if dangerous:
            return ToolResult(
                success=False,
                error=f"Disallowed SQL keyword: {dangerous.group()}",
            )

        try:
            conn = sqlite3.connect(self._db_path)
            conn.row_factory = sqlite3.Row
            cursor = conn.cursor()
            cursor.execute(query)
            rows = cursor.fetchall()
            conn.close()

            if not rows:
                return ToolResult(
                    success=True,
                    output="Query returned 0 rows.",
                    structured_output={"columns": [], "rows": [], "row_count": 0},
                )

            columns = list(rows[0].keys())
            data = [dict(row) for row in rows]

            # Format as text table
            lines = [" | ".join(columns)]
            lines.append("-" * len(lines[0]))
            for row in data[:50]:  # Cap display at 50 rows
                lines.append(" | ".join(str(row.get(c, "")) for c in columns))
            if len(data) > 50:
                lines.append(f"... ({len(data)} total rows)")

            return ToolResult(
                success=True,
                output="\n".join(lines),
                structured_output={"columns": columns, "rows": data, "row_count": len(data)},
            )

        except sqlite3.Error as e:
            return ToolResult(success=False, error=f"SQL error: {str(e)}")


def get_tools() -> list[BaseTool]:
    return [SqliteQueryTool()]
