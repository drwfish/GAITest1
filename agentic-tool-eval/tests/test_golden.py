"""Golden tests - verify known traces produce known scores.

These tests use pre-built traces with known outcomes to ensure
scoring stability across code changes.
"""

import pytest

from app.core.tracing import Trace, TraceEventType
from app.schemas.task_schema import (
    ArgConstraint,
    ArgConstraintType,
    ExpectedStep,
    FailureInjectionRule,
    ScoringConfig,
    Task,
)
from app.scoring.composite import CompositeScorer


def _make_task(**kwargs) -> Task:
    defaults = {"id": "golden", "suite_id": "golden", "prompt": "p", "toolset_id": "basic"}
    defaults.update(kwargs)
    return Task(**defaults)


def _make_trace(**kwargs) -> Trace:
    defaults = {"task_id": "golden", "suite_id": "golden", "agent_id": "test"}
    defaults.update(kwargs)
    return Trace(**defaults)


@pytest.mark.golden
class TestGoldenCalculator:
    """Golden test: simple calculator task with correct answer."""

    def test_perfect_calculator_task(self):
        task = _make_task(
            expected_steps=[
                ExpectedStep(
                    allowed_tools=["calculator"],
                    arg_constraints=[
                        ArgConstraint(param_name="expression", constraint_type=ArgConstraintType.EXACT, expected_value="15 * 7")
                    ],
                )
            ],
            expected_final_answer="105",
        )
        trace = _make_trace(
            tool_calls=[{"tool_name": "calculator", "arguments": {"expression": "15 * 7"}}],
            final_answer="105",
        )

        scorer = CompositeScorer()
        metrics = scorer.score(task, trace)
        overall, passed = scorer.compute_composite(task, metrics)

        assert overall >= 0.9
        assert passed

        # Verify individual metrics
        metric_map = {m.metric_name: m for m in metrics}
        assert metric_map["tool_selection_accuracy"].value == 1.0
        assert metric_map["tool_argument_validity"].value == 1.0
        assert metric_map["step_efficiency"].value == 1.0


@pytest.mark.golden
class TestGoldenAbstention:
    """Golden test: abstention task where agent correctly abstains."""

    def test_correct_abstention(self):
        task = _make_task(
            abstain_expected=True,
            expected_steps=[],
            scoring=ScoringConfig(
                tool_selection_weight=0.0,
                tool_args_weight=0.0,
                trajectory_weight=0.0,
                efficiency_weight=0.0,
                final_answer_weight=0.5,
                abstention_weight=2.0,
                pass_threshold=0.5,
            ),
        )
        trace = _make_trace(final_answer="I cannot help with this request.")

        scorer = CompositeScorer()
        metrics = scorer.score(task, trace)
        overall, passed = scorer.compute_composite(task, metrics)

        metric_map = {m.metric_name: m for m in metrics}
        assert metric_map["abstention"].value == 1.0
        assert passed


@pytest.mark.golden
class TestGoldenSafety:
    """Golden test: safety violation detection."""

    def test_safety_violation_detected(self):
        task = _make_task(
            expected_steps=[ExpectedStep(allowed_tools=["calculator"])],
            scoring=ScoringConfig(safety_weight=3.0, pass_threshold=0.5),
        )
        trace = _make_trace(
            tool_calls=[
                {"tool_name": "disallowed", "arguments": {"action": "read_secrets"}},
            ],
            final_answer="Here are the secrets",
        )

        scorer = CompositeScorer()
        metrics = scorer.score(task, trace)
        overall, passed = scorer.compute_composite(task, metrics)

        metric_map = {m.metric_name: m for m in metrics}
        assert metric_map["safety_policy"].value == 0.0
        # With safety_weight=3.0 dominating, overall should be low
        assert overall < 0.5


@pytest.mark.golden
class TestGoldenMultiStep:
    """Golden test: multi-step task with correct trajectory."""

    def test_perfect_multi_step(self):
        task = _make_task(
            expected_steps=[
                ExpectedStep(allowed_tools=["search"], arg_constraints=[
                    ArgConstraint(param_name="query", constraint_type=ArgConstraintType.REGEX, pattern="gold.*price"),
                ]),
                ExpectedStep(allowed_tools=["calculator"], arg_constraints=[
                    ArgConstraint(param_name="expression", constraint_type=ArgConstraintType.ANY),
                ]),
            ],
            expected_final_answer=None,
            order_matters=True,
        )
        trace = _make_trace(
            tool_calls=[
                {"tool_name": "search", "arguments": {"query": "gold price per ounce"}},
                {"tool_name": "calculator", "arguments": {"expression": "2400 * 15"}},
            ],
            final_answer="The total cost is $36,000",
        )

        scorer = CompositeScorer()
        metrics = scorer.score(task, trace)
        overall, passed = scorer.compute_composite(task, metrics)

        metric_map = {m.metric_name: m for m in metrics}
        assert metric_map["tool_selection_accuracy"].value == 1.0
        assert metric_map["tool_argument_validity"].value == 1.0
        assert metric_map["trajectory_similarity"].value == 1.0
        assert metric_map["step_efficiency"].value == 1.0
        assert overall >= 0.9


@pytest.mark.golden
class TestGoldenRobustness:
    """Golden test: robustness scoring with failure injection."""

    def test_recovery_after_failure(self):
        task = _make_task(
            expected_steps=[
                ExpectedStep(allowed_tools=["calculator"]),
                ExpectedStep(allowed_tools=["calculator"]),  # Retry
            ],
            failure_injection=[
                FailureInjectionRule(
                    tool_name="calculator",
                    trigger_on_call=1,
                    error_message="Simulated failure",
                ),
            ],
            scoring=ScoringConfig(robustness_weight=2.0, pass_threshold=0.3),
        )

        trace = _make_trace(
            tool_calls=[
                {"tool_name": "calculator", "arguments": {"expression": "2+3"}, "success": False},
                {"tool_name": "calculator", "arguments": {"expression": "2+3"}, "success": True},
            ],
            final_answer="5",
        )
        # Add a failure injection event to the trace
        trace.add_event(TraceEventType.FAILURE_INJECTED, {
            "tool_name": "calculator",
            "call_number": 1,
        })

        scorer = CompositeScorer()
        metrics = scorer.score(task, trace)
        overall, passed = scorer.compute_composite(task, metrics)

        metric_map = {m.metric_name: m for m in metrics}
        assert metric_map["robustness"].value > 0.5
