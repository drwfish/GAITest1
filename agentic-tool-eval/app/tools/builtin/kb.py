"""Knowledge base tool - returns facts from a local key-value store.

Provides deterministic responses for known keys.
Used for tasks that test the agent's ability to look up specific facts.
"""

from __future__ import annotations

from typing import Any

from app.tools.base import BaseTool, ToolResult

# Built-in knowledge base entries
KNOWLEDGE_BASE: dict[str, str] = {
    "capital_of_france": "Paris",
    "capital_of_germany": "Berlin",
    "capital_of_japan": "Tokyo",
    "capital_of_brazil": "Brasilia",
    "capital_of_australia": "Canberra",
    "capital_of_canada": "Ottawa",
    "capital_of_india": "New Delhi",
    "capital_of_italy": "Rome",
    "capital_of_spain": "Madrid",
    "capital_of_mexico": "Mexico City",
    "speed_of_light": "299,792,458 meters per second",
    "boiling_point_water": "100 degrees Celsius at standard atmospheric pressure",
    "freezing_point_water": "0 degrees Celsius at standard atmospheric pressure",
    "earth_radius_km": "6,371 km",
    "moon_distance_km": "384,400 km on average",
    "population_world_2023": "Approximately 8 billion",
    "python_creator": "Guido van Rossum",
    "linux_creator": "Linus Torvalds",
    "http_status_200": "OK - The request was successful",
    "http_status_404": "Not Found - The requested resource was not found",
    "http_status_500": "Internal Server Error",
    "pi_value": "3.14159265358979323846",
    "euler_number": "2.71828182845904523536",
    "golden_ratio": "1.61803398874989484820",
    "speed_of_sound": "343 meters per second in air at 20 degrees Celsius",
    "largest_planet": "Jupiter",
    "smallest_planet": "Mercury",
    "closest_star": "Proxima Centauri (4.24 light-years away)",
    "chemical_symbol_gold": "Au",
    "chemical_symbol_silver": "Ag",
    "chemical_symbol_iron": "Fe",
    "water_formula": "H2O",
    "co2_formula": "CO2",
    "avogadro_number": "6.022 x 10^23",
    "planck_constant": "6.626 x 10^-34 J·s",
    "gravitational_constant": "6.674 x 10^-11 N·m²/kg²",
    "boltzmann_constant": "1.381 x 10^-23 J/K",
    "sql_join_types": "INNER JOIN, LEFT JOIN, RIGHT JOIN, FULL OUTER JOIN, CROSS JOIN",
    "rest_methods": "GET, POST, PUT, PATCH, DELETE, HEAD, OPTIONS",
    "osi_layers": "Physical, Data Link, Network, Transport, Session, Presentation, Application",
}


class KnowledgeBaseTool(BaseTool):
    name = "knowledge_base"
    description = (
        "Look up a fact from the knowledge base by key. "
        "Available keys include topics like capitals, science constants, "
        "programming facts, and more. Use list_keys to see available keys."
    )
    parameters_schema = {
        "type": "object",
        "properties": {
            "key": {
                "type": "string",
                "description": "The knowledge base key to look up (e.g., 'capital_of_france', 'speed_of_light')",
            },
            "action": {
                "type": "string",
                "enum": ["lookup", "list_keys"],
                "description": "Action to perform: 'lookup' a specific key or 'list_keys' to see available keys",
                "default": "lookup",
            },
        },
        "required": ["key"],
    }
    cost = 0.5
    latency_ms = 50.0

    def execute(self, args: dict[str, Any], context: dict[str, Any] | None = None) -> ToolResult:
        action = args.get("action", "lookup")

        if action == "list_keys":
            keys = sorted(KNOWLEDGE_BASE.keys())
            return ToolResult(
                success=True,
                output="\n".join(keys),
                structured_output={"keys": keys, "count": len(keys)},
            )

        key = args.get("key", "").strip().lower().replace(" ", "_")
        value = KNOWLEDGE_BASE.get(key)
        if value is None:
            # Try fuzzy match
            for k, v in KNOWLEDGE_BASE.items():
                if key in k or k in key:
                    return ToolResult(
                        success=True,
                        output=f"{k}: {v}",
                        structured_output={"key": k, "value": v, "fuzzy_match": True},
                    )
            return ToolResult(
                success=False,
                error=f"Key '{key}' not found in knowledge base. Use action='list_keys' to see available keys.",
            )

        return ToolResult(
            success=True,
            output=f"{key}: {value}",
            structured_output={"key": key, "value": value},
        )


def get_tools() -> list[BaseTool]:
    return [KnowledgeBaseTool()]
