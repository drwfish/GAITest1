"""Task (eval case) schema definitions.

A Task represents a single evaluation case. Tasks are grouped into suites.
Each task specifies:
- A prompt for the agent
- Which tools are available
- Expected behavior (steps, final answer, state)
- Scoring configuration

Tasks are loaded from YAML files in app/resources/tasks/<suite_id>/.
"""

from __future__ import annotations

from enum import Enum
from typing import Any

from pydantic import BaseModel, Field


class ArgConstraintType(str, Enum):
    """Types of argument constraints for expected steps."""
    EXACT = "exact"
    REGEX = "regex"
    NUMERIC_TOLERANCE = "numeric_tolerance"
    SET_MEMBERSHIP = "set_membership"
    JSON_SCHEMA = "json_schema"
    ANY = "any"


class ArgConstraint(BaseModel):
    """Constraint on a single argument of a tool call."""
    param_name: str
    constraint_type: ArgConstraintType = ArgConstraintType.EXACT
    expected_value: Any = None
    tolerance: float | None = None  # For numeric_tolerance
    allowed_values: list[Any] | None = None  # For set_membership
    pattern: str | None = None  # For regex
    schema: dict[str, Any] | None = None  # For json_schema


class ExpectedStep(BaseModel):
    """Expected step in a tool-use trajectory."""
    allowed_tools: list[str] = Field(
        ..., description="Tool names that are acceptable for this step"
    )
    arg_constraints: list[ArgConstraint] = Field(
        default_factory=list,
        description="Constraints on the arguments passed to the tool",
    )
    description: str | None = None


class UserSimulatorRule(BaseModel):
    """Rule for the user simulator in multi-turn tasks."""
    trigger_pattern: str = Field(
        ..., description="Regex pattern to match against agent's question/output"
    )
    response: str = Field(
        ..., description="Response to return when trigger matches"
    )


class UserSimulatorConfig(BaseModel):
    """Configuration for the user simulator."""
    rules: list[UserSimulatorRule] = Field(default_factory=list)
    default_response: str = "I don't have that information."


class Milestone(BaseModel):
    """Intermediate checkpoint in a multi-step task."""
    id: str
    description: str
    check_type: str = "state_contains"  # state_contains, tool_called, answer_contains
    expected_value: Any = None
    weight: float = 1.0


class ScoringConfig(BaseModel):
    """Scoring weights and thresholds for a task."""
    tool_selection_weight: float = 1.0
    tool_args_weight: float = 1.0
    trajectory_weight: float = 1.0
    efficiency_weight: float = 0.5
    final_answer_weight: float = 1.0
    final_state_weight: float = 0.0
    abstention_weight: float = 0.0
    robustness_weight: float = 0.0
    safety_weight: float = 0.0
    pass_threshold: float = 0.7
    final_answer_mode: str = "exact"  # exact, regex, judge


class FailureInjectionRule(BaseModel):
    """Rule for injecting failures into tool calls."""
    tool_name: str
    failure_rate: float = 0.0  # 0-1 probability (ignored if trigger_on_call is set)
    trigger_on_call: int | None = None  # Deterministic: fail on Nth call (1-based)
    error_message: str = "Simulated tool failure"
    timeout_ms: int | None = None  # Simulate timeout by sleeping


class Task(BaseModel):
    """A single evaluation task (eval case)."""
    id: str
    suite_id: str
    category: str = "agentic"
    prompt: str = Field(..., description="Initial user request for the agent")
    toolset_id: str = Field(
        ..., description="Identifier for which tool subset to expose"
    )
    max_turns: int = 10
    max_tool_calls: int = 20
    expected_steps: list[ExpectedStep] = Field(default_factory=list)
    order_matters: bool = True
    expected_final_answer: Any | None = None
    expected_final_state: dict[str, Any] | None = None
    abstain_expected: bool = False
    scoring: ScoringConfig = Field(default_factory=ScoringConfig)
    user_simulator: UserSimulatorConfig | None = None
    milestones: list[Milestone] = Field(default_factory=list)
    failure_injection: list[FailureInjectionRule] = Field(default_factory=list)
    tags: list[str] = Field(default_factory=list)
    description: str | None = None


class Suite(BaseModel):
    """A collection of tasks forming an evaluation suite."""
    id: str
    name: str
    description: str = ""
    version: str = "1.0.0"
    category: str = "agentic"
    tasks: list[Task] = Field(default_factory=list)
    tags: list[str] = Field(default_factory=list)
