"""Stdout result sink - writes results to standard output.

Always available, useful for Kubernetes Job mode where results
are captured from container stdout.
"""

from __future__ import annotations

import json
import sys

from app.schemas.results_schema import EvalRunResult
from app.sinks.base import ResultSink


class StdoutSink(ResultSink):
    """Write results to stdout as JSON."""

    def __init__(self, pretty: bool = True) -> None:
        self._pretty = pretty

    def write(self, result: EvalRunResult) -> None:
        data = result.model_dump(mode="json")
        indent = 2 if self._pretty else None
        json.dump(data, sys.stdout, indent=indent, default=str)
        sys.stdout.write("\n")
        sys.stdout.flush()
