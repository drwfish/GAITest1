"""Unit tests for built-in tools."""

from app.tools.builtin.calculator import CalculatorTool
from app.tools.builtin.search import SearchTool
from app.tools.builtin.kb import KnowledgeBaseTool
from app.tools.builtin.time_tool import TimeTool
from app.tools.builtin.disallowed import DisallowedTool
from app.tools.builtin.slow_accurate import SlowAccurateTool
from app.tools.builtin.fast_approx import FastApproxTool
from app.tools.builtin.sqlite_query import SqliteQueryTool


class TestCalculatorTool:
    def test_basic_addition(self):
        tool = CalculatorTool()
        result = tool.execute({"expression": "2 + 3"})
        assert result.success
        assert result.output == "5"

    def test_complex_expression(self):
        tool = CalculatorTool()
        result = tool.execute({"expression": "sqrt(144)"})
        assert result.success
        assert result.output == "12"

    def test_division_by_zero(self):
        tool = CalculatorTool()
        result = tool.execute({"expression": "1/0"})
        assert not result.success

    def test_invalid_expression(self):
        tool = CalculatorTool()
        result = tool.execute({"expression": "import os"})
        assert not result.success


class TestSearchTool:
    def test_search_returns_results(self):
        tool = SearchTool()
        result = tool.execute({"query": "renewable energy"})
        assert result.success
        assert result.structured_output.get("total", 0) > 0

    def test_search_no_results(self):
        tool = SearchTool()
        result = tool.execute({"query": "xyznonexistentterm12345"})
        assert result.success

    def test_search_top_k(self):
        tool = SearchTool()
        result = tool.execute({"query": "technology", "top_k": 2})
        assert result.success
        assert len(result.structured_output.get("results", [])) <= 2


class TestKnowledgeBaseTool:
    def test_known_key(self):
        tool = KnowledgeBaseTool()
        result = tool.execute({"key": "capital_of_france"})
        assert result.success
        assert "Paris" in result.output

    def test_unknown_key(self):
        tool = KnowledgeBaseTool()
        result = tool.execute({"key": "nonexistent_key_12345"})
        assert not result.success

    def test_list_keys(self):
        tool = KnowledgeBaseTool()
        result = tool.execute({"key": "", "action": "list_keys"})
        assert result.success
        assert result.structured_output.get("count", 0) > 0


class TestTimeTool:
    def test_iso_format(self):
        tool = TimeTool()
        result = tool.execute({"format": "iso"})
        assert result.success
        assert "2025" in result.output

    def test_unix_format(self):
        tool = TimeTool()
        result = tool.execute({"format": "unix"})
        assert result.success
        assert result.output.isdigit()

    def test_human_format(self):
        tool = TimeTool()
        result = tool.execute({"format": "human"})
        assert result.success
        assert "January" in result.output or "2025" in result.output


class TestDisallowedTool:
    def test_returns_violation(self):
        tool = DisallowedTool()
        result = tool.execute({"action": "read_secrets"})
        assert result.success  # Tool executes but records violation
        assert "VIOLATION" in result.output
        assert result.structured_output.get("violation") is True


class TestSlowAccurateTool:
    def test_get_metric(self):
        tool = SlowAccurateTool()
        result = tool.execute({"metric": "revenue_q1"})
        assert result.success
        assert result.structured_output.get("precision") == "exact"

    def test_unknown_metric(self):
        tool = SlowAccurateTool()
        result = tool.execute({"metric": "nonexistent"})
        assert not result.success


class TestFastApproxTool:
    def test_get_metric(self):
        tool = FastApproxTool()
        result = tool.execute({"metric": "revenue_q1"})
        assert result.success
        assert result.structured_output.get("precision") == "approximate"


class TestSqliteQueryTool:
    def test_select_query(self):
        tool = SqliteQueryTool()
        result = tool.execute({"query": "SELECT COUNT(*) as cnt FROM employees"})
        assert result.success
        assert result.structured_output.get("row_count", 0) > 0

    def test_reject_insert(self):
        tool = SqliteQueryTool()
        result = tool.execute({"query": "INSERT INTO employees VALUES (99, 'test', 'test', 0, '2025-01-01')"})
        assert not result.success

    def test_reject_drop(self):
        tool = SqliteQueryTool()
        result = tool.execute({"query": "DROP TABLE employees"})
        assert not result.success
