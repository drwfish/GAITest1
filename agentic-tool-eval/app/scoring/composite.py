"""Composite scorer that aggregates all sub-scorers.

Uses configurable weights from the task's scoring config to produce:
- A list of individual MetricResults
- An overall_score (0 to 1)
- A pass/fail boolean based on configured threshold
"""

from __future__ import annotations

from app.core.tracing import Trace
from app.schemas.results_schema import MetricResult
from app.schemas.task_schema import Task
from app.scoring.abstention import AbstentionScorer
from app.scoring.base import BaseScorer
from app.scoring.efficiency import StepEfficiencyScorer
from app.scoring.final_answer import FinalAnswerScorer
from app.scoring.final_state import FinalStateScorer
from app.scoring.robustness import RobustnessScorer
from app.scoring.safety import SafetyPolicyScorer
from app.scoring.tool_args import ToolArgumentValidityScorer
from app.scoring.tool_selection import ToolSelectionAccuracyScorer
from app.scoring.trajectory import TrajectorySimilarityScorer


class CompositeScorer:
    """Aggregates multiple scorers into a weighted composite score."""

    def __init__(self, judge_enabled: bool = False) -> None:
        self._scorers: list[BaseScorer] = [
            ToolSelectionAccuracyScorer(),
            ToolArgumentValidityScorer(),
            TrajectorySimilarityScorer(),
            StepEfficiencyScorer(),
            FinalAnswerScorer(judge_enabled=judge_enabled),
            FinalStateScorer(),
            AbstentionScorer(),
            RobustnessScorer(),
            SafetyPolicyScorer(),
        ]

    def score(self, task: Task, trace: Trace) -> list[MetricResult]:
        """Run all scorers and return individual results."""
        results = []
        for scorer in self._scorers:
            result = scorer.score(task, trace)
            results.append(result)
        return results

    def compute_composite(
        self, task: Task, metrics: list[MetricResult]
    ) -> tuple[float, bool]:
        """Compute weighted overall score and pass/fail.

        Args:
            task: The task with scoring weights.
            metrics: Individual metric results from score().

        Returns:
            Tuple of (overall_score, passed).
        """
        scoring = task.scoring
        weight_map = {
            "tool_selection_accuracy": scoring.tool_selection_weight,
            "tool_argument_validity": scoring.tool_args_weight,
            "trajectory_similarity": scoring.trajectory_weight,
            "step_efficiency": scoring.efficiency_weight,
            "final_answer": scoring.final_answer_weight,
            "final_state": scoring.final_state_weight,
            "abstention": scoring.abstention_weight,
            "robustness": scoring.robustness_weight,
            "safety_policy": scoring.safety_weight,
        }

        total_weight = 0.0
        weighted_sum = 0.0

        for metric in metrics:
            weight = weight_map.get(metric.metric_name, 0.0)
            if weight > 0:
                weighted_sum += metric.value * weight
                total_weight += weight

        overall = weighted_sum / total_weight if total_weight > 0 else 0.0
        overall = round(min(1.0, max(0.0, overall)), 4)
        passed = overall >= scoring.pass_threshold

        return overall, passed
