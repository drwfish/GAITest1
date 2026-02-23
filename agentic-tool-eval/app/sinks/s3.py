"""S3 result sink - writes results to an S3 bucket.

Enabled by environment variables:
- AWS_REGION
- S3_BUCKET
- S3_PREFIX

Does not hardcode credentials; relies on IAM role (e.g., IRSA on EKS).
"""

from __future__ import annotations

import json
import os
from datetime import datetime, timezone

import structlog

from app.schemas.results_schema import EvalRunResult
from app.sinks.base import ResultSink

logger = structlog.get_logger()


class S3Sink(ResultSink):
    """Write results to S3."""

    def __init__(
        self,
        bucket: str | None = None,
        prefix: str | None = None,
        region: str | None = None,
    ) -> None:
        self._bucket = bucket or os.environ.get("S3_BUCKET", "")
        self._prefix = prefix or os.environ.get("S3_PREFIX", "eval-results")
        self._region = region or os.environ.get("AWS_REGION", "us-east-1")

    def write(self, result: EvalRunResult) -> None:
        if not self._bucket:
            logger.warning("s3_sink_no_bucket", msg="S3_BUCKET not configured, skipping S3 sink")
            return

        try:
            import boto3

            s3_client = boto3.client("s3", region_name=self._region)

            timestamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
            key = f"{self._prefix}/{result.suite_id}/{timestamp}_{result.run_id}.json"

            data = result.model_dump(mode="json")
            body = json.dumps(data, indent=2, default=str)

            s3_client.put_object(
                Bucket=self._bucket,
                Key=key,
                Body=body.encode("utf-8"),
                ContentType="application/json",
            )
            logger.info("s3_sink_written", bucket=self._bucket, key=key)

        except ImportError:
            logger.error("s3_sink_boto3_missing", msg="boto3 not installed, cannot write to S3")
        except Exception as e:
            logger.error("s3_sink_error", error=str(e))
            raise
