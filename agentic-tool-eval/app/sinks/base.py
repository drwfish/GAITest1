"""Base result sink interface.

All sinks implement write() to persist evaluation results.
"""

from __future__ import annotations

from abc import ABC, abstractmethod

from app.schemas.results_schema import EvalRunResult


class ResultSink(ABC):
    """Base class for result sinks."""

    @abstractmethod
    def write(self, result: EvalRunResult) -> None:
        """Write evaluation results to this sink.

        Args:
            result: The complete evaluation run result.
        """
        ...
