"""Tool registry for managing available tools.

The ToolRegistry loads tools from:
- Built-in Python modules (app.tools.builtin.*)
- A configured plugins directory
- Explicit registration via register()

It supports creating subsets (toolsets) for specific tasks.
"""

from __future__ import annotations

import importlib
import pkgutil
from pathlib import Path
from typing import Any

import structlog

from app.tools.base import BaseTool

logger = structlog.get_logger()


class ToolRegistry:
    """Registry of all available tools."""

    def __init__(self) -> None:
        self._tools: dict[str, BaseTool] = {}

    def register(self, tool: BaseTool) -> None:
        """Register a tool. Raises ValueError if name already registered."""
        if tool.name in self._tools:
            raise ValueError(f"Tool '{tool.name}' is already registered")
        self._tools[tool.name] = tool
        logger.debug("tool_registered", tool_name=tool.name)

    def get(self, name: str) -> BaseTool | None:
        return self._tools.get(name)

    def list_tools(self) -> list[str]:
        return sorted(self._tools.keys())

    def get_all(self) -> dict[str, BaseTool]:
        return dict(self._tools)

    def get_subset(self, names: list[str]) -> dict[str, BaseTool]:
        """Return a subset of tools by name."""
        subset = {}
        for name in names:
            tool = self._tools.get(name)
            if tool is not None:
                subset[name] = tool
        return subset

    def get_schemas(self, names: list[str] | None = None) -> list[dict[str, Any]]:
        """Get tool schemas for a subset (or all) tools."""
        if names is None:
            tools = self._tools.values()
        else:
            tools = [self._tools[n] for n in names if n in self._tools]
        return [t.get_schema() for t in tools]

    def load_builtin_tools(self) -> None:
        """Discover and load all built-in tools from app.tools.builtin."""
        import app.tools.builtin as builtin_pkg

        for _importer, modname, _ispkg in pkgutil.iter_modules(builtin_pkg.__path__):
            module = importlib.import_module(f"app.tools.builtin.{modname}")
            # Each module should define a function get_tools() -> list[BaseTool]
            if hasattr(module, "get_tools"):
                for tool in module.get_tools():
                    if tool.name not in self._tools:
                        self.register(tool)
            else:
                logger.warning("builtin_module_no_get_tools", module=modname)

    def load_plugins_dir(self, plugins_dir: str | Path) -> None:
        """Load tools from a plugins directory.

        Each .py file in the directory should define get_tools() -> list[BaseTool].
        """
        plugins_path = Path(plugins_dir)
        if not plugins_path.is_dir():
            logger.warning("plugins_dir_not_found", path=str(plugins_path))
            return

        for py_file in sorted(plugins_path.glob("*.py")):
            if py_file.name.startswith("_"):
                continue
            spec = importlib.util.spec_from_file_location(py_file.stem, py_file)
            if spec is None or spec.loader is None:
                continue
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            if hasattr(module, "get_tools"):
                for tool in module.get_tools():
                    if tool.name not in self._tools:
                        self.register(tool)


# Predefined toolset configurations mapping toolset_id -> list of tool names.
# Tasks reference a toolset_id; the environment resolves it to actual tool instances.
TOOLSET_CONFIGS: dict[str, list[str]] = {
    "basic": [
        "calculator", "search", "knowledge_base", "time",
    ],
    "full": [
        "calculator", "search", "sqlite_query", "knowledge_base",
        "file_read", "time", "slow_accurate", "fast_approx",
    ],
    "with_disallowed": [
        "calculator", "search", "knowledge_base", "time", "disallowed",
    ],
    "calculator_only": ["calculator"],
    "search_only": ["search"],
    "sqlite_only": ["sqlite_query"],
    "cost_tradeoff": ["slow_accurate", "fast_approx"],
    "multi_tool": [
        "calculator", "search", "sqlite_query", "knowledge_base",
        "file_read", "time",
    ],
    "safety_test": [
        "calculator", "search", "knowledge_base", "time", "disallowed",
    ],
    "empty": [],
}


def build_default_registry() -> ToolRegistry:
    """Create a registry with all built-in tools loaded."""
    registry = ToolRegistry()
    registry.load_builtin_tools()
    return registry
