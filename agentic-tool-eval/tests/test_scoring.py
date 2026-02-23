"""Unit tests for scoring components."""

import pytest

from app.core.tracing import Trace, TraceEventType
from app.schemas.results_schema import Severity
from app.schemas.task_schema import (
    ArgConstraint,
    ArgConstraintType,
    ExpectedStep,
    FailureInjectionRule,
    ScoringConfig,
    Task,
)
from app.scoring.abstention import AbstentionScorer
from app.scoring.efficiency import StepEfficiencyScorer
from app.scoring.final_answer import FinalAnswerScorer
from app.scoring.safety import SafetyPolicyScorer
from app.scoring.tool_args import ToolArgumentValidityScorer
from app.scoring.tool_selection import ToolSelectionAccuracyScorer
from app.scoring.trajectory import TrajectorySimilarityScorer
from app.scoring.composite import CompositeScorer


def _make_task(**kwargs) -> Task:
    defaults = {
        "id": "test_001",
        "suite_id": "test_suite",
        "prompt": "Test prompt",
        "toolset_id": "basic",
    }
    defaults.update(kwargs)
    return Task(**defaults)


def _make_trace(**kwargs) -> Trace:
    defaults = {
        "task_id": "test_001",
        "suite_id": "test_suite",
        "agent_id": "test_agent",
    }
    defaults.update(kwargs)
    return Trace(**defaults)


class TestToolSelectionAccuracy:
    def test_perfect_selection(self):
        task = _make_task(expected_steps=[
            ExpectedStep(allowed_tools=["calculator"]),
            ExpectedStep(allowed_tools=["search"]),
        ])
        trace = _make_trace(tool_calls=[
            {"tool_name": "calculator", "arguments": {}},
            {"tool_name": "search", "arguments": {}},
        ])
        result = ToolSelectionAccuracyScorer().score(task, trace)
        assert result.value == 1.0

    def test_wrong_selection(self):
        task = _make_task(expected_steps=[
            ExpectedStep(allowed_tools=["calculator"]),
        ])
        trace = _make_trace(tool_calls=[
            {"tool_name": "search", "arguments": {}},
        ])
        result = ToolSelectionAccuracyScorer().score(task, trace)
        assert result.value == 0.0

    def test_partial_selection(self):
        task = _make_task(expected_steps=[
            ExpectedStep(allowed_tools=["calculator"]),
            ExpectedStep(allowed_tools=["search"]),
        ])
        trace = _make_trace(tool_calls=[
            {"tool_name": "calculator", "arguments": {}},
            {"tool_name": "calculator", "arguments": {}},
        ])
        result = ToolSelectionAccuracyScorer().score(task, trace)
        assert result.value == 0.5

    def test_no_expected_steps(self):
        task = _make_task(expected_steps=[])
        trace = _make_trace()
        result = ToolSelectionAccuracyScorer().score(task, trace)
        assert result.value == 1.0

    def test_multiple_allowed_tools(self):
        task = _make_task(expected_steps=[
            ExpectedStep(allowed_tools=["calculator", "fast_approx"]),
        ])
        trace = _make_trace(tool_calls=[
            {"tool_name": "fast_approx", "arguments": {}},
        ])
        result = ToolSelectionAccuracyScorer().score(task, trace)
        assert result.value == 1.0


class TestToolArgumentValidity:
    def test_exact_match(self):
        task = _make_task(expected_steps=[
            ExpectedStep(
                allowed_tools=["calculator"],
                arg_constraints=[
                    ArgConstraint(param_name="expression", constraint_type=ArgConstraintType.EXACT, expected_value="2 + 3"),
                ],
            )
        ])
        trace = _make_trace(tool_calls=[
            {"tool_name": "calculator", "arguments": {"expression": "2 + 3"}},
        ])
        result = ToolArgumentValidityScorer().score(task, trace)
        assert result.value == 1.0

    def test_regex_match(self):
        task = _make_task(expected_steps=[
            ExpectedStep(
                allowed_tools=["search"],
                arg_constraints=[
                    ArgConstraint(param_name="query", constraint_type=ArgConstraintType.REGEX, pattern=r"renewable.*energy"),
                ],
            )
        ])
        trace = _make_trace(tool_calls=[
            {"tool_name": "search", "arguments": {"query": "renewable energy policy"}},
        ])
        result = ToolArgumentValidityScorer().score(task, trace)
        assert result.value == 1.0

    def test_numeric_tolerance(self):
        task = _make_task(expected_steps=[
            ExpectedStep(
                allowed_tools=["calculator"],
                arg_constraints=[
                    ArgConstraint(
                        param_name="value",
                        constraint_type=ArgConstraintType.NUMERIC_TOLERANCE,
                        expected_value=3.14,
                        tolerance=0.01,
                    ),
                ],
            )
        ])
        trace = _make_trace(tool_calls=[
            {"tool_name": "calculator", "arguments": {"value": 3.141}},
        ])
        result = ToolArgumentValidityScorer().score(task, trace)
        assert result.value == 1.0


class TestStepEfficiency:
    def test_perfect_efficiency(self):
        task = _make_task(expected_steps=[
            ExpectedStep(allowed_tools=["calculator"]),
            ExpectedStep(allowed_tools=["search"]),
        ])
        trace = _make_trace(tool_calls=[
            {"tool_name": "calculator", "arguments": {}},
            {"tool_name": "search", "arguments": {}},
        ])
        result = StepEfficiencyScorer().score(task, trace)
        assert result.value == 1.0

    def test_over_stepping(self):
        task = _make_task(expected_steps=[
            ExpectedStep(allowed_tools=["calculator"]),
        ])
        trace = _make_trace(tool_calls=[
            {"tool_name": "calculator", "arguments": {}},
            {"tool_name": "calculator", "arguments": {}},
        ])
        result = StepEfficiencyScorer().score(task, trace)
        assert result.value == 0.5  # ratio=2, value=1/2

    def test_no_steps_taken(self):
        task = _make_task(expected_steps=[
            ExpectedStep(allowed_tools=["calculator"]),
        ])
        trace = _make_trace()
        result = StepEfficiencyScorer().score(task, trace)
        assert result.value == 0.0


class TestFinalAnswer:
    def test_exact_match(self):
        task = _make_task(expected_final_answer="42")
        trace = _make_trace(final_answer="42")
        result = FinalAnswerScorer().score(task, trace)
        assert result.value == 1.0

    def test_numeric_match(self):
        task = _make_task(expected_final_answer="42")
        trace = _make_trace(final_answer="42.0")
        result = FinalAnswerScorer().score(task, trace)
        assert result.value == 1.0

    def test_no_answer(self):
        task = _make_task(expected_final_answer="42")
        trace = _make_trace(final_answer=None)
        result = FinalAnswerScorer().score(task, trace)
        assert result.value == 0.0

    def test_no_expected(self):
        task = _make_task()
        trace = _make_trace(final_answer="anything")
        result = FinalAnswerScorer().score(task, trace)
        assert result.value == 1.0

    def test_regex_mode(self):
        task = _make_task(
            expected_final_answer=r"\d+",
            scoring=ScoringConfig(final_answer_mode="regex"),
        )
        trace = _make_trace(final_answer="The answer is 42")
        result = FinalAnswerScorer().score(task, trace)
        assert result.value == 1.0


class TestAbstention:
    def test_correct_abstention(self):
        task = _make_task(abstain_expected=True)
        trace = _make_trace()
        result = AbstentionScorer().score(task, trace)
        assert result.value == 1.0

    def test_incorrect_tool_use(self):
        task = _make_task(abstain_expected=True)
        trace = _make_trace(tool_calls=[{"tool_name": "calculator", "arguments": {}}])
        result = AbstentionScorer().score(task, trace)
        assert result.value == 0.0
        assert result.severity == Severity.FAIL

    def test_not_applicable(self):
        task = _make_task(abstain_expected=False)
        trace = _make_trace()
        result = AbstentionScorer().score(task, trace)
        assert result.value == 1.0


class TestSafetyPolicy:
    def test_no_violations(self):
        task = _make_task()
        trace = _make_trace(tool_calls=[
            {"tool_name": "calculator", "arguments": {"expression": "2+3"}},
        ])
        result = SafetyPolicyScorer().score(task, trace)
        assert result.value == 1.0

    def test_disallowed_tool_called(self):
        task = _make_task()
        trace = _make_trace(tool_calls=[
            {"tool_name": "disallowed", "arguments": {"action": "read_secrets"}},
        ])
        result = SafetyPolicyScorer().score(task, trace)
        assert result.value == 0.0
        assert result.severity == Severity.FAIL

    def test_no_tool_calls(self):
        task = _make_task()
        trace = _make_trace()
        result = SafetyPolicyScorer().score(task, trace)
        assert result.value == 1.0


class TestTrajectorySimilarity:
    def test_perfect_ordered(self):
        task = _make_task(
            order_matters=True,
            expected_steps=[
                ExpectedStep(allowed_tools=["calculator"]),
                ExpectedStep(allowed_tools=["search"]),
            ],
        )
        trace = _make_trace(tool_calls=[
            {"tool_name": "calculator"},
            {"tool_name": "search"},
        ])
        result = TrajectorySimilarityScorer().score(task, trace)
        assert result.value == 1.0

    def test_reversed_order(self):
        task = _make_task(
            order_matters=True,
            expected_steps=[
                ExpectedStep(allowed_tools=["calculator"]),
                ExpectedStep(allowed_tools=["search"]),
            ],
        )
        trace = _make_trace(tool_calls=[
            {"tool_name": "search"},
            {"tool_name": "calculator"},
        ])
        result = TrajectorySimilarityScorer().score(task, trace)
        # Edit distance = 2, max_len = 2, value = 0.0
        assert result.value == 0.0

    def test_unordered_match(self):
        task = _make_task(
            order_matters=False,
            expected_steps=[
                ExpectedStep(allowed_tools=["calculator"]),
                ExpectedStep(allowed_tools=["search"]),
            ],
        )
        trace = _make_trace(tool_calls=[
            {"tool_name": "search"},
            {"tool_name": "calculator"},
        ])
        result = TrajectorySimilarityScorer().score(task, trace)
        assert result.value == 1.0


class TestCompositeScorer:
    def test_basic_composite(self):
        task = _make_task(
            expected_steps=[ExpectedStep(allowed_tools=["calculator"])],
            expected_final_answer="5",
        )
        trace = _make_trace(
            tool_calls=[{"tool_name": "calculator", "arguments": {}}],
            final_answer="5",
        )
        scorer = CompositeScorer()
        metrics = scorer.score(task, trace)
        overall, passed = scorer.compute_composite(task, metrics)
        assert overall > 0
        assert isinstance(passed, bool)
