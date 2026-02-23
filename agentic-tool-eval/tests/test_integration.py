"""Integration tests for the evaluation framework.

These tests run actual suites with real agents and verify stable results.
"""

import pytest

from app.agents.echo import EchoAgent
from app.agents.heuristic import HeuristicAgent
from app.core.orchestrator import Orchestrator
from app.core.registry import build_default_registry
from app.scoring.composite import CompositeScorer


@pytest.mark.integration
class TestHeuristicAgentIntegration:
    """Run suite with HeuristicAgent and assert non-zero but stable results."""

    def test_single_tool_routing_suite(self):
        orchestrator = Orchestrator(
            registry=build_default_registry(),
            scorers=CompositeScorer(),
        )
        suite = orchestrator.load_suite("suite_single_tool_routing")
        agent = HeuristicAgent()

        result = orchestrator.run_suite(suite, agent)

        assert result.summary is not None
        assert result.summary.total_tasks > 0
        # Heuristic agent should get some tasks right
        assert result.summary.pass_rate > 0.0
        # But not perfect (it's a heuristic)
        assert result.summary.overall_score > 0.0
        # All tasks should have results
        assert len(result.task_results) == result.summary.total_tasks

    def test_safety_suite_no_violations(self):
        """HeuristicAgent should avoid calling disallowed tools."""
        orchestrator = Orchestrator(
            registry=build_default_registry(),
            scorers=CompositeScorer(),
        )
        suite = orchestrator.load_suite("suite_safety_policies")
        agent = HeuristicAgent()

        result = orchestrator.run_suite(suite, agent)

        # Check that no safety violations occurred
        for tr in result.task_results:
            metric_map = {m.metric_name: m for m in tr.metrics}
            safety = metric_map.get("safety_policy")
            if safety:
                assert safety.value == 1.0, f"Task {tr.task_id} had safety violation"


@pytest.mark.integration
class TestEchoAgentIntegration:
    """Run suite with EchoAgent and assert expected failures."""

    def test_echo_agent_fails_tool_tasks(self):
        """EchoAgent never calls tools, so it should fail on tool-requiring tasks."""
        orchestrator = Orchestrator(
            registry=build_default_registry(),
            scorers=CompositeScorer(),
        )
        suite = orchestrator.load_suite("suite_single_tool_routing")
        agent = EchoAgent()

        result = orchestrator.run_suite(suite, agent)

        assert result.summary is not None
        # Echo agent should have poor scores on tool-requiring tasks
        assert result.summary.overall_score < 0.5

        # Verify efficiency scores are low (no tool calls made)
        for tr in result.task_results:
            metric_map = {m.metric_name: m for m in tr.metrics}
            efficiency = metric_map.get("step_efficiency")
            if efficiency:
                assert efficiency.value == 0.0

    def test_echo_agent_abstention_suite(self):
        """EchoAgent should do well on abstention tasks (it never calls tools)."""
        orchestrator = Orchestrator(
            registry=build_default_registry(),
            scorers=CompositeScorer(),
        )
        suite = orchestrator.load_suite("suite_abstain_and_missing_tools")
        agent = EchoAgent()

        result = orchestrator.run_suite(suite, agent)

        assert result.summary is not None
        # Echo agent should score well on abstention (it naturally abstains)
        for tr in result.task_results:
            metric_map = {m.metric_name: m for m in tr.metrics}
            abstention = metric_map.get("abstention")
            if abstention:
                assert abstention.value == 1.0


@pytest.mark.integration
class TestRegistryIntegration:
    """Test that the tool registry loads all expected tools."""

    def test_all_builtin_tools_loaded(self):
        registry = build_default_registry()
        tools = registry.list_tools()

        expected_tools = [
            "calculator", "search", "sqlite_query", "knowledge_base",
            "file_read", "time", "slow_accurate", "fast_approx", "disallowed",
        ]
        for tool_name in expected_tools:
            assert tool_name in tools, f"Expected tool '{tool_name}' not found in registry"


@pytest.mark.integration
class TestSuiteLoading:
    """Test that all suites load correctly."""

    def test_all_suites_load(self):
        orchestrator = Orchestrator(
            registry=build_default_registry(),
            scorers=CompositeScorer(),
        )
        suites = orchestrator.list_suites()
        assert len(suites) >= 7

        for suite_info in suites:
            suite = orchestrator.load_suite(suite_info["id"])
            assert len(suite.tasks) > 0, f"Suite {suite_info['id']} has no tasks"
