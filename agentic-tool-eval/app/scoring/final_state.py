"""Final State Scorer.

Compares the environment's final state against the expected final state.
Uses deep equality with canonicalization.
"""

from __future__ import annotations

from app.core.tracing import Trace
from app.schemas.results_schema import MetricResult, Severity
from app.schemas.task_schema import Task
from app.scoring.base import BaseScorer
from app.scoring.canonicalize import canonicalize_args, deep_equals


class FinalStateScorer(BaseScorer):
    metric_name = "final_state"

    def score(self, task: Task, trace: Trace) -> MetricResult:
        expected = task.expected_final_state
        if expected is None:
            return MetricResult(
                metric_name=self.metric_name,
                value=1.0,
                evidence={"reason": "No expected final state defined."},
                severity=Severity.INFO,
            )

        actual = trace.final_state
        if actual is None:
            return MetricResult(
                metric_name=self.metric_name,
                value=0.0,
                evidence={"reason": "No final state recorded in trace."},
                severity=Severity.FAIL,
            )

        # Canonicalize both for comparison
        canon_expected = canonicalize_args(expected)
        canon_actual = canonicalize_args(actual)

        if deep_equals(canon_expected, canon_actual):
            return MetricResult(
                metric_name=self.metric_name,
                value=1.0,
                evidence={"match": True},
                severity=Severity.INFO,
            )

        # Partial scoring: check how many expected keys match
        if isinstance(expected, dict) and isinstance(actual, dict):
            total_keys = len(expected)
            matching_keys = 0
            mismatches = []

            for key in expected:
                if key in actual:
                    exp_val = canon_expected.get(key)
                    act_val = canon_actual.get(key)
                    if deep_equals(exp_val, act_val):
                        matching_keys += 1
                    else:
                        mismatches.append({
                            "key": key,
                            "expected": exp_val,
                            "actual": act_val,
                        })
                else:
                    mismatches.append({
                        "key": key,
                        "expected": expected[key],
                        "actual": None,
                        "reason": "key missing",
                    })

            value = matching_keys / total_keys if total_keys > 0 else 0.0
            severity = Severity.INFO if value >= 0.8 else (Severity.WARN if value >= 0.5 else Severity.FAIL)

            return MetricResult(
                metric_name=self.metric_name,
                value=round(value, 4),
                evidence={
                    "matching_keys": matching_keys,
                    "total_keys": total_keys,
                    "mismatches": mismatches[:10],  # Cap to avoid huge evidence
                },
                severity=severity,
            )

        return MetricResult(
            metric_name=self.metric_name,
            value=0.0,
            evidence={
                "expected_type": type(expected).__name__,
                "actual_type": type(actual).__name__,
                "reason": "State types do not match or deep comparison failed.",
            },
            severity=Severity.FAIL,
        )
