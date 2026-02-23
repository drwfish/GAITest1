"""Heuristic agent - baseline agent that selects tools by keyword matching.

This agent provides a deterministic, non-trivial baseline for testing.
It uses simple heuristics to:
1. Match keywords in the prompt to available tool names/descriptions
2. Extract likely arguments from the prompt text
3. Makes one tool call per turn, then returns the result as the final answer

This is intentionally imperfect - it will make some right choices and some
wrong ones, providing a useful baseline for scorer calibration.
"""

from __future__ import annotations

import re
import uuid
from typing import Any

from app.agents.base import BaseAgent
from app.schemas.agent_protocol import (
    AgentRequest,
    AgentResponse,
    MessageRole,
    ToolCall,
)


# Keyword-to-tool mapping heuristics
TOOL_KEYWORDS: dict[str, list[str]] = {
    "calculator": [
        "calculate", "compute", "math", "arithmetic", "sum", "add", "subtract",
        "multiply", "divide", "plus", "minus", "times", "product", "quotient",
        "percentage", "percent", "square root", "sqrt", "power", "factorial",
        "average", "mean", "total",
    ],
    "search": [
        "search", "find", "look up", "lookup", "query", "information about",
        "tell me about", "what is", "who is", "where is", "when did",
        "articles", "results for", "documents about",
    ],
    "sqlite_query": [
        "sql", "database", "query", "table", "select", "employees", "products",
        "orders", "salary", "department", "price", "stock", "customer",
        "hire_date", "order_date",
    ],
    "knowledge_base": [
        "capital of", "speed of", "boiling point", "freezing point",
        "population", "creator of", "http status", "formula", "constant",
        "planet", "chemical symbol", "fact about", "knowledge",
    ],
    "file_read": [
        "read file", "file contents", "open file", "load file",
        "read the file", "contents of", "file at",
    ],
    "time": [
        "time", "date", "current time", "what time", "today", "now",
        "current date", "day of the week", "timestamp",
    ],
    "slow_accurate": [
        "exact", "precise", "accurate", "detailed analysis",
        "exact revenue", "precise metric", "accurate data",
    ],
    "fast_approx": [
        "approximate", "quick", "estimate", "rough", "ballpark",
        "roughly", "about how much", "quick look",
    ],
}


def _score_tool_match(prompt: str, tool_name: str, tool_description: str) -> float:
    """Score how well a tool matches a prompt based on keywords."""
    prompt_lower = prompt.lower()
    score = 0.0

    # Check keyword matches
    keywords = TOOL_KEYWORDS.get(tool_name, [])
    for kw in keywords:
        if kw in prompt_lower:
            score += 1.0

    # Check if tool name appears in prompt
    if tool_name.replace("_", " ") in prompt_lower:
        score += 2.0

    # Check description overlap
    desc_words = set(tool_description.lower().split())
    prompt_words = set(prompt_lower.split())
    overlap = len(desc_words & prompt_words)
    score += overlap * 0.1

    return score


def _extract_calculator_args(prompt: str) -> dict[str, Any]:
    """Try to extract a math expression from the prompt."""
    # Look for patterns like "calculate 2 + 3" or "what is 15 * 7"
    patterns = [
        r"(?:calculate|compute|eval(?:uate)?|what is|how much is)\s+(.+?)(?:\?|$|\.)",
        r"(\d+[\s]*[+\-*/^%]+[\s]*\d+(?:[\s]*[+\-*/^%]+[\s]*\d+)*)",
    ]
    for pattern in patterns:
        m = re.search(pattern, prompt, re.IGNORECASE)
        if m:
            expr = m.group(1).strip().rstrip("?.!")
            # Clean up common words
            expr = re.sub(r"\b(is|equals?|the result of)\b", "", expr, flags=re.IGNORECASE).strip()
            return {"expression": expr}
    return {"expression": prompt}


def _extract_search_args(prompt: str) -> dict[str, Any]:
    """Try to extract a search query from the prompt."""
    # Remove common prefixes
    query = re.sub(
        r"^(?:search for|find|look up|search|tell me about|what is|who is)\s+",
        "",
        prompt,
        flags=re.IGNORECASE,
    ).strip().rstrip("?.!")
    return {"query": query, "top_k": 3}


def _extract_sql_args(prompt: str) -> dict[str, Any]:
    """Try to extract or construct a SQL query from the prompt."""
    # Check if there's a literal SQL query
    sql_match = re.search(r"(SELECT\s.+?)(?:$|\.|\?)", prompt, re.IGNORECASE | re.DOTALL)
    if sql_match:
        return {"query": sql_match.group(1).strip()}

    # Simple heuristic SQL generation
    prompt_lower = prompt.lower()
    if "employee" in prompt_lower or "salary" in prompt_lower:
        if "highest" in prompt_lower or "max" in prompt_lower:
            return {"query": "SELECT name, salary FROM employees ORDER BY salary DESC LIMIT 5"}
        if "department" in prompt_lower:
            return {"query": "SELECT department, COUNT(*) as count, AVG(salary) as avg_salary FROM employees GROUP BY department"}
        return {"query": "SELECT * FROM employees LIMIT 10"}
    if "product" in prompt_lower or "price" in prompt_lower:
        if "expensive" in prompt_lower or "max" in prompt_lower:
            return {"query": "SELECT name, price FROM products ORDER BY price DESC LIMIT 5"}
        return {"query": "SELECT * FROM products LIMIT 10"}
    if "order" in prompt_lower:
        return {"query": "SELECT * FROM orders LIMIT 10"}

    return {"query": "SELECT name FROM sqlite_master WHERE type='table'"}


def _extract_kb_args(prompt: str) -> dict[str, Any]:
    """Try to extract a knowledge base key from the prompt."""
    prompt_lower = prompt.lower()
    # Try to match known patterns
    capital_match = re.search(r"capital of (\w+)", prompt_lower)
    if capital_match:
        return {"key": f"capital_of_{capital_match.group(1)}"}

    # Generic key extraction
    key = re.sub(r"[^a-z0-9_]+", "_", prompt_lower).strip("_")
    # Take a reasonable subset
    if len(key) > 40:
        key = key[:40]
    return {"key": key}


def _extract_time_args(prompt: str) -> dict[str, Any]:
    """Extract time format from prompt."""
    prompt_lower = prompt.lower()
    if "unix" in prompt_lower or "timestamp" in prompt_lower:
        return {"format": "unix"}
    if "date" in prompt_lower and "time" not in prompt_lower:
        return {"format": "date_only"}
    return {"format": "human"}


def _extract_metric_args(prompt: str) -> dict[str, Any]:
    """Extract metric name for data analysis tools."""
    prompt_lower = prompt.lower()
    # Match known metric names
    known_metrics = [
        "revenue_q1", "revenue_q2", "revenue_q3", "revenue_q4",
        "users_active", "users_total", "conversion_rate", "churn_rate",
        "avg_order_value", "median_order_value", "nps_score",
        "customer_satisfaction", "uptime_percentage", "error_rate",
        "p50_latency_ms", "p95_latency_ms", "p99_latency_ms",
    ]
    for metric in known_metrics:
        if metric.replace("_", " ") in prompt_lower or metric in prompt_lower:
            return {"metric": metric}

    # Fallback: try to construct a metric name
    if "revenue" in prompt_lower:
        return {"metric": "revenue_q1"}
    if "user" in prompt_lower:
        return {"metric": "users_active"}
    if "latency" in prompt_lower:
        return {"metric": "p95_latency_ms"}
    return {"metric": "revenue_q1"}


ARG_EXTRACTORS: dict[str, Any] = {
    "calculator": _extract_calculator_args,
    "search": _extract_search_args,
    "sqlite_query": _extract_sql_args,
    "knowledge_base": _extract_kb_args,
    "time": _extract_time_args,
    "slow_accurate": _extract_metric_args,
    "fast_approx": _extract_metric_args,
    "file_read": lambda p: {"path": "corpora/search_corpus.json"},
}


class HeuristicAgent(BaseAgent):
    """Agent that selects tools based on keyword matching heuristics."""

    agent_id: str = "heuristic"

    def respond(self, request: AgentRequest) -> AgentResponse:
        # If we already have a tool result, return it as final answer
        for msg in request.messages:
            if msg.role == MessageRole.TOOL:
                return AgentResponse(
                    final_answer=msg.content,
                    reasoning="Heuristic agent: returning tool result as final answer.",
                )

        # Find the user prompt
        user_prompt = ""
        for msg in reversed(request.messages):
            if msg.role == MessageRole.USER:
                user_prompt = msg.content
                break

        if not user_prompt or not request.tools:
            return AgentResponse(
                final_answer="I don't have enough information to help.",
                reasoning="No prompt or no tools available.",
            )

        # Score each tool
        tool_scores: list[tuple[float, str, str]] = []
        for tool in request.tools:
            score = _score_tool_match(user_prompt, tool.name, tool.description)
            tool_scores.append((score, tool.name, tool.description))

        tool_scores.sort(key=lambda x: x[0], reverse=True)

        # If best score is 0, abstain (no tool matches)
        if not tool_scores or tool_scores[0][0] <= 0:
            return AgentResponse(
                final_answer="I cannot determine which tool to use for this request.",
                reasoning="No tool matched the prompt keywords.",
            )

        best_tool_name = tool_scores[0][1]

        # Don't call the disallowed tool
        if best_tool_name == "disallowed":
            # Pick next best
            if len(tool_scores) > 1 and tool_scores[1][0] > 0:
                best_tool_name = tool_scores[1][1]
            else:
                return AgentResponse(
                    final_answer="I cannot safely help with this request.",
                    reasoning="Best matching tool is disallowed; declining to use it.",
                )

        # Extract arguments
        extractor = ARG_EXTRACTORS.get(best_tool_name, lambda p: {})
        arguments = extractor(user_prompt)

        return AgentResponse(
            tool_calls=[
                ToolCall(
                    id=str(uuid.uuid4()),
                    tool_name=best_tool_name,
                    arguments=arguments,
                )
            ],
            reasoning=f"Heuristic agent: selected '{best_tool_name}' based on keyword matching.",
        )
