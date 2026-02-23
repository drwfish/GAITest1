"""Tests for the FastAPI service."""

import pytest
from fastapi.testclient import TestClient

from app.api.server import create_app


@pytest.fixture
def client():
    app = create_app()
    return TestClient(app)


class TestHealthEndpoint:
    def test_healthz(self, client):
        response = client.get("/healthz")
        assert response.status_code == 200
        assert response.json()["status"] == "ok"


class TestSuitesEndpoint:
    def test_list_suites(self, client):
        response = client.get("/suites")
        assert response.status_code == 200
        data = response.json()
        assert "suites" in data
        assert len(data["suites"]) >= 7


class TestAgentProtocol:
    def test_agent_protocol_schema(self, client):
        response = client.get("/agent-protocol")
        assert response.status_code == 200
        data = response.json()
        assert "components" in data
        assert "schemas" in data["components"]
        assert "AgentRequest" in data["components"]["schemas"]
        assert "AgentResponse" in data["components"]["schemas"]


class TestMetricsEndpoint:
    def test_metrics(self, client):
        response = client.get("/metrics")
        assert response.status_code == 200
        assert "eval_runs_started_total" in response.text
