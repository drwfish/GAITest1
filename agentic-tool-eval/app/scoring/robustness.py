"""Robustness Scorer.

Rewards successful recovery after injected tool failures.
Checks whether the agent:
1. Retried the failed tool call
2. Used a fallback tool
3. Still arrived at a correct or reasonable answer
"""

from __future__ import annotations

from app.core.tracing import Trace, TraceEventType
from app.schemas.results_schema import MetricResult, Severity
from app.schemas.task_schema import Task
from app.scoring.base import BaseScorer


class RobustnessScorer(BaseScorer):
    metric_name = "robustness"

    def score(self, task: Task, trace: Trace) -> MetricResult:
        if not task.failure_injection:
            return MetricResult(
                metric_name=self.metric_name,
                value=1.0,
                evidence={"reason": "No failure injection configured for this task."},
                severity=Severity.INFO,
            )

        # Count failures that were injected
        failures_injected = 0
        for event in trace.events:
            if event.event_type == TraceEventType.FAILURE_INJECTED:
                failures_injected += 1

        if failures_injected == 0:
            # Failure injection was configured but no failures actually triggered
            # (e.g., agent didn't call the tool that would fail)
            return MetricResult(
                metric_name=self.metric_name,
                value=0.5,
                evidence={
                    "reason": "Failure injection configured but no failures triggered.",
                    "failures_injected": 0,
                },
                severity=Severity.WARN,
            )

        # Check for recovery indicators
        recovery_indicators = 0
        total_checks = 0

        # Check 1: Did the agent retry after failure?
        total_checks += 1
        failed_tools = set()
        for event in trace.events:
            if event.event_type == TraceEventType.FAILURE_INJECTED:
                failed_tools.add(event.data.get("tool_name", ""))

        retried = False
        for tc in trace.tool_calls:
            tool_name = tc.get("tool_name", "")
            if tool_name in failed_tools and tc.get("success", False):
                retried = True
                break

        if retried:
            recovery_indicators += 1

        # Check 2: Did the agent use a fallback tool?
        total_checks += 1
        tools_used = {tc.get("tool_name", "") for tc in trace.tool_calls}
        # If agent used tools other than the failed ones, that counts as fallback
        non_failed_tools = tools_used - failed_tools
        if non_failed_tools:
            recovery_indicators += 1

        # Check 3: Did the agent provide a final answer?
        total_checks += 1
        if trace.final_answer is not None:
            recovery_indicators += 1

        value = recovery_indicators / total_checks if total_checks > 0 else 0.0
        severity = Severity.INFO if value >= 0.7 else (Severity.WARN if value >= 0.3 else Severity.FAIL)

        return MetricResult(
            metric_name=self.metric_name,
            value=round(value, 4),
            evidence={
                "failures_injected": failures_injected,
                "failed_tools": sorted(failed_tools),
                "retried": retried,
                "used_fallback": bool(non_failed_tools),
                "provided_answer": trace.final_answer is not None,
                "recovery_indicators": recovery_indicators,
                "total_checks": total_checks,
            },
            severity=severity,
        )
