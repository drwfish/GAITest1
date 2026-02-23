"""Replay engine for re-scoring traces without agent access.

Given a stored trace, the replay engine can:
1. Reconstruct the task from the trace
2. Re-run all scorers
3. Produce identical summary metrics (deterministic)

This enables offline analysis and scorer development.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import structlog

from app.core.tracing import Trace
from app.schemas.results_schema import MetricResult, TaskResult
from app.schemas.task_schema import Task
from app.scoring.composite import CompositeScorer

logger = structlog.get_logger()


def replay_trace(
    trace: Trace,
    task: Task,
    scorers: CompositeScorer | None = None,
) -> TaskResult:
    """Re-score a trace without contacting the agent.

    Args:
        trace: A previously recorded trace.
        task: The task definition (needed for expected values and scoring config).
        scorers: Scorer pipeline to use. Defaults to CompositeScorer().

    Returns:
        TaskResult with updated scores.
    """
    scorers = scorers or CompositeScorer()

    logger.info("replay_started", trace_id=trace.trace_id, task_id=task.id)

    metrics = scorers.score(task, trace)
    overall, passed = scorers.compute_composite(task, metrics)

    return TaskResult(
        task_id=task.id,
        suite_id=task.suite_id,
        passed=passed,
        overall_score=overall,
        metrics=metrics,
        trace_id=trace.trace_id,
    )


def replay_from_files(
    trace_path: str,
    task_path: str | None = None,
    task_data: dict[str, Any] | None = None,
    scorers: CompositeScorer | None = None,
) -> TaskResult:
    """Replay from file paths.

    Args:
        trace_path: Path to the trace JSON file.
        task_path: Path to the task YAML/JSON file.
        task_data: Alternative to task_path: provide task data directly.
        scorers: Optional scorer pipeline.

    Returns:
        TaskResult from replay.
    """
    trace = Trace.from_file(trace_path)

    if task_data:
        task = Task(**task_data)
    elif task_path:
        import yaml
        with open(task_path, "r") as f:
            raw = yaml.safe_load(f)
        task = Task(**raw)
    else:
        raise ValueError("Either task_path or task_data must be provided")

    return replay_trace(trace, task, scorers)
