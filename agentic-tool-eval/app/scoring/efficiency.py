"""Step Efficiency Scorer.

Measures the ratio of expected steps to actual steps taken.
Penalizes both too many steps (inefficiency) and too few steps (incomplete).
"""

from __future__ import annotations

from app.core.tracing import Trace
from app.schemas.results_schema import MetricResult, Severity
from app.schemas.task_schema import Task
from app.scoring.base import BaseScorer


class StepEfficiencyScorer(BaseScorer):
    metric_name = "step_efficiency"

    def score(self, task: Task, trace: Trace) -> MetricResult:
        expected_count = len(task.expected_steps)
        actual_count = len(trace.tool_calls)

        if expected_count == 0:
            # No steps expected
            if actual_count == 0:
                value = 1.0
                reason = "No steps expected, none taken."
            else:
                # Agent made unnecessary calls
                value = max(0.0, 1.0 - actual_count * 0.2)
                reason = f"No steps expected but {actual_count} calls made."
        elif actual_count == 0:
            value = 0.0
            reason = f"Expected {expected_count} steps but no tool calls made."
        else:
            # Score based on ratio. Perfect = 1.0 (exact match).
            # Penalty grows as ratio diverges from 1.0.
            ratio = actual_count / expected_count
            if ratio <= 1.0:
                # Under-stepping: linear penalty
                value = ratio
            else:
                # Over-stepping: penalize excess, but less harshly
                # ratio=2.0 -> 0.5, ratio=3.0 -> 0.33
                value = 1.0 / ratio
            reason = f"Expected {expected_count} steps, took {actual_count} (ratio: {ratio:.2f})."

        severity = Severity.INFO if value >= 0.8 else (Severity.WARN if value >= 0.5 else Severity.FAIL)

        return MetricResult(
            metric_name=self.metric_name,
            value=round(value, 4),
            evidence={
                "expected_steps": expected_count,
                "actual_steps": actual_count,
                "ratio": actual_count / expected_count if expected_count > 0 else None,
                "reason": reason,
            },
            severity=severity,
        )
