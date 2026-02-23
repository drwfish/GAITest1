"""API routes for listing evaluation suites."""

from __future__ import annotations

from fastapi import APIRouter

from app.core.orchestrator import Orchestrator
from app.schemas.agent_protocol import get_agent_protocol_schema

router = APIRouter(tags=["suites"])


@router.get("/suites")
async def list_suites():
    """List all available evaluation suites."""
    orchestrator = Orchestrator()
    suites = orchestrator.list_suites()
    return {"suites": suites}


@router.get("/agent-protocol")
async def agent_protocol():
    """Return the agent protocol schema (OpenAPI-compatible)."""
    return get_agent_protocol_schema()
