"""File result sink - writes results as JSONL to a file."""

from __future__ import annotations

import json
from pathlib import Path

import structlog

from app.schemas.results_schema import EvalRunResult
from app.sinks.base import ResultSink

logger = structlog.get_logger()


class FileSink(ResultSink):
    """Write results to a JSONL file."""

    def __init__(self, path: str = "/results/results.jsonl") -> None:
        self._path = Path(path)

    def write(self, result: EvalRunResult) -> None:
        self._path.parent.mkdir(parents=True, exist_ok=True)
        data = result.model_dump(mode="json")
        with open(self._path, "a") as f:
            f.write(json.dumps(data, default=str) + "\n")
        logger.info("file_sink_written", path=str(self._path))
