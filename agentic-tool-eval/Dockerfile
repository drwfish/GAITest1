# Multi-stage Dockerfile for agentic-tool-eval
# Runs as non-root, minimal image, no secrets in logs

# ---- Build stage ----
FROM python:3.11-slim AS builder

WORKDIR /build

# Install build dependencies
COPY pyproject.toml ./
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir hatchling && \
    pip wheel --no-cache-dir --wheel-dir /wheels -e .

# ---- Runtime stage ----
FROM python:3.11-slim AS runtime

# Security: create non-root user
RUN groupadd -r evaluser && useradd -r -g evaluser -d /app -s /sbin/nologin evaluser

WORKDIR /app

# Install runtime dependencies from wheels
COPY --from=builder /wheels /wheels
RUN pip install --no-cache-dir /wheels/*.whl && \
    rm -rf /wheels

# Copy application code
COPY app/ /app/app/
COPY pyproject.toml /app/

# Seed the database (deterministic, no external deps)
RUN python -m app.resources.db.seed_db || true

# Create results directory
RUN mkdir -p /results && chown evaluser:evaluser /results

# Security: switch to non-root user
USER evaluser

# Expose port for FastAPI service mode
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/healthz')" || exit 1

# Entrypoint: supports both service and batch modes
# Usage:
#   docker run <image> serve               -> starts HTTP API
#   docker run <image> run --suite <id>     -> runs batch eval
#   docker run <image> list-suites          -> lists available suites
#   docker run <image> replay --trace <p>   -> replays a trace
ENTRYPOINT ["python", "-m", "app.cli.main"]
CMD ["serve", "--host", "0.0.0.0", "--port", "8080"]
