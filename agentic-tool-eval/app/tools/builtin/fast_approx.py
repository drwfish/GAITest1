"""Fast but approximate tool - returns quick estimates with lower precision.

Counterpart to slow_accurate. Same domain (data analysis) but returns
rounded/estimated values at lower cost and latency. Used to test whether
agents can make cost-accuracy tradeoffs appropriately.
"""

from __future__ import annotations

import math
from typing import Any

from app.tools.base import BaseTool, ToolResult

# Same base data as slow_accurate, but values are rounded/approximated
_APPROX_DATASET = {
    "revenue_q1": 1_235_000,
    "revenue_q2": 1_457_000,
    "revenue_q3": 1_346_000,
    "revenue_q4": 1_568_000,
    "users_active": 46_000,
    "users_total": 123_000,
    "conversion_rate": 0.034,
    "churn_rate": 0.016,
    "avg_order_value": 68,
    "median_order_value": 52,
    "std_dev_order": 35,
    "customer_satisfaction": 4.2,
    "nps_score": 42,
    "support_tickets_monthly": 1_200,
    "resolution_time_hours": 4.5,
    "uptime_percentage": 99.97,
    "error_rate": 0.0003,
    "p50_latency_ms": 45,
    "p95_latency_ms": 230,
    "p99_latency_ms": 890,
}


class FastApproxTool(BaseTool):
    name = "fast_approx"
    description = (
        "Quickly retrieve approximate business metrics. "
        "Returns rounded estimates - faster and cheaper but less precise. "
        "Available metrics: revenue_q1-q4, users_active, users_total, conversion_rate, "
        "churn_rate, avg_order_value, median_order_value, std_dev_order, "
        "customer_satisfaction, nps_score, support_tickets_monthly, resolution_time_hours, "
        "uptime_percentage, error_rate, p50/p95/p99_latency_ms."
    )
    parameters_schema = {
        "type": "object",
        "properties": {
            "metric": {
                "type": "string",
                "description": "Name of the metric to retrieve",
            },
            "operation": {
                "type": "string",
                "enum": ["get", "compare", "trend"],
                "description": "Operation: get a single metric, compare two, or get trend",
                "default": "get",
            },
            "metric2": {
                "type": "string",
                "description": "Second metric for compare operation",
            },
        },
        "required": ["metric"],
    }
    cost = 1.0
    latency_ms = 100.0

    def execute(self, args: dict[str, Any], context: dict[str, Any] | None = None) -> ToolResult:
        metric = args.get("metric", "")
        operation = args.get("operation", "get")

        if operation == "get":
            value = _APPROX_DATASET.get(metric)
            if value is None:
                return ToolResult(
                    success=False,
                    error=f"Metric '{metric}' not found. Available: {', '.join(sorted(_APPROX_DATASET.keys()))}",
                )
            return ToolResult(
                success=True,
                output=f"{metric} ≈ {value}",
                structured_output={"metric": metric, "value": value, "precision": "approximate"},
            )

        elif operation == "compare":
            metric2 = args.get("metric2", "")
            val1 = _APPROX_DATASET.get(metric)
            val2 = _APPROX_DATASET.get(metric2)
            if val1 is None or val2 is None:
                missing = metric if val1 is None else metric2
                return ToolResult(success=False, error=f"Metric '{missing}' not found.")
            diff = val1 - val2
            pct = (diff / val2 * 100) if val2 != 0 else float("inf")
            return ToolResult(
                success=True,
                output=f"{metric} (~{val1}) vs {metric2} (~{val2}): diff ≈ {diff}, ~{pct:.0f}%",
                structured_output={
                    "metric1": {"name": metric, "value": val1},
                    "metric2": {"name": metric2, "value": val2},
                    "difference": diff,
                    "percentage_diff": round(pct, 0),
                    "precision": "approximate",
                },
            )

        elif operation == "trend":
            quarters = ["revenue_q1", "revenue_q2", "revenue_q3", "revenue_q4"]
            if metric.startswith("revenue"):
                values = {q: _APPROX_DATASET[q] for q in quarters}
                vals = list(values.values())
                growth = (vals[-1] - vals[0]) / vals[0] * 100
                return ToolResult(
                    success=True,
                    output=f"Revenue trend (approx): {values}. YoY growth ≈ {growth:.0f}%",
                    structured_output={
                        "trend": values,
                        "growth_percentage": round(growth, 0),
                        "precision": "approximate",
                    },
                )
            return ToolResult(success=False, error="Trend operation only available for revenue metrics.")

        return ToolResult(success=False, error=f"Unknown operation: {operation}")


def get_tools() -> list[BaseTool]:
    return [FastApproxTool()]
