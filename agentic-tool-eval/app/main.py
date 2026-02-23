"""Main entry point for the agentic-tool-eval application.

This module serves as the top-level entry point. When run as a module,
it delegates to the Typer CLI app.
"""

from app.cli.main import app

if __name__ == "__main__":
    app()
