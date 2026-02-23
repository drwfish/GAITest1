"""FastAPI application factory.

Creates the FastAPI app with all routes, health checks, and metrics.
"""

from __future__ import annotations

from fastapi import FastAPI
from prometheus_client import CollectorRegistry, generate_latest, Counter, Histogram

from app.api.routes_runs import router as runs_router
from app.api.routes_suites import router as suites_router

# Prometheus metrics
PROM_REGISTRY = CollectorRegistry()
RUNS_STARTED = Counter(
    "eval_runs_started_total",
    "Total evaluation runs started",
    registry=PROM_REGISTRY,
)
RUNS_COMPLETED = Counter(
    "eval_runs_completed_total",
    "Total evaluation runs completed",
    registry=PROM_REGISTRY,
)
RUN_DURATION = Histogram(
    "eval_run_duration_seconds",
    "Duration of evaluation runs",
    registry=PROM_REGISTRY,
)


def create_app() -> FastAPI:
    """Create and configure the FastAPI application."""
    app = FastAPI(
        title="Agentic Tool-Use Evaluation API",
        description="API for running and managing agentic tool-use evaluations",
        version="0.1.0",
    )

    # Store metrics registry on app state for access in routes
    app.state.prom_registry = PROM_REGISTRY
    app.state.runs_started = RUNS_STARTED
    app.state.runs_completed = RUNS_COMPLETED
    app.state.run_duration = RUN_DURATION

    # In-memory run store (for service mode)
    app.state.runs = {}

    app.include_router(runs_router)
    app.include_router(suites_router)

    @app.get("/healthz", tags=["health"])
    async def healthz():
        return {"status": "ok"}

    @app.get("/metrics", tags=["observability"])
    async def metrics():
        from fastapi.responses import Response
        data = generate_latest(PROM_REGISTRY)
        return Response(content=data, media_type="text/plain; charset=utf-8")

    return app
