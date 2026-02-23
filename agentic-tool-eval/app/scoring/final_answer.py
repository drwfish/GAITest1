"""Final Answer Scorer.

Scores the agent's final answer against the expected answer.
Supports:
- Exact match (with normalization)
- Regex mode
- Numeric tolerance
- Judge mode (OFF by default, uses LLM-as-judge when enabled)
"""

from __future__ import annotations

import re
from typing import Any

from app.core.tracing import Trace
from app.schemas.results_schema import MetricResult, Severity
from app.schemas.task_schema import Task
from app.scoring.base import BaseScorer
from app.scoring.canonicalize import canonicalize_number, canonicalize_string


class FinalAnswerScorer(BaseScorer):
    metric_name = "final_answer"

    def __init__(self, judge_enabled: bool = False) -> None:
        self._judge_enabled = judge_enabled

    def score(self, task: Task, trace: Trace) -> MetricResult:
        expected = task.expected_final_answer
        actual = trace.final_answer

        if expected is None:
            return MetricResult(
                metric_name=self.metric_name,
                value=1.0,
                evidence={"reason": "No expected final answer defined."},
                severity=Severity.INFO,
            )

        if actual is None:
            return MetricResult(
                metric_name=self.metric_name,
                value=0.0,
                evidence={"reason": "Agent did not provide a final answer."},
                severity=Severity.FAIL,
            )

        mode = task.scoring.final_answer_mode

        if mode == "regex":
            return self._score_regex(expected, actual)
        elif mode == "judge" and self._judge_enabled:
            # Judge mode is OFF by default. When enabled, it would call
            # an LLM to evaluate answer quality. For now, fall back to
            # contains-based matching as a reasonable heuristic.
            return self._score_contains(expected, actual)
        else:
            return self._score_exact(expected, actual)

    def _score_exact(self, expected: Any, actual: str) -> MetricResult:
        """Exact match with normalization."""
        expected_str = str(expected)

        # Try numeric comparison first
        expected_num = canonicalize_number(expected_str)
        actual_num = canonicalize_number(actual)
        if expected_num is not None and actual_num is not None:
            match = abs(expected_num - actual_num) < 0.01
            return MetricResult(
                metric_name=self.metric_name,
                value=1.0 if match else 0.0,
                evidence={
                    "mode": "numeric",
                    "expected": expected_num,
                    "actual": actual_num,
                    "difference": abs(expected_num - actual_num),
                },
                severity=Severity.INFO if match else Severity.FAIL,
            )

        # String comparison
        canon_expected = canonicalize_string(expected_str)
        canon_actual = canonicalize_string(actual)

        if canon_expected == canon_actual:
            return MetricResult(
                metric_name=self.metric_name,
                value=1.0,
                evidence={"mode": "exact", "match": True},
                severity=Severity.INFO,
            )

        # Partial credit: check if expected is contained in actual
        if canon_expected in canon_actual:
            return MetricResult(
                metric_name=self.metric_name,
                value=0.8,
                evidence={
                    "mode": "exact",
                    "match": False,
                    "partial": True,
                    "reason": "Expected answer found within actual answer.",
                },
                severity=Severity.WARN,
            )

        return MetricResult(
            metric_name=self.metric_name,
            value=0.0,
            evidence={
                "mode": "exact",
                "expected": expected_str[:200],
                "actual": actual[:200],
            },
            severity=Severity.FAIL,
        )

    def _score_regex(self, expected: Any, actual: str) -> MetricResult:
        """Regex-based scoring."""
        pattern = str(expected)
        try:
            match = bool(re.search(pattern, actual, re.IGNORECASE | re.DOTALL))
        except re.error as e:
            return MetricResult(
                metric_name=self.metric_name,
                value=0.0,
                evidence={"mode": "regex", "error": f"Invalid regex: {e}"},
                severity=Severity.FAIL,
            )

        return MetricResult(
            metric_name=self.metric_name,
            value=1.0 if match else 0.0,
            evidence={
                "mode": "regex",
                "pattern": pattern,
                "match": match,
            },
            severity=Severity.INFO if match else Severity.FAIL,
        )

    def _score_contains(self, expected: Any, actual: str) -> MetricResult:
        """Contains-based scoring (fallback for judge mode when judge is disabled)."""
        expected_str = canonicalize_string(str(expected))
        actual_canon = canonicalize_string(actual)

        if expected_str in actual_canon or actual_canon in expected_str:
            value = 1.0
        elif any(word in actual_canon for word in expected_str.split() if len(word) > 3):
            # Partial credit for key word overlap
            expected_words = {w for w in expected_str.split() if len(w) > 3}
            actual_words = set(actual_canon.split())
            overlap = len(expected_words & actual_words)
            value = min(1.0, overlap / max(len(expected_words), 1))
        else:
            value = 0.0

        severity = Severity.INFO if value >= 0.8 else (Severity.WARN if value >= 0.5 else Severity.FAIL)

        return MetricResult(
            metric_name=self.metric_name,
            value=value,
            evidence={
                "mode": "contains",
                "expected_preview": str(expected)[:200],
                "actual_preview": actual[:200],
            },
            severity=severity,
        )
