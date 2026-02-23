"""Search tool - queries a local corpus and returns top-k hits.

The corpus is a JSON file with an array of documents, each having
'id', 'title', 'content', and optional 'tags' fields.
Search is performed via simple keyword matching (TF-IDF-like scoring).
No external network access is required.
"""

from __future__ import annotations

import json
import re
from collections import Counter
from math import log
from pathlib import Path
from typing import Any

from app.tools.base import BaseTool, ToolResult

DEFAULT_CORPUS_PATH = str(Path(__file__).parent.parent.parent / "resources" / "corpora" / "search_corpus.json")


class SearchTool(BaseTool):
    name = "search"
    description = "Search a knowledge corpus for relevant documents. Returns top-k results matching the query."
    parameters_schema = {
        "type": "object",
        "properties": {
            "query": {
                "type": "string",
                "description": "Search query string",
            },
            "top_k": {
                "type": "integer",
                "description": "Number of results to return (default 5)",
                "default": 5,
                "minimum": 1,
                "maximum": 20,
            },
        },
        "required": ["query"],
    }
    cost = 1.0
    latency_ms = 200.0

    def __init__(self, corpus_path: str | None = None) -> None:
        self._corpus_path = corpus_path or DEFAULT_CORPUS_PATH
        self._corpus: list[dict[str, Any]] | None = None

    def _load_corpus(self) -> list[dict[str, Any]]:
        if self._corpus is None:
            try:
                with open(self._corpus_path, "r") as f:
                    self._corpus = json.load(f)
            except FileNotFoundError:
                self._corpus = []
        return self._corpus

    def execute(self, args: dict[str, Any], context: dict[str, Any] | None = None) -> ToolResult:
        query = args.get("query", "")
        top_k = args.get("top_k", 5)

        corpus = self._load_corpus()
        if not corpus:
            return ToolResult(
                success=True,
                output="No results found.",
                structured_output={"results": [], "total": 0},
            )

        # Tokenize query
        query_tokens = _tokenize(query)
        if not query_tokens:
            return ToolResult(
                success=True,
                output="No results found.",
                structured_output={"results": [], "total": 0},
            )

        # Score documents
        scored = []
        doc_count = len(corpus)
        # Compute IDF
        doc_freq: Counter[str] = Counter()
        for doc in corpus:
            tokens = set(_tokenize(doc.get("title", "") + " " + doc.get("content", "")))
            for t in tokens:
                doc_freq[t] += 1

        for doc in corpus:
            text = doc.get("title", "") + " " + doc.get("content", "")
            doc_tokens = _tokenize(text)
            if not doc_tokens:
                continue
            token_counts = Counter(doc_tokens)
            score = 0.0
            for qt in query_tokens:
                tf = token_counts.get(qt, 0) / len(doc_tokens)
                idf = log((doc_count + 1) / (doc_freq.get(qt, 0) + 1))
                score += tf * idf
            if score > 0:
                scored.append((score, doc))

        scored.sort(key=lambda x: x[0], reverse=True)
        results = scored[:top_k]

        formatted_results = []
        output_lines = []
        for i, (score, doc) in enumerate(results, 1):
            entry = {
                "rank": i,
                "id": doc.get("id", ""),
                "title": doc.get("title", ""),
                "snippet": doc.get("content", "")[:200],
                "score": round(score, 4),
            }
            formatted_results.append(entry)
            output_lines.append(f"{i}. [{entry['id']}] {entry['title']}: {entry['snippet']}")

        output_text = "\n".join(output_lines) if output_lines else "No results found."
        return ToolResult(
            success=True,
            output=output_text,
            structured_output={"results": formatted_results, "total": len(results)},
        )


def _tokenize(text: str) -> list[str]:
    """Simple tokenization: lowercase, split on non-alphanumeric."""
    return [t for t in re.split(r"[^a-z0-9]+", text.lower()) if t]


def get_tools() -> list[BaseTool]:
    return [SearchTool()]
