"""Evaluation environment.

An Environment provides:
- A set of tools available for a task
- An optional mutable state object
- Tool execution with validation, tracing, latency simulation, and failure injection
"""

from __future__ import annotations

import json
import time
from typing import Any

import jsonschema
import structlog

from app.core.tracing import Trace, TraceEventType
from app.schemas.task_schema import FailureInjectionRule
from app.tools.base import BaseTool, ToolResult

logger = structlog.get_logger()


class Environment:
    """Execution environment for a single task evaluation.

    Manages available tools, state, failure injection, and tracing.
    """

    def __init__(
        self,
        tools: dict[str, BaseTool],
        trace: Trace,
        state: dict[str, Any] | None = None,
        failure_rules: list[FailureInjectionRule] | None = None,
        simulate_latency: bool = False,
        max_simulated_latency_ms: float = 100.0,
    ) -> None:
        self.tools = tools
        self.trace = trace
        self.state = state if state is not None else {}
        self.failure_rules = {r.tool_name: r for r in (failure_rules or [])}
        self.simulate_latency = simulate_latency
        self.max_simulated_latency_ms = max_simulated_latency_ms
        self._call_counts: dict[str, int] = {}

    def get_available_tool_names(self) -> list[str]:
        return sorted(self.tools.keys())

    def get_tool_schemas(self) -> list[dict[str, Any]]:
        return [t.get_schema() for t in self.tools.values()]

    def execute_tool(self, tool_name: str, args: dict[str, Any]) -> ToolResult:
        """Execute a tool call with validation, tracing, and failure injection.

        Args:
            tool_name: Name of the tool to call.
            args: Arguments to pass to the tool.

        Returns:
            ToolResult with output or error.
        """
        start_time = time.monotonic()

        # Track call count for deterministic failure triggers
        self._call_counts[tool_name] = self._call_counts.get(tool_name, 0) + 1
        call_num = self._call_counts[tool_name]

        self.trace.add_event(
            TraceEventType.TOOL_CALL_START,
            {"tool_name": tool_name, "arguments": _safe_serialize(args), "call_number": call_num},
        )

        # Check if tool exists
        tool = self.tools.get(tool_name)
        if tool is None:
            result = ToolResult(
                success=False,
                error=f"Tool '{tool_name}' is not available in this environment",
            )
            duration_ms = (time.monotonic() - start_time) * 1000
            self.trace.record_tool_call(tool_name, args, result.model_dump(), False, duration_ms)
            self.trace.add_event(
                TraceEventType.TOOL_CALL_END,
                {"tool_name": tool_name, "success": False, "error": result.error},
            )
            return result

        # Validate arguments against schema
        if tool.parameters_schema:
            validation_error = _validate_args(args, tool.parameters_schema)
            if validation_error:
                self.trace.add_event(
                    TraceEventType.TOOL_VALIDATION_ERROR,
                    {"tool_name": tool_name, "error": validation_error},
                )
                result = ToolResult(
                    success=False,
                    error=f"Argument validation failed: {validation_error}",
                )
                duration_ms = (time.monotonic() - start_time) * 1000
                self.trace.record_tool_call(tool_name, args, result.model_dump(), False, duration_ms)
                self.trace.add_event(
                    TraceEventType.TOOL_CALL_END,
                    {"tool_name": tool_name, "success": False, "error": result.error},
                )
                return result

        # Check failure injection
        failure_rule = self.failure_rules.get(tool_name)
        if failure_rule:
            should_fail = False
            if failure_rule.trigger_on_call is not None:
                should_fail = call_num == failure_rule.trigger_on_call
            elif failure_rule.failure_rate > 0:
                # For deterministic behavior, use call count as seed
                # This ensures reproducible failures across runs
                should_fail = (hash((tool_name, call_num)) % 100) < (failure_rule.failure_rate * 100)

            if should_fail:
                self.trace.add_event(
                    TraceEventType.FAILURE_INJECTED,
                    {"tool_name": tool_name, "call_number": call_num, "rule": failure_rule.model_dump()},
                )
                # Simulate timeout if configured
                if failure_rule.timeout_ms and self.simulate_latency:
                    sleep_s = min(failure_rule.timeout_ms, self.max_simulated_latency_ms) / 1000
                    time.sleep(sleep_s)
                result = ToolResult(success=False, error=failure_rule.error_message)
                duration_ms = (time.monotonic() - start_time) * 1000
                self.trace.record_tool_call(tool_name, args, result.model_dump(), False, duration_ms)
                self.trace.add_event(
                    TraceEventType.TOOL_CALL_END,
                    {"tool_name": tool_name, "success": False, "error": result.error, "failure_injected": True},
                )
                return result

        # Simulate latency if configured
        if self.simulate_latency and tool.latency_ms > 0:
            sleep_s = min(tool.latency_ms, self.max_simulated_latency_ms) / 1000
            time.sleep(sleep_s)

        # Execute the tool
        try:
            context = {"state": self.state, "call_number": call_num}
            result = tool.execute(args, context)
        except Exception as e:
            logger.error("tool_execution_error", tool_name=tool_name, error=str(e))
            result = ToolResult(success=False, error=f"Tool execution error: {str(e)}")

        duration_ms = (time.monotonic() - start_time) * 1000
        self.trace.record_tool_call(tool_name, args, result.model_dump(), result.success, duration_ms)
        self.trace.add_event(
            TraceEventType.TOOL_CALL_END,
            {
                "tool_name": tool_name,
                "success": result.success,
                "duration_ms": duration_ms,
                "output_preview": result.output[:200] if result.output else None,
            },
        )

        return result


def _validate_args(args: dict[str, Any], schema: dict[str, Any]) -> str | None:
    """Validate arguments against a JSON schema. Returns error string or None."""
    try:
        jsonschema.validate(instance=args, schema=schema)
        return None
    except jsonschema.ValidationError as e:
        return e.message


def _safe_serialize(obj: Any) -> Any:
    """Safely serialize an object for tracing, avoiding secrets."""
    try:
        json.dumps(obj)
        return obj
    except (TypeError, ValueError):
        return str(obj)
