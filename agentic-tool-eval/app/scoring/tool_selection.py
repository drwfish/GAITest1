"""Tool Selection Accuracy Scorer.

Measures whether the agent selected the correct tool(s) at each step.
For each expected step, checks if the actual tool call uses one of the
allowed tools.
"""

from __future__ import annotations

from app.core.tracing import Trace
from app.schemas.results_schema import MetricResult, Severity
from app.schemas.task_schema import Task
from app.scoring.base import BaseScorer


class ToolSelectionAccuracyScorer(BaseScorer):
    metric_name = "tool_selection_accuracy"

    def score(self, task: Task, trace: Trace) -> MetricResult:
        if not task.expected_steps:
            return MetricResult(
                metric_name=self.metric_name,
                value=1.0,
                evidence={"reason": "No expected steps defined; trivially correct."},
                severity=Severity.INFO,
            )

        expected = task.expected_steps
        actual = trace.tool_calls

        correct = 0
        total = len(expected)
        details = []

        for i, step in enumerate(expected):
            if i < len(actual):
                actual_tool = actual[i].get("tool_name", "")
                is_correct = actual_tool in step.allowed_tools
                correct += int(is_correct)
                details.append({
                    "step": i,
                    "expected_tools": step.allowed_tools,
                    "actual_tool": actual_tool,
                    "correct": is_correct,
                })
            else:
                details.append({
                    "step": i,
                    "expected_tools": step.allowed_tools,
                    "actual_tool": None,
                    "correct": False,
                })

        # Also penalize extra tool calls beyond expected
        extra_calls = max(0, len(actual) - len(expected))

        value = correct / total if total > 0 else 1.0
        severity = Severity.INFO if value >= 0.8 else (Severity.WARN if value >= 0.5 else Severity.FAIL)

        return MetricResult(
            metric_name=self.metric_name,
            value=value,
            evidence={
                "correct": correct,
                "total_expected": total,
                "total_actual": len(actual),
                "extra_calls": extra_calls,
                "details": details,
            },
            severity=severity,
        )
