"""Results schema for eval runs.

Defines a stable, versioned JSON schema for evaluation results.
Results are structured as "measures" with category=agentic and support
multiple sub-metrics. This schema is designed for ingestion into a
Responsible AI platform.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timezone
from enum import Enum
from typing import Any

from pydantic import BaseModel, Field


RESULTS_SCHEMA_VERSION = "1.0.0"


class Severity(str, Enum):
    INFO = "info"
    WARN = "warn"
    FAIL = "fail"


class MetricResult(BaseModel):
    """A single scorer's output for one task."""
    metric_name: str
    value: float = Field(..., ge=0.0, le=1.0)
    evidence: dict[str, Any] = Field(default_factory=dict)
    severity: Severity = Severity.INFO


class TaskResult(BaseModel):
    """Complete result for a single task."""
    task_id: str
    suite_id: str
    category: str = "agentic"
    passed: bool
    overall_score: float = Field(..., ge=0.0, le=1.0)
    metrics: list[MetricResult] = Field(default_factory=list)
    trace_id: str | None = None
    error: str | None = None
    duration_ms: float = 0.0


class ToolConfusionEntry(BaseModel):
    """Entry in the tool confusion matrix."""
    expected_tool: str
    actual_tool: str
    count: int


class SubMetricAggregate(BaseModel):
    """Aggregate statistics for a sub-metric across tasks."""
    metric_name: str
    mean: float
    median: float
    min: float
    max: float
    std_dev: float
    count: int


class RunSummary(BaseModel):
    """Summary statistics for an eval run."""
    total_tasks: int
    passed_tasks: int
    failed_tasks: int
    error_tasks: int = 0
    pass_rate: float = Field(..., ge=0.0, le=1.0)
    overall_score: float = Field(..., ge=0.0, le=1.0)
    sub_metric_aggregates: list[SubMetricAggregate] = Field(default_factory=list)
    tool_confusion_matrix: list[ToolConfusionEntry] = Field(default_factory=list)
    total_tool_calls: int = 0
    total_duration_ms: float = 0.0


class EnvironmentMetadata(BaseModel):
    """Metadata about the evaluation environment."""
    git_sha: str | None = None
    image_tag: str | None = None
    hostname: str | None = None
    python_version: str | None = None
    framework_version: str = "0.1.0"


class RunConfig(BaseModel):
    """Configuration used for the run, stored for reproducibility."""
    suite_id: str
    agent_adapter: str
    agent_config: dict[str, Any] = Field(default_factory=dict)
    failure_injection_enabled: bool = True
    judge_enabled: bool = False
    random_seed: int | None = None


class EvalRunResult(BaseModel):
    """Complete result for an evaluation run.

    This is the top-level results object written to sinks.
    Schema is versioned for backwards compatibility.
    """
    schema_version: str = RESULTS_SCHEMA_VERSION
    run_id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    started_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    finished_at: datetime | None = None
    suite_id: str
    suite_version: str = "1.0.0"
    agent_id: str
    category: str = "agentic"
    environment: EnvironmentMetadata = Field(default_factory=EnvironmentMetadata)
    config: RunConfig | None = None
    summary: RunSummary | None = None
    task_results: list[TaskResult] = Field(default_factory=list)


class RunStatus(str, Enum):
    PENDING = "pending"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"


class RunInfo(BaseModel):
    """Lightweight run info for API responses."""
    run_id: str
    suite_id: str
    agent_id: str
    status: RunStatus = RunStatus.PENDING
    started_at: datetime | None = None
    finished_at: datetime | None = None
    summary: RunSummary | None = None
