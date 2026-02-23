"""Canonicalization utilities for structured equivalence checking.

Provides AST-like canonicalization of tool calls and arguments,
tolerant to ordering and formatting differences.
"""

from __future__ import annotations

import json
import re
from typing import Any


def canonicalize_string(s: str) -> str:
    """Normalize a string for comparison.

    - Strip whitespace
    - Lowercase
    - Normalize multiple spaces to single
    - Remove trailing punctuation
    """
    s = s.strip().lower()
    s = re.sub(r"\s+", " ", s)
    s = s.rstrip(".,;:!?")
    return s


def canonicalize_number(v: Any) -> float | None:
    """Try to parse a value as a number."""
    if isinstance(v, (int, float)):
        return float(v)
    if isinstance(v, str):
        # Remove commas, currency symbols, whitespace
        cleaned = re.sub(r"[,$\s%]", "", v.strip())
        try:
            return float(cleaned)
        except ValueError:
            return None
    return None


def canonicalize_args(args: dict[str, Any]) -> dict[str, Any]:
    """Canonicalize tool call arguments for comparison.

    - Sort dict keys
    - Normalize strings
    - Normalize numbers
    - Recursively canonicalize nested structures
    """
    result = {}
    for key in sorted(args.keys()):
        value = args[key]
        result[key] = _canonicalize_value(value)
    return result


def _canonicalize_value(value: Any) -> Any:
    """Canonicalize a single value."""
    if isinstance(value, str):
        # Try as number first
        num = canonicalize_number(value)
        if num is not None and re.match(r"^[\d.,\-+eE\s$%]+$", value.strip()):
            return num
        return canonicalize_string(value)
    elif isinstance(value, (int, float)):
        return float(value)
    elif isinstance(value, dict):
        return canonicalize_args(value)
    elif isinstance(value, list):
        return [_canonicalize_value(v) for v in value]
    elif isinstance(value, bool):
        return value
    elif value is None:
        return None
    return str(value)


def canonicalize_tool_call(tool_name: str, args: dict[str, Any]) -> dict[str, Any]:
    """Canonicalize a complete tool call for comparison."""
    return {
        "tool_name": tool_name.strip().lower(),
        "arguments": canonicalize_args(args),
    }


def deep_equals(a: Any, b: Any, numeric_tolerance: float = 1e-6) -> bool:
    """Deep equality check with numeric tolerance and canonicalization.

    Handles dicts, lists, strings, numbers with tolerance.
    """
    if isinstance(a, dict) and isinstance(b, dict):
        if set(a.keys()) != set(b.keys()):
            return False
        return all(deep_equals(a[k], b[k], numeric_tolerance) for k in a)
    elif isinstance(a, list) and isinstance(b, list):
        if len(a) != len(b):
            return False
        return all(deep_equals(ai, bi, numeric_tolerance) for ai, bi in zip(a, b))
    elif isinstance(a, (int, float)) and isinstance(b, (int, float)):
        return abs(float(a) - float(b)) <= numeric_tolerance
    elif isinstance(a, str) and isinstance(b, str):
        return canonicalize_string(a) == canonicalize_string(b)
    else:
        return a == b


def set_equals_unordered(a: list[Any], b: list[Any]) -> bool:
    """Check if two lists contain the same elements regardless of order.

    Uses JSON serialization for hashability.
    """
    def to_hashable(v: Any) -> str:
        return json.dumps(v, sort_keys=True, default=str)

    set_a = {to_hashable(x) for x in a}
    set_b = {to_hashable(x) for x in b}
    return set_a == set_b


def edit_distance(seq_a: list[str], seq_b: list[str]) -> int:
    """Compute Levenshtein edit distance between two sequences."""
    m, n = len(seq_a), len(seq_b)
    dp = [[0] * (n + 1) for _ in range(m + 1)]

    for i in range(m + 1):
        dp[i][0] = i
    for j in range(n + 1):
        dp[0][j] = j

    for i in range(1, m + 1):
        for j in range(1, n + 1):
            if seq_a[i - 1] == seq_b[j - 1]:
                dp[i][j] = dp[i - 1][j - 1]
            else:
                dp[i][j] = 1 + min(dp[i - 1][j], dp[i][j - 1], dp[i - 1][j - 1])

    return dp[m][n]
