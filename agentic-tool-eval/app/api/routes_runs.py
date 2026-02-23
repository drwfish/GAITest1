"""API routes for evaluation runs."""

from __future__ import annotations

import threading
import uuid
from datetime import datetime, timezone
from typing import Any

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field

from app.schemas.results_schema import EvalRunResult, RunInfo, RunStatus

router = APIRouter(prefix="/runs", tags=["runs"])


class RunRequest(BaseModel):
    suite_id: str
    agent_adapter: str = "heuristic"
    agent_config: dict[str, Any] = Field(default_factory=dict)
    simulate_latency: bool = False
    judge_enabled: bool = False


class RunResponse(BaseModel):
    run_id: str


@router.post("", response_model=RunResponse)
async def create_run(body: RunRequest, request: Request):
    """Start a new evaluation run (async)."""
    run_id = str(uuid.uuid4())

    # Store initial run info
    run_info = RunInfo(
        run_id=run_id,
        suite_id=body.suite_id,
        agent_id=body.agent_adapter,
        status=RunStatus.PENDING,
        started_at=datetime.now(timezone.utc),
    )
    request.app.state.runs[run_id] = {
        "info": run_info,
        "result": None,
    }

    # Update Prometheus metrics
    request.app.state.runs_started.inc()

    # Run in background thread
    thread = threading.Thread(
        target=_run_eval,
        args=(run_id, body, request.app),
        daemon=True,
    )
    thread.start()

    return RunResponse(run_id=run_id)


@router.get("/{run_id}")
async def get_run(run_id: str, request: Request):
    """Get run status and summary."""
    run_data = request.app.state.runs.get(run_id)
    if run_data is None:
        raise HTTPException(status_code=404, detail=f"Run {run_id} not found")

    info: RunInfo = run_data["info"]
    return info.model_dump(mode="json")


@router.get("/{run_id}/results")
async def get_run_results(run_id: str, request: Request):
    """Get full results for a completed run."""
    run_data = request.app.state.runs.get(run_id)
    if run_data is None:
        raise HTTPException(status_code=404, detail=f"Run {run_id} not found")

    result: EvalRunResult | None = run_data.get("result")
    if result is None:
        info: RunInfo = run_data["info"]
        if info.status == RunStatus.RUNNING:
            raise HTTPException(status_code=202, detail="Run still in progress")
        elif info.status == RunStatus.FAILED:
            raise HTTPException(status_code=500, detail="Run failed")
        else:
            raise HTTPException(status_code=202, detail="Run not yet started")

    return result.model_dump(mode="json")


def _run_eval(run_id: str, body: RunRequest, app: Any) -> None:
    """Execute evaluation in a background thread."""
    import time

    from app.agents.echo import EchoAgent
    from app.agents.heuristic import HeuristicAgent
    from app.agents.http_adapter import HTTPAgentAdapter
    from app.core.orchestrator import Orchestrator
    from app.core.registry import build_default_registry
    from app.schemas.results_schema import RunConfig
    from app.scoring.composite import CompositeScorer

    run_data = app.state.runs[run_id]
    run_data["info"].status = RunStatus.RUNNING

    start_time = time.monotonic()

    try:
        # Build agent
        if body.agent_adapter == "echo":
            agent = EchoAgent()
        elif body.agent_adapter == "heuristic":
            agent = HeuristicAgent()
        elif body.agent_adapter == "http":
            url = body.agent_config.get("url", "")
            if not url:
                raise ValueError("agent_config.url is required for http adapter")
            agent = HTTPAgentAdapter(
                url=url,
                headers=body.agent_config.get("headers"),
            )
        else:
            raise ValueError(f"Unknown adapter: {body.agent_adapter}")

        orchestrator = Orchestrator(
            registry=build_default_registry(),
            scorers=CompositeScorer(judge_enabled=body.judge_enabled),
            simulate_latency=body.simulate_latency,
        )

        suite = orchestrator.load_suite(body.suite_id)
        run_config = RunConfig(
            suite_id=body.suite_id,
            agent_adapter=body.agent_adapter,
            agent_config=body.agent_config,
            judge_enabled=body.judge_enabled,
        )

        result = orchestrator.run_suite(suite, agent, run_config)
        result.run_id = run_id

        run_data["result"] = result
        run_data["info"].status = RunStatus.COMPLETED
        run_data["info"].finished_at = datetime.now(timezone.utc)
        run_data["info"].summary = result.summary

        duration = time.monotonic() - start_time
        app.state.runs_completed.inc()
        app.state.run_duration.observe(duration)

    except Exception as e:
        run_data["info"].status = RunStatus.FAILED
        run_data["info"].finished_at = datetime.now(timezone.utc)
        import structlog
        structlog.get_logger().error("run_failed", run_id=run_id, error=str(e))
