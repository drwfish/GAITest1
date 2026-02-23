"""Slow but accurate tool - returns precise results with higher latency/cost.

This tool and its counterpart (fast_approx) are used to test cost-aware
tool selection: some tasks benefit from accuracy, others from speed.
Both operate on a "data analysis" domain.
"""

from __future__ import annotations

import math
from typing import Any

from app.tools.base import BaseTool, ToolResult

# Simulated dataset for analysis
_DATASET = {
    "revenue_q1": 1_234_567.89,
    "revenue_q2": 1_456_789.12,
    "revenue_q3": 1_345_678.45,
    "revenue_q4": 1_567_890.67,
    "users_active": 45_678,
    "users_total": 123_456,
    "conversion_rate": 0.0342,
    "churn_rate": 0.0156,
    "avg_order_value": 67.89,
    "median_order_value": 52.34,
    "std_dev_order": 34.56,
    "customer_satisfaction": 4.23,
    "nps_score": 42,
    "support_tickets_monthly": 1_234,
    "resolution_time_hours": 4.5,
    "uptime_percentage": 99.97,
    "error_rate": 0.0003,
    "p50_latency_ms": 45,
    "p95_latency_ms": 230,
    "p99_latency_ms": 890,
}


class SlowAccurateTool(BaseTool):
    name = "slow_accurate"
    description = (
        "Perform precise data analysis on business metrics. "
        "Returns exact values with full precision. Higher cost but guaranteed accuracy. "
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
                "description": "Operation: get a single metric, compare two metrics, or get trend across quarters",
                "default": "get",
            },
            "metric2": {
                "type": "string",
                "description": "Second metric for compare operation",
            },
        },
        "required": ["metric"],
    }
    cost = 10.0
    latency_ms = 2000.0

    def execute(self, args: dict[str, Any], context: dict[str, Any] | None = None) -> ToolResult:
        metric = args.get("metric", "")
        operation = args.get("operation", "get")

        if operation == "get":
            value = _DATASET.get(metric)
            if value is None:
                return ToolResult(
                    success=False,
                    error=f"Metric '{metric}' not found. Available: {', '.join(sorted(_DATASET.keys()))}",
                )
            return ToolResult(
                success=True,
                output=f"{metric} = {value}",
                structured_output={"metric": metric, "value": value, "precision": "exact"},
            )

        elif operation == "compare":
            metric2 = args.get("metric2", "")
            val1 = _DATASET.get(metric)
            val2 = _DATASET.get(metric2)
            if val1 is None or val2 is None:
                missing = metric if val1 is None else metric2
                return ToolResult(success=False, error=f"Metric '{missing}' not found.")
            diff = val1 - val2
            pct = (diff / val2 * 100) if val2 != 0 else float("inf")
            return ToolResult(
                success=True,
                output=f"{metric} ({val1}) vs {metric2} ({val2}): difference = {diff}, {pct:.2f}%",
                structured_output={
                    "metric1": {"name": metric, "value": val1},
                    "metric2": {"name": metric2, "value": val2},
                    "difference": diff,
                    "percentage_diff": round(pct, 2),
                    "precision": "exact",
                },
            )

        elif operation == "trend":
            quarters = ["revenue_q1", "revenue_q2", "revenue_q3", "revenue_q4"]
            if metric.startswith("revenue"):
                values = {q: _DATASET[q] for q in quarters}
                vals = list(values.values())
                growth = (vals[-1] - vals[0]) / vals[0] * 100
                return ToolResult(
                    success=True,
                    output=f"Revenue trend: {values}. YoY growth: {growth:.2f}%",
                    structured_output={
                        "trend": values,
                        "growth_percentage": round(growth, 2),
                        "precision": "exact",
                    },
                )
            return ToolResult(success=False, error="Trend operation only available for revenue metrics.")

        return ToolResult(success=False, error=f"Unknown operation: {operation}")


def get_tools() -> list[BaseTool]:
    return [SlowAccurateTool()]
