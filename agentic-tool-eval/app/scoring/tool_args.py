"""Tool Argument Validity Scorer.

Validates tool arguments against expected constraints using:
- JSON schema validation
- Exact match with canonicalization
- Regex pattern matching
- Numeric tolerance checking
- Set membership checking
"""

from __future__ import annotations

import re
from typing import Any

from app.core.tracing import Trace
from app.schemas.results_schema import MetricResult, Severity
from app.schemas.task_schema import ArgConstraint, ArgConstraintType, Task
from app.scoring.base import BaseScorer
from app.scoring.canonicalize import canonicalize_number, canonicalize_string


class ToolArgumentValidityScorer(BaseScorer):
    metric_name = "tool_argument_validity"

    def score(self, task: Task, trace: Trace) -> MetricResult:
        if not task.expected_steps:
            return MetricResult(
                metric_name=self.metric_name,
                value=1.0,
                evidence={"reason": "No expected steps defined."},
                severity=Severity.INFO,
            )

        total_constraints = 0
        satisfied = 0
        details = []

        for i, step in enumerate(task.expected_steps):
            if not step.arg_constraints:
                continue

            actual_args = {}
            if i < len(trace.tool_calls):
                actual_args = trace.tool_calls[i].get("arguments", {})

            for constraint in step.arg_constraints:
                total_constraints += 1
                result = _check_constraint(constraint, actual_args)
                if result["satisfied"]:
                    satisfied += 1
                details.append({
                    "step": i,
                    "param": constraint.param_name,
                    "constraint_type": constraint.constraint_type.value,
                    **result,
                })

        if total_constraints == 0:
            value = 1.0
        else:
            value = satisfied / total_constraints

        severity = Severity.INFO if value >= 0.8 else (Severity.WARN if value >= 0.5 else Severity.FAIL)

        return MetricResult(
            metric_name=self.metric_name,
            value=value,
            evidence={
                "satisfied": satisfied,
                "total_constraints": total_constraints,
                "details": details,
            },
            severity=severity,
        )


def _check_constraint(constraint: ArgConstraint, actual_args: dict[str, Any]) -> dict[str, Any]:
    """Check a single argument constraint."""
    actual_value = actual_args.get(constraint.param_name)

    if constraint.constraint_type == ArgConstraintType.ANY:
        return {
            "satisfied": actual_value is not None,
            "actual": actual_value,
            "reason": "any value accepted" if actual_value is not None else "parameter missing",
        }

    if actual_value is None:
        return {
            "satisfied": False,
            "actual": None,
            "reason": f"Parameter '{constraint.param_name}' not provided",
        }

    if constraint.constraint_type == ArgConstraintType.EXACT:
        expected = constraint.expected_value
        if isinstance(expected, str) and isinstance(actual_value, str):
            match = canonicalize_string(str(expected)) == canonicalize_string(str(actual_value))
        else:
            match = expected == actual_value
        return {
            "satisfied": match,
            "actual": actual_value,
            "expected": expected,
            "reason": "exact match" if match else "values differ",
        }

    if constraint.constraint_type == ArgConstraintType.REGEX:
        pattern = constraint.pattern or ""
        match = bool(re.search(pattern, str(actual_value), re.IGNORECASE))
        return {
            "satisfied": match,
            "actual": actual_value,
            "pattern": pattern,
            "reason": "regex match" if match else "regex not matched",
        }

    if constraint.constraint_type == ArgConstraintType.NUMERIC_TOLERANCE:
        expected_num = canonicalize_number(constraint.expected_value)
        actual_num = canonicalize_number(actual_value)
        tolerance = constraint.tolerance or 0.01
        if expected_num is not None and actual_num is not None:
            match = abs(expected_num - actual_num) <= tolerance
            return {
                "satisfied": match,
                "actual": actual_num,
                "expected": expected_num,
                "tolerance": tolerance,
                "difference": abs(expected_num - actual_num),
                "reason": "within tolerance" if match else "outside tolerance",
            }
        return {
            "satisfied": False,
            "actual": actual_value,
            "reason": "could not parse as number",
        }

    if constraint.constraint_type == ArgConstraintType.SET_MEMBERSHIP:
        allowed = constraint.allowed_values or []
        # Normalize for comparison
        normalized_actual = canonicalize_string(str(actual_value)) if isinstance(actual_value, str) else actual_value
        normalized_allowed = [
            canonicalize_string(str(v)) if isinstance(v, str) else v
            for v in allowed
        ]
        match = normalized_actual in normalized_allowed
        return {
            "satisfied": match,
            "actual": actual_value,
            "allowed": allowed,
            "reason": "in allowed set" if match else "not in allowed set",
        }

    if constraint.constraint_type == ArgConstraintType.JSON_SCHEMA:
        import jsonschema
        schema = constraint.schema or {}
        try:
            jsonschema.validate(instance=actual_value, schema=schema)
            return {"satisfied": True, "actual": actual_value, "reason": "schema valid"}
        except jsonschema.ValidationError as e:
            return {"satisfied": False, "actual": actual_value, "reason": f"schema invalid: {e.message}"}

    return {"satisfied": False, "reason": f"Unknown constraint type: {constraint.constraint_type}"}
