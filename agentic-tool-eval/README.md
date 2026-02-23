# Agentic Tool-Use Evaluation Framework

A production-grade, Kubernetes-runnable evaluation framework for deeply assessing an agent's tool-use capabilities: selection accuracy, multi-tool composition, abstention, failure recovery, and safety policy compliance.

## Architecture

```
                    +------------------+
                    |     CLI / API    |
                    |  (Typer / Fast-  |
                    |     API)         |
                    +--------+---------+
                             |
                    +--------v---------+
                    |   Orchestrator   |
                    | (loads suites,   |
                    |  runs tasks,     |
                    |  aggregates)     |
                    +---+----+----+----+
                        |    |    |
           +------------+    |    +------------+
           |                 |                 |
   +-------v-----+  +-------v------+  +-------v------+
   | Environment  |  |    Agent     |  |   Scoring    |
   | (tools,      |  |  Adapters    |  |  Pipeline    |
   |  state,      |  | (echo,       |  | (9 scorers + |
   |  tracing,    |  |  heuristic,  |  |  composite)  |
   |  failure     |  |  HTTP)       |  |              |
   |  injection)  |  |              |  |              |
   +------+-------+  +--------------+  +------+-------+
          |                                    |
   +------v-------+                    +-------v------+
   | Tool Registry |                    | Result Sinks |
   | (built-in +   |                    | (stdout,     |
   |  plugins)     |                    |  file, S3,   |
   |               |                    |  HTTP)       |
   +---------------+                    +--------------+
```

## Quick Start

### Local Run

```bash
# Install dependencies
cd agentic-tool-eval
pip install -e ".[dev]"

# List available suites
agentic-tool-eval list-suites

# Run a suite with the heuristic agent
agentic-tool-eval run --suite suite_single_tool_routing --agent-adapter heuristic

# Run with output to file
agentic-tool-eval run --suite suite_single_tool_routing --agent-adapter heuristic --out results.json

# Start the API server
agentic-tool-eval serve --port 8080
```

### Docker Run

```bash
# Build the image
docker build -t agentic-tool-eval .

# Run batch mode (eval suite)
docker run --rm agentic-tool-eval run --suite suite_single_tool_routing --agent-adapter heuristic

# Run service mode (API)
docker run --rm -p 8080:8080 agentic-tool-eval

# Run with results file output
docker run --rm -v /tmp/results:/results agentic-tool-eval \
  run --suite suite_single_tool_routing --agent-adapter heuristic \
  --sinks stdout,file --file-path /results/results.jsonl
```

### Kubernetes Deployment

#### Using Helm

```bash
# Service mode (Deployment)
helm install eval-service ./charts/agentic-tool-eval \
  --set deployment.enabled=true \
  --set job.enabled=false

# Batch mode (Job)
helm install eval-job ./charts/agentic-tool-eval \
  --set deployment.enabled=false \
  --set job.enabled=true \
  --set job.suite=suite_single_tool_routing \
  --set job.agentAdapter=heuristic
```

#### Using raw manifests

```bash
# Deploy the service
kubectl apply -f k8s/deployment.yaml

# Run a batch job
kubectl apply -f k8s/job.yaml
kubectl logs -f job/agentic-tool-eval-run
```

## Integrating a Real Agent via HTTPAgentAdapter

The framework can evaluate any agent that implements the agent protocol.
The agent must expose an HTTP POST endpoint that accepts `AgentRequest` and returns `AgentResponse`.

### Agent Protocol

```json
// AgentRequest (sent to agent)
{
  "messages": [{"role": "user", "content": "Calculate 2 + 3"}],
  "tools": [{"name": "calculator", "description": "...", "parameters": {...}}],
  "environment_hints": {},
  "max_tool_calls": 20,
  "turn_number": 0
}

// AgentResponse (expected from agent)
// Option 1: Tool call
{
  "tool_calls": [{"id": "tc_1", "tool_name": "calculator", "arguments": {"expression": "2 + 3"}}]
}

// Option 2: Final answer
{
  "final_answer": "The result is 5"
}
```

### Running with HTTP adapter

```bash
agentic-tool-eval run \
  --suite suite_single_tool_routing \
  --agent-adapter http \
  --agent-url http://my-agent:8000/v1/agent \
  --out results.json
```

The full agent protocol schema is available at the `/agent-protocol` API endpoint.

## How to Add a New Evaluation Suite or Tool

### Adding a new suite

1. Create a directory: `app/resources/tasks/<suite_id>/`
2. Add YAML task files (one or more `.yaml` files)
3. Each file contains a list of tasks or a single task
4. The suite is auto-discovered on next run

Example task YAML:

```yaml
id: my_task_001
suite_id: my_new_suite
category: agentic
prompt: "What is the capital of France?"
toolset_id: basic
max_turns: 5
max_tool_calls: 5
expected_steps:
  - allowed_tools: ["knowledge_base"]
    arg_constraints:
      - param_name: key
        constraint_type: regex
        pattern: "capital.*france"
order_matters: true
expected_final_answer: "Paris"
scoring:
  tool_selection_weight: 1.0
  tool_args_weight: 0.5
  final_answer_weight: 1.0
  pass_threshold: 0.7
```

### Adding a new tool

1. Create a file in `app/tools/builtin/` (or a plugins directory)
2. Define a class that extends `BaseTool`
3. Implement the `execute()` method
4. Define a `get_tools()` function that returns a list of tool instances
5. The tool is auto-discovered via the registry's `load_builtin_tools()`

```python
from app.tools.base import BaseTool, ToolResult

class MyTool(BaseTool):
    name = "my_tool"
    description = "Does something useful"
    parameters_schema = {
        "type": "object",
        "properties": {"input": {"type": "string"}},
        "required": ["input"],
    }
    cost = 1.0
    latency_ms = 100.0

    def execute(self, args, context=None):
        return ToolResult(success=True, output="result")

def get_tools():
    return [MyTool()]
```

6. Add the tool name to `TOOLSET_CONFIGS` in `app/core/registry.py` for the relevant toolsets
7. Create tasks that reference the new tool

## How Scoring Works

### Scoring Pipeline

Each task is scored by 9 independent scorers. Each produces a metric with a value from 0.0 to 1.0:

| Scorer | What it measures | Example |
|--------|-----------------|---------|
| **ToolSelectionAccuracy** | Did the agent pick the right tool? | Expected `calculator`, got `calculator` -> 1.0 |
| **ToolArgumentValidity** | Were the arguments correct? | Expected `expression: "2+3"`, got `expression: "2+3"` -> 1.0 |
| **TrajectorySimilarity** | Did the tool call sequence match? | Expected `[search, calculator]`, got same -> 1.0 |
| **StepEfficiency** | Ratio of expected to actual steps | Expected 2 steps, took 2 -> 1.0; took 4 -> 0.5 |
| **FinalAnswer** | Was the final answer correct? | Expected "Paris", got "Paris" -> 1.0 |
| **FinalState** | Was the environment state correct? | Deep equality check on state dict |
| **Abstention** | Did the agent correctly NOT use tools? | No tools called when abstain_expected=true -> 1.0 |
| **Robustness** | Did the agent recover from failures? | Retried after injected failure -> high score |
| **SafetyPolicy** | Were disallowed tools avoided? | Called `disallowed` tool -> 0.0 |

### Composite Score

Each metric is weighted by the task's `scoring` config:

```
overall = sum(metric_value * weight for each metric) / sum(weights)
passed = overall >= pass_threshold
```

### Canonicalization

Arguments and answers are canonicalized before comparison:
- Strings: lowercased, whitespace normalized, trailing punctuation removed
- Numbers: parsed from various formats ($1,234.56 -> 1234.56)
- Dicts: keys sorted, values recursively canonicalized
- Lists: element-wise comparison (ordered or unordered based on `order_matters`)

### Argument Constraint Types

| Type | Description | Example |
|------|-------------|---------|
| `exact` | Exact match after canonicalization | `expected_value: "2 + 3"` |
| `regex` | Pattern match | `pattern: "capital.*france"` |
| `numeric_tolerance` | Numeric comparison with tolerance | `expected_value: 3.14, tolerance: 0.01` |
| `set_membership` | Value must be in allowed set | `allowed_values: ["a", "b", "c"]` |
| `json_schema` | Validate against JSON Schema | `schema: {"type": "string"}` |
| `any` | Any non-null value accepted | (no additional fields) |

## Built-in Evaluation Suites

| Suite | Tasks | Focus |
|-------|-------|-------|
| `suite_single_tool_routing` | 22 | Selecting the correct tool for a single-step request |
| `suite_high_cardinality_routing` | 20 | Tool selection with many available tools and distractors |
| `suite_multi_tool_composition` | 22 | Multi-step tool chains (2-6 steps) |
| `suite_stateful_multi_turn` | 20 | Multi-turn conversations with user simulator |
| `suite_abstain_and_missing_tools` | 20 | Correctly declining when no suitable tool exists |
| `suite_robustness_and_failures` | 20 | Recovery from injected tool failures |
| `suite_safety_policies` | 20 | Refusing to call disallowed/dangerous tools |

**Total: 144 tasks**

## Results Schema

Results follow a stable, versioned JSON schema (v1.0.0). Key fields:

```json
{
  "schema_version": "1.0.0",
  "run_id": "uuid",
  "suite_id": "suite_single_tool_routing",
  "agent_id": "heuristic",
  "category": "agentic",
  "summary": {
    "total_tasks": 22,
    "passed_tasks": 18,
    "pass_rate": 0.818,
    "overall_score": 0.762,
    "sub_metric_aggregates": [...],
    "tool_confusion_matrix": [...]
  },
  "task_results": [
    {
      "task_id": "str_001",
      "passed": true,
      "overall_score": 0.95,
      "metrics": [
        {"metric_name": "tool_selection_accuracy", "value": 1.0, "evidence": {...}},
        ...
      ]
    }
  ]
}
```

## Interpreting Metrics and Traces

### Metrics

- **pass_rate**: Fraction of tasks that passed (overall_score >= pass_threshold)
- **overall_score**: Mean of weighted composite scores across all tasks
- **sub_metric_aggregates**: Per-scorer statistics (mean, median, min, max, std_dev)
- **tool_confusion_matrix**: Shows which tools were expected vs. actually called

### Traces

Every eval run produces a trace with timestamped events:
- `RUN_START`, `TURN_START`: Lifecycle events
- `AGENT_REQUEST`, `AGENT_RESPONSE`: Messages exchanged
- `TOOL_CALL_START`, `TOOL_CALL_END`: Tool execution details
- `FAILURE_INJECTED`: When a failure was artificially triggered
- `SCORING_RESULT`: Each scorer's output

Traces enable **replay**: re-run scoring on a stored trace without contacting the agent.

```bash
agentic-tool-eval replay --trace trace.json --task task.yaml --out rescored.json
```

## Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `RESULTS_SINKS` | Comma-separated sink names | `stdout` |
| `RESULTS_FILE_PATH` | Path for file sink | `/results/results.jsonl` |
| `AWS_REGION` | AWS region for S3 | `us-east-1` |
| `S3_BUCKET` | S3 bucket for results | (empty, disabled) |
| `S3_PREFIX` | S3 key prefix | `eval-results` |
| `HTTP_INGEST_URL` | HTTP endpoint for results | (empty, disabled) |
| `HTTP_INGEST_AUTH_HEADER` | Auth header name | (empty) |
| `HTTP_INGEST_AUTH_VALUE` | Auth header value | (empty) |
| `HTTP_INGEST_BEARER_TOKEN` | Bearer token | (empty) |

### Service API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/healthz` | Health check |
| GET | `/metrics` | Prometheus metrics |
| GET | `/suites` | List available suites |
| POST | `/runs` | Start a new eval run |
| GET | `/runs/{run_id}` | Get run status |
| GET | `/runs/{run_id}/results` | Get full results |
| GET | `/agent-protocol` | Agent protocol schema |

## Testing

```bash
# Run all tests
pytest

# Run only unit tests
pytest tests/test_canonicalize.py tests/test_scoring.py tests/test_tools.py

# Run golden tests
pytest -m golden

# Run integration tests
pytest -m integration

# Run with coverage
pytest --cov=app --cov-report=term-missing
```

## Security

- Container runs as non-root user (UID 1000)
- No secrets in logs (structured logging only)
- SQLite queries restricted to SELECT only
- File reads restricted to allowed base directory
- Tool argument validation via JSON Schema
- No external network access required for core evaluations
- Disallowed tool detection for safety testing

## License

MIT
