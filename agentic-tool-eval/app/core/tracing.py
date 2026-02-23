"""Tracing system for evaluation runs.

Every eval run produces a complete trace of:
- Messages exchanged
- Tool calls attempted and results
- Scoring outputs with evidence
- Timing information

Traces support replay: given a stored trace, scoring can be re-run
without contacting the agent.
"""

from __future__ import annotations

import json
import uuid
from datetime import datetime, timezone
from enum import Enum
from typing import Any

from pydantic import BaseModel, Field


class TraceEventType(str, Enum):
    RUN_START = "run_start"
    TURN_START = "turn_start"
    AGENT_REQUEST = "agent_request"
    AGENT_RESPONSE = "agent_response"
    TOOL_CALL_START = "tool_call_start"
    TOOL_CALL_END = "tool_call_end"
    TOOL_VALIDATION_ERROR = "tool_validation_error"
    FAILURE_INJECTED = "failure_injected"
    USER_SIMULATOR_RESPONSE = "user_simulator_response"
    MILESTONE_CHECK = "milestone_check"
    SCORING_START = "scoring_start"
    SCORING_RESULT = "scoring_result"
    RUN_END = "run_end"
    ERROR = "error"


class TraceEvent(BaseModel):
    """A single event in an evaluation trace."""
    timestamp: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    event_type: TraceEventType
    data: dict[str, Any] = Field(default_factory=dict)


class Trace(BaseModel):
    """Complete trace for an evaluation run of a single task."""
    trace_id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    task_id: str
    suite_id: str
    agent_id: str
    started_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    finished_at: datetime | None = None
    events: list[TraceEvent] = Field(default_factory=list)

    # Collected data for replay
    messages: list[dict[str, Any]] = Field(default_factory=list)
    tool_calls: list[dict[str, Any]] = Field(default_factory=list)
    tool_results: list[dict[str, Any]] = Field(default_factory=list)
    final_answer: str | None = None
    final_state: dict[str, Any] | None = None

    def add_event(self, event_type: TraceEventType, data: dict[str, Any] | None = None) -> None:
        self.events.append(TraceEvent(event_type=event_type, data=data or {}))

    def record_tool_call(
        self,
        tool_name: str,
        arguments: dict[str, Any],
        result: dict[str, Any],
        success: bool,
        duration_ms: float,
    ) -> None:
        call_record = {
            "tool_name": tool_name,
            "arguments": arguments,
            "success": success,
            "duration_ms": duration_ms,
        }
        self.tool_calls.append(call_record)
        self.tool_results.append(result)

    def finalize(self) -> None:
        self.finished_at = datetime.now(timezone.utc)
        self.add_event(TraceEventType.RUN_END)

    def to_json(self) -> str:
        return self.model_dump_json(indent=2)

    @classmethod
    def from_json(cls, json_str: str) -> Trace:
        return cls.model_validate_json(json_str)

    @classmethod
    def from_file(cls, path: str) -> Trace:
        with open(path, "r") as f:
            return cls.model_validate_json(f.read())

    def save(self, path: str) -> None:
        with open(path, "w") as f:
            f.write(self.to_json())
