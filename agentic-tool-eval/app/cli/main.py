"""CLI entry point using Typer.

Commands:
- list-suites: Show available evaluation suites
- run: Execute an eval suite against an agent
- serve: Start the HTTP API server
- replay: Re-score a stored trace
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

import structlog
import typer

# Configure structured logging
structlog.configure(
    processors=[
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.add_log_level,
        structlog.processors.JSONRenderer(),
    ],
    wrapper_class=structlog.BoundLogger,
    context_class=dict,
    logger_factory=structlog.PrintLoggerFactory(file=sys.stderr),
)

logger = structlog.get_logger()
app = typer.Typer(
    name="agentic-tool-eval",
    help="Agentic Tool-Use Evaluation Framework",
)


def _build_sinks(sink_names: str, file_path: str | None = None) -> list:
    """Build result sinks from configuration."""
    from app.sinks.stdout import StdoutSink
    from app.sinks.file import FileSink
    from app.sinks.s3 import S3Sink
    from app.sinks.http import HttpSink

    sinks = []
    for name in sink_names.split(","):
        name = name.strip().lower()
        if name == "stdout":
            sinks.append(StdoutSink())
        elif name == "file":
            sinks.append(FileSink(path=file_path or "/results/results.jsonl"))
        elif name == "s3":
            sinks.append(S3Sink())
        elif name == "http":
            sinks.append(HttpSink())
    return sinks


def _build_agent(adapter: str, agent_url: str | None = None, agent_config: str | None = None):
    """Build an agent from adapter name and config."""
    from app.agents.echo import EchoAgent
    from app.agents.heuristic import HeuristicAgent
    from app.agents.http_adapter import HTTPAgentAdapter

    if adapter == "echo":
        return EchoAgent()
    elif adapter == "heuristic":
        return HeuristicAgent()
    elif adapter == "http":
        if not agent_url:
            typer.echo("Error: --agent-url is required for http adapter", err=True)
            raise typer.Exit(1)
        headers = {}
        if agent_config:
            config = json.loads(agent_config)
            headers = config.get("headers", {})
        return HTTPAgentAdapter(url=agent_url, headers=headers)
    else:
        typer.echo(f"Error: Unknown adapter '{adapter}'", err=True)
        raise typer.Exit(1)


@app.command("list-suites")
def list_suites():
    """List available evaluation suites."""
    from app.core.orchestrator import Orchestrator

    orchestrator = Orchestrator()
    suites = orchestrator.list_suites()

    if not suites:
        typer.echo("No suites found.")
        return

    typer.echo(f"{'Suite ID':<45} {'Task Files':>10}")
    typer.echo("-" * 57)
    for s in suites:
        typer.echo(f"{s['id']:<45} {s['task_files']:>10}")


@app.command("run")
def run(
    suite: str = typer.Option(..., "--suite", help="Suite ID to run"),
    agent_adapter: str = typer.Option("heuristic", "--agent-adapter", help="Agent adapter: echo, heuristic, http"),
    agent_url: str | None = typer.Option(None, "--agent-url", help="URL for HTTP agent adapter"),
    agent_config: str | None = typer.Option(None, "--agent-config", help="JSON config for agent adapter"),
    out: str | None = typer.Option(None, "--out", help="Output file path for results JSON"),
    sinks: str = typer.Option(
        os.environ.get("RESULTS_SINKS", "stdout"),
        "--sinks",
        help="Comma-separated list of sinks: stdout,file,s3,http",
    ),
    file_path: str | None = typer.Option(
        os.environ.get("RESULTS_FILE_PATH"),
        "--file-path",
        help="File path for file sink",
    ),
    threshold: float = typer.Option(0.0, "--threshold", help="Minimum pass rate (0-1). Exit non-zero if below."),
    simulate_latency: bool = typer.Option(False, "--simulate-latency", help="Simulate tool latency"),
):
    """Run an evaluation suite."""
    from app.core.orchestrator import Orchestrator
    from app.core.registry import build_default_registry
    from app.schemas.results_schema import RunConfig
    from app.scoring.composite import CompositeScorer

    agent = _build_agent(agent_adapter, agent_url, agent_config)
    result_sinks = _build_sinks(sinks, file_path)

    orchestrator = Orchestrator(
        registry=build_default_registry(),
        scorers=CompositeScorer(),
        sinks=result_sinks,
        simulate_latency=simulate_latency,
    )

    try:
        suite_obj = orchestrator.load_suite(suite)
    except FileNotFoundError as e:
        typer.echo(f"Error: {e}", err=True)
        raise typer.Exit(1)

    run_config = RunConfig(
        suite_id=suite,
        agent_adapter=agent_adapter,
        agent_config=json.loads(agent_config) if agent_config else {},
    )

    result = orchestrator.run_suite(suite_obj, agent, run_config)

    # Write to explicit output file if specified
    if out:
        Path(out).parent.mkdir(parents=True, exist_ok=True)
        with open(out, "w") as f:
            f.write(result.model_dump_json(indent=2))
        logger.info("results_written", path=out)

    # Print summary to stderr
    summary = result.summary
    if summary:
        typer.echo(
            f"\nSuite: {suite}\n"
            f"Agent: {agent_adapter}\n"
            f"Tasks: {summary.total_tasks}\n"
            f"Passed: {summary.passed_tasks}\n"
            f"Failed: {summary.failed_tasks}\n"
            f"Errors: {summary.error_tasks}\n"
            f"Pass Rate: {summary.pass_rate:.2%}\n"
            f"Overall Score: {summary.overall_score:.4f}\n",
            err=True,
        )

    # Exit non-zero if below threshold
    if threshold > 0 and summary and summary.pass_rate < threshold:
        logger.warning("threshold_not_met", pass_rate=summary.pass_rate, threshold=threshold)
        raise typer.Exit(1)


@app.command("serve")
def serve(
    host: str = typer.Option("0.0.0.0", "--host", help="Host to bind to"),
    port: int = typer.Option(8080, "--port", help="Port to listen on"),
):
    """Start the HTTP API server."""
    import uvicorn
    uvicorn.run(
        "app.api.server:create_app",
        host=host,
        port=port,
        factory=True,
        log_level="info",
    )


@app.command("replay")
def replay(
    trace_path: str = typer.Option(..., "--trace", help="Path to trace JSON file"),
    task_path: str | None = typer.Option(None, "--task", help="Path to task YAML file"),
    out: str | None = typer.Option(None, "--out", help="Output file path for results JSON"),
):
    """Re-score a stored trace without agent access."""
    from app.core.replay import replay_from_files

    if not task_path:
        typer.echo("Error: --task is required for replay", err=True)
        raise typer.Exit(1)

    result = replay_from_files(trace_path, task_path=task_path)

    output = result.model_dump_json(indent=2)
    if out:
        Path(out).parent.mkdir(parents=True, exist_ok=True)
        with open(out, "w") as f:
            f.write(output)
        typer.echo(f"Replay results written to {out}", err=True)
    else:
        typer.echo(output)


if __name__ == "__main__":
    app()
