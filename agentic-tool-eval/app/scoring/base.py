"""Base scorer interface.

All scorers implement the BaseScorer interface and produce MetricResult objects.
"""

from __future__ import annotations

from abc import ABC, abstractmethod

from app.core.tracing import Trace
from app.schemas.results_schema import MetricResult
from app.schemas.task_schema import Task


class BaseScorer(ABC):
    """Base class for all scorers.

    Each scorer computes one metric and emits a MetricResult with:
    - metric_name
    - value (0 to 1)
    - evidence (structured, for debugging)
    - severity (info, warn, fail)
    """

    metric_name: str = ""

    @abstractmethod
    def score(self, task: Task, trace: Trace) -> MetricResult:
        """Score a task execution based on the trace.

        Args:
            task: The task definition with expected behavior.
            trace: The execution trace with actual behavior.

        Returns:
            MetricResult with the score and evidence.
        """
        ...
