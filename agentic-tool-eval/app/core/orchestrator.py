"""Evaluation orchestrator.

The Orchestrator is the main engine that:
1. Loads tasks from a suite
2. Sets up the environment for each task
3. Runs the agent through the evaluation loop
4. Collects traces and scores results
5. Aggregates results and writes to sinks

The orchestrator does NOT contain scoring or tool logic directly;
it delegates to the appropriate components.
"""

from __future__ import annotations

import math
import re
import statistics
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import structlog
import yaml

from app.agents.base import BaseAgent
from app.core.environment import Environment
from app.core.registry import TOOLSET_CONFIGS, ToolRegistry, build_default_registry
from app.core.tracing import Trace, TraceEventType
from app.schemas.agent_protocol import (
    AgentRequest,
    AgentResponse,
    Message,
    MessageRole,
    ToolCall,
    ToolSchema,
)
from app.schemas.results_schema import (
    EnvironmentMetadata,
    EvalRunResult,
    MetricResult,
    RunConfig,
    RunSummary,
    SubMetricAggregate,
    TaskResult,
    ToolConfusionEntry,
)
from app.schemas.task_schema import Suite, Task, UserSimulatorConfig
from app.scoring.composite import CompositeScorer
from app.sinks.base import ResultSink

logger = structlog.get_logger()


class Orchestrator:
    """Main evaluation orchestrator."""

    def __init__(
        self,
        registry: ToolRegistry | None = None,
        scorers: CompositeScorer | None = None,
        sinks: list[ResultSink] | None = None,
        simulate_latency: bool = False,
        judge_enabled: bool = False,
    ) -> None:
        self.registry = registry or build_default_registry()
        self.scorers = scorers or CompositeScorer()
        self.sinks = sinks or []
        self.simulate_latency = simulate_latency
        self.judge_enabled = judge_enabled

    def load_suite(self, suite_id: str, resources_dir: str | None = None) -> Suite:
        """Load a suite from YAML files in the resources directory."""
        if resources_dir is None:
            resources_dir = str(Path(__file__).parent.parent / "resources" / "tasks")
        suite_dir = Path(resources_dir) / suite_id
        if not suite_dir.is_dir():
            raise FileNotFoundError(f"Suite directory not found: {suite_dir}")

        tasks: list[Task] = []
        for yaml_file in sorted(suite_dir.glob("*.yaml")):
            with open(yaml_file, "r") as f:
                data = yaml.safe_load(f)
            if data is None:
                continue
            # Support both single task and list of tasks in one file
            if isinstance(data, list):
                for item in data:
                    item.setdefault("suite_id", suite_id)
                    tasks.append(Task(**item))
            else:
                data.setdefault("suite_id", suite_id)
                tasks.append(Task(**data))

        suite = Suite(
            id=suite_id,
            name=suite_id.replace("_", " ").title(),
            description=f"Evaluation suite: {suite_id}",
            tasks=tasks,
        )
        logger.info("suite_loaded", suite_id=suite_id, task_count=len(tasks))
        return suite

    def list_suites(self, resources_dir: str | None = None) -> list[dict[str, Any]]:
        """List all available suites."""
        if resources_dir is None:
            resources_dir = str(Path(__file__).parent.parent / "resources" / "tasks")
        suites_path = Path(resources_dir)
        if not suites_path.is_dir():
            return []
        result = []
        for d in sorted(suites_path.iterdir()):
            if d.is_dir() and not d.name.startswith("_"):
                task_count = len(list(d.glob("*.yaml")))
                result.append({
                    "id": d.name,
                    "name": d.name.replace("_", " ").title(),
                    "task_files": task_count,
                })
        return result

    def run_suite(
        self,
        suite: Suite,
        agent: BaseAgent,
        run_config: RunConfig | None = None,
    ) -> EvalRunResult:
        """Run all tasks in a suite and return aggregated results."""
        run_id = str(uuid.uuid4())
        started_at = datetime.now(timezone.utc)

        logger.info("run_started", run_id=run_id, suite_id=suite.id, agent_id=agent.agent_id)

        run_result = EvalRunResult(
            run_id=run_id,
            started_at=started_at,
            suite_id=suite.id,
            suite_version=suite.version,
            agent_id=agent.agent_id,
            config=run_config,
            environment=EnvironmentMetadata(framework_version="0.1.0"),
        )

        task_results: list[TaskResult] = []
        all_tool_calls_expected: list[str] = []
        all_tool_calls_actual: list[str] = []

        for task in suite.tasks:
            try:
                task_result, trace = self._run_task(task, agent)
                task_results.append(task_result)

                # Collect confusion matrix data
                for i, step in enumerate(task.expected_steps):
                    expected_tool = step.allowed_tools[0] if step.allowed_tools else "none"
                    actual_tool = "none"
                    if i < len(trace.tool_calls):
                        actual_tool = trace.tool_calls[i].get("tool_name", "none")
                    all_tool_calls_expected.append(expected_tool)
                    all_tool_calls_actual.append(actual_tool)

            except Exception as e:
                logger.error("task_error", task_id=task.id, error=str(e))
                task_results.append(TaskResult(
                    task_id=task.id,
                    suite_id=suite.id,
                    passed=False,
                    overall_score=0.0,
                    error=str(e),
                ))

        # Build summary
        run_result.task_results = task_results
        run_result.summary = self._build_summary(task_results, all_tool_calls_expected, all_tool_calls_actual)
        run_result.finished_at = datetime.now(timezone.utc)

        logger.info(
            "run_completed",
            run_id=run_id,
            pass_rate=run_result.summary.pass_rate,
            overall_score=run_result.summary.overall_score,
        )

        # Write to sinks
        for sink in self.sinks:
            try:
                sink.write(run_result)
            except Exception as e:
                logger.error("sink_error", sink=type(sink).__name__, error=str(e))

        return run_result

    def _run_task(self, task: Task, agent: BaseAgent) -> tuple[TaskResult, Trace]:
        """Run a single task and return the result and trace."""
        task_start = time.monotonic()

        trace = Trace(task_id=task.id, suite_id=task.suite_id, agent_id=agent.agent_id)
        trace.add_event(TraceEventType.RUN_START, {"task_id": task.id})

        # Resolve toolset
        tool_names = TOOLSET_CONFIGS.get(task.toolset_id, [])
        tools = self.registry.get_subset(tool_names)

        # Create environment
        env = Environment(
            tools=tools,
            trace=trace,
            failure_rules=task.failure_injection,
            simulate_latency=self.simulate_latency,
        )

        # Build tool schemas for agent
        tool_schemas = [
            ToolSchema(**t.get_schema()) for t in tools.values()
        ]

        # Conversation loop
        messages: list[Message] = [
            Message(role=MessageRole.USER, content=task.prompt)
        ]
        trace.messages.append({"role": "user", "content": task.prompt})

        total_tool_calls = 0
        final_answer = None

        for turn in range(task.max_turns):
            trace.add_event(TraceEventType.TURN_START, {"turn": turn})

            # Build request
            request = AgentRequest(
                messages=messages,
                tools=tool_schemas,
                environment_hints={"task_id": task.id},
                max_tool_calls=task.max_tool_calls - total_tool_calls,
                turn_number=turn,
            )

            trace.add_event(TraceEventType.AGENT_REQUEST, {
                "turn": turn,
                "message_count": len(messages),
                "tool_count": len(tool_schemas),
            })

            # Get agent response
            try:
                response = agent.respond(request)
            except Exception as e:
                trace.add_event(TraceEventType.ERROR, {"error": str(e)})
                break

            trace.add_event(TraceEventType.AGENT_RESPONSE, {
                "is_final": response.is_final(),
                "tool_call_count": len(response.tool_calls),
            })

            if response.is_final():
                final_answer = response.final_answer
                trace.final_answer = final_answer
                messages.append(Message(role=MessageRole.ASSISTANT, content=final_answer or ""))
                trace.messages.append({"role": "assistant", "content": final_answer})
                break

            # Process tool calls
            if response.tool_calls:
                assistant_content = response.reasoning or "Making tool calls."
                messages.append(Message(role=MessageRole.ASSISTANT, content=assistant_content))
                trace.messages.append({"role": "assistant", "content": assistant_content})

                for tc in response.tool_calls:
                    if total_tool_calls >= task.max_tool_calls:
                        break
                    total_tool_calls += 1

                    result = env.execute_tool(tc.tool_name, tc.arguments)

                    tool_msg_content = result.output if result.success else f"Error: {result.error}"
                    messages.append(Message(
                        role=MessageRole.TOOL,
                        content=tool_msg_content,
                        tool_call_id=tc.id,
                        name=tc.tool_name,
                    ))
                    trace.messages.append({
                        "role": "tool",
                        "name": tc.tool_name,
                        "content": tool_msg_content,
                    })

            # Check for user simulator (multi-turn)
            if task.user_simulator and not response.is_final():
                sim_response = _run_user_simulator(
                    task.user_simulator,
                    messages,
                )
                if sim_response:
                    messages.append(Message(role=MessageRole.USER, content=sim_response))
                    trace.messages.append({"role": "user", "content": sim_response})
                    trace.add_event(
                        TraceEventType.USER_SIMULATOR_RESPONSE,
                        {"response": sim_response},
                    )

        trace.final_state = dict(env.state)
        trace.finalize()

        # Score the task
        trace.add_event(TraceEventType.SCORING_START)
        metrics = self.scorers.score(task, trace)
        for m in metrics:
            trace.add_event(TraceEventType.SCORING_RESULT, m.model_dump())

        overall, passed = self.scorers.compute_composite(task, metrics)

        duration_ms = (time.monotonic() - task_start) * 1000

        task_result = TaskResult(
            task_id=task.id,
            suite_id=task.suite_id,
            passed=passed,
            overall_score=overall,
            metrics=metrics,
            trace_id=trace.trace_id,
            duration_ms=duration_ms,
        )

        return task_result, trace

    def _build_summary(
        self,
        task_results: list[TaskResult],
        expected_tools: list[str],
        actual_tools: list[str],
    ) -> RunSummary:
        """Build aggregate summary from task results."""
        total = len(task_results)
        passed = sum(1 for r in task_results if r.passed)
        failed = sum(1 for r in task_results if not r.passed and r.error is None)
        errors = sum(1 for r in task_results if r.error is not None)
        scores = [r.overall_score for r in task_results]

        # Sub-metric aggregates
        metric_values: dict[str, list[float]] = {}
        for tr in task_results:
            for m in tr.metrics:
                metric_values.setdefault(m.metric_name, []).append(m.value)

        sub_aggregates = []
        for name, values in sorted(metric_values.items()):
            n = len(values)
            mean = statistics.mean(values) if values else 0.0
            med = statistics.median(values) if values else 0.0
            mn = min(values) if values else 0.0
            mx = max(values) if values else 0.0
            sd = statistics.stdev(values) if n > 1 else 0.0
            sub_aggregates.append(SubMetricAggregate(
                metric_name=name, mean=mean, median=med, min=mn, max=mx, std_dev=sd, count=n
            ))

        # Confusion matrix
        confusion: dict[tuple[str, str], int] = {}
        for exp, act in zip(expected_tools, actual_tools):
            key = (exp, act)
            confusion[key] = confusion.get(key, 0) + 1
        confusion_entries = [
            ToolConfusionEntry(expected_tool=k[0], actual_tool=k[1], count=v)
            for k, v in sorted(confusion.items())
        ]

        total_duration = sum(r.duration_ms for r in task_results)

        return RunSummary(
            total_tasks=total,
            passed_tasks=passed,
            failed_tasks=failed,
            error_tasks=errors,
            pass_rate=passed / total if total > 0 else 0.0,
            overall_score=statistics.mean(scores) if scores else 0.0,
            sub_metric_aggregates=sub_aggregates,
            tool_confusion_matrix=confusion_entries,
            total_duration_ms=total_duration,
        )


def _run_user_simulator(config: UserSimulatorConfig, messages: list[Message]) -> str | None:
    """Run the user simulator rules against the last assistant message.

    Returns a user message if a rule matches, or the default response
    if no rules match but the agent seems to be asking a question.
    """
    # Find last assistant message
    last_assistant = None
    for msg in reversed(messages):
        if msg.role == MessageRole.ASSISTANT:
            last_assistant = msg.content
            break

    if not last_assistant:
        return None

    # Check if the agent is asking a question (simple heuristic)
    is_question = "?" in last_assistant

    for rule in config.rules:
        if re.search(rule.trigger_pattern, last_assistant, re.IGNORECASE):
            return rule.response

    if is_question:
        return config.default_response

    return None
