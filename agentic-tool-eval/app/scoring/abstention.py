"""Abstention Scorer.

Penalizes tool use when abstain_expected is True.
When a task has abstain_expected=True, the agent should NOT call any tools.
Any tool call is scored as a violation.
"""

from __future__ import annotations

from app.core.tracing import Trace
from app.schemas.results_schema import MetricResult, Severity
from app.schemas.task_schema import Task
from app.scoring.base import BaseScorer


class AbstentionScorer(BaseScorer):
    metric_name = "abstention"

    def score(self, task: Task, trace: Trace) -> MetricResult:
        if not task.abstain_expected:
            # Abstention not relevant for this task
            return MetricResult(
                metric_name=self.metric_name,
                value=1.0,
                evidence={"reason": "Abstention not expected for this task."},
                severity=Severity.INFO,
            )

        tool_calls_made = len(trace.tool_calls)

        if tool_calls_made == 0:
            # Agent correctly abstained
            return MetricResult(
                metric_name=self.metric_name,
                value=1.0,
                evidence={
                    "abstained": True,
                    "tool_calls_made": 0,
                    "reason": "Agent correctly abstained from calling any tools.",
                },
                severity=Severity.INFO,
            )

        # Agent incorrectly called tools
        # Score decreases with each unwanted tool call
        value = 0.0
        tools_called = [tc.get("tool_name", "unknown") for tc in trace.tool_calls]

        return MetricResult(
            metric_name=self.metric_name,
            value=value,
            evidence={
                "abstained": False,
                "tool_calls_made": tool_calls_made,
                "tools_called": tools_called,
                "reason": f"Agent should have abstained but made {tool_calls_made} tool call(s).",
            },
            severity=Severity.FAIL,
        )
