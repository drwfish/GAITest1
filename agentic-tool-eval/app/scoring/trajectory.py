"""Trajectory Similarity Scorer.

Compares the sequence of tool calls against the expected trajectory.
- When order_matters: uses edit distance for order-aware comparison
- When !order_matters: uses set-based comparison (order-insensitive)
"""

from __future__ import annotations

from app.core.tracing import Trace
from app.schemas.results_schema import MetricResult, Severity
from app.schemas.task_schema import Task
from app.scoring.base import BaseScorer
from app.scoring.canonicalize import edit_distance


class TrajectorySimilarityScorer(BaseScorer):
    metric_name = "trajectory_similarity"

    def score(self, task: Task, trace: Trace) -> MetricResult:
        if not task.expected_steps:
            return MetricResult(
                metric_name=self.metric_name,
                value=1.0,
                evidence={"reason": "No expected steps defined."},
                severity=Severity.INFO,
            )

        # Build expected tool sequence (use first allowed tool as canonical)
        expected_seq = [step.allowed_tools[0] if step.allowed_tools else "none" for step in task.expected_steps]
        actual_seq = [tc.get("tool_name", "none") for tc in trace.tool_calls]

        if task.order_matters:
            value, evidence = _score_ordered(expected_seq, actual_seq)
        else:
            value, evidence = _score_unordered(expected_seq, actual_seq)

        severity = Severity.INFO if value >= 0.8 else (Severity.WARN if value >= 0.5 else Severity.FAIL)

        return MetricResult(
            metric_name=self.metric_name,
            value=value,
            evidence=evidence,
            severity=severity,
        )


def _score_ordered(expected: list[str], actual: list[str]) -> tuple[float, dict]:
    """Order-aware trajectory scoring using edit distance."""
    if not expected and not actual:
        return 1.0, {"method": "ordered", "edit_distance": 0}

    max_len = max(len(expected), len(actual))
    if max_len == 0:
        return 1.0, {"method": "ordered", "edit_distance": 0}

    dist = edit_distance(expected, actual)
    # Normalize: 0 distance = 1.0 score, max_len distance = 0.0
    value = max(0.0, 1.0 - dist / max_len)

    return value, {
        "method": "ordered",
        "edit_distance": dist,
        "max_possible_distance": max_len,
        "expected_sequence": expected,
        "actual_sequence": actual,
    }


def _score_unordered(expected: list[str], actual: list[str]) -> tuple[float, dict]:
    """Order-insensitive trajectory scoring using set overlap."""
    expected_set = set(expected)
    actual_set = set(actual)

    if not expected_set:
        return 1.0, {"method": "unordered", "reason": "no expected tools"}

    # Use multiset-aware comparison
    from collections import Counter
    expected_counts = Counter(expected)
    actual_counts = Counter(actual)

    # Count matches (min of expected and actual for each tool)
    matches = sum(min(expected_counts[t], actual_counts[t]) for t in expected_counts)
    total = sum(expected_counts.values())

    # Also penalize extra tools
    extra = sum(max(0, actual_counts[t] - expected_counts.get(t, 0)) for t in actual_counts)

    value = matches / total if total > 0 else 1.0
    # Small penalty for extra calls
    if extra > 0 and value > 0:
        value = max(0.0, value - extra * 0.1)

    return value, {
        "method": "unordered",
        "matches": matches,
        "total_expected": total,
        "extra_calls": extra,
        "expected_set": sorted(expected_set),
        "actual_set": sorted(actual_set),
    }
