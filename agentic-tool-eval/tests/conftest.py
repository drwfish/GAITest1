"""Shared test fixtures."""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

# Ensure the app package is importable
sys.path.insert(0, str(Path(__file__).parent.parent))


@pytest.fixture
def registry():
    """Build a default tool registry."""
    from app.core.registry import build_default_registry
    return build_default_registry()


@pytest.fixture
def orchestrator():
    """Build a default orchestrator."""
    from app.core.orchestrator import Orchestrator
    from app.core.registry import build_default_registry
    from app.scoring.composite import CompositeScorer

    return Orchestrator(
        registry=build_default_registry(),
        scorers=CompositeScorer(),
    )
