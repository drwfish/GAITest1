"""Calculator tool - evaluates arithmetic expressions safely.

Supports basic arithmetic (+, -, *, /, **, %, //), parentheses,
and common math functions (sqrt, abs, round, min, max).
Does NOT use eval() for safety; uses a restricted AST-based evaluator.
"""

from __future__ import annotations

import ast
import math
import operator
from typing import Any

from app.tools.base import BaseTool, ToolResult

# Safe operators and functions
SAFE_OPERATORS = {
    ast.Add: operator.add,
    ast.Sub: operator.sub,
    ast.Mult: operator.mul,
    ast.Div: operator.truediv,
    ast.FloorDiv: operator.floordiv,
    ast.Mod: operator.mod,
    ast.Pow: operator.pow,
    ast.USub: operator.neg,
    ast.UAdd: operator.pos,
}

SAFE_FUNCTIONS = {
    "sqrt": math.sqrt,
    "abs": abs,
    "round": round,
    "min": min,
    "max": max,
    "ceil": math.ceil,
    "floor": math.floor,
    "log": math.log,
    "log10": math.log10,
    "sin": math.sin,
    "cos": math.cos,
    "tan": math.tan,
    "pi": math.pi,
    "e": math.e,
}


def _safe_eval_node(node: ast.AST) -> float:
    """Recursively evaluate an AST node with only safe operations."""
    if isinstance(node, ast.Expression):
        return _safe_eval_node(node.body)
    elif isinstance(node, ast.Constant):
        if isinstance(node.value, (int, float)):
            return float(node.value)
        raise ValueError(f"Unsupported constant type: {type(node.value)}")
    elif isinstance(node, ast.BinOp):
        op_func = SAFE_OPERATORS.get(type(node.op))
        if op_func is None:
            raise ValueError(f"Unsupported operator: {type(node.op).__name__}")
        left = _safe_eval_node(node.left)
        right = _safe_eval_node(node.right)
        return float(op_func(left, right))
    elif isinstance(node, ast.UnaryOp):
        op_func = SAFE_OPERATORS.get(type(node.op))
        if op_func is None:
            raise ValueError(f"Unsupported unary operator: {type(node.op).__name__}")
        operand = _safe_eval_node(node.operand)
        return float(op_func(operand))
    elif isinstance(node, ast.Call):
        if isinstance(node.func, ast.Name):
            func_name = node.func.id
            func = SAFE_FUNCTIONS.get(func_name)
            if func is None:
                raise ValueError(f"Unsupported function: {func_name}")
            args = [_safe_eval_node(a) for a in node.args]
            if callable(func):
                return float(func(*args))
            return float(func)
        raise ValueError("Only named function calls are supported")
    elif isinstance(node, ast.Name):
        val = SAFE_FUNCTIONS.get(node.id)
        if val is not None and not callable(val):
            return float(val)
        raise ValueError(f"Unknown variable: {node.id}")
    else:
        raise ValueError(f"Unsupported AST node: {type(node).__name__}")


def safe_calculate(expression: str) -> float:
    """Safely evaluate a mathematical expression."""
    tree = ast.parse(expression, mode="eval")
    return _safe_eval_node(tree)


class CalculatorTool(BaseTool):
    name = "calculator"
    description = "Evaluate a mathematical expression. Supports +, -, *, /, **, %, //, sqrt, abs, round, min, max, ceil, floor, log, sin, cos, tan, pi, e."
    parameters_schema = {
        "type": "object",
        "properties": {
            "expression": {
                "type": "string",
                "description": "Mathematical expression to evaluate (e.g., '2 + 3 * 4', 'sqrt(16)')",
            }
        },
        "required": ["expression"],
    }
    cost = 0.1
    latency_ms = 10.0

    def execute(self, args: dict[str, Any], context: dict[str, Any] | None = None) -> ToolResult:
        expression = args.get("expression", "")
        try:
            result = safe_calculate(expression)
            # Format: remove trailing zeros for clean output
            if result == int(result):
                formatted = str(int(result))
            else:
                formatted = f"{result:.10g}"
            return ToolResult(
                success=True,
                output=formatted,
                structured_output={"result": result, "expression": expression},
            )
        except (ValueError, SyntaxError, ZeroDivisionError, OverflowError) as e:
            return ToolResult(success=False, error=f"Calculation error: {str(e)}")


def get_tools() -> list[BaseTool]:
    return [CalculatorTool()]
