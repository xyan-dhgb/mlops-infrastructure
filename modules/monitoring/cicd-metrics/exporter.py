#!/usr/bin/env python3
"""Expose CI/CD pipeline metrics from S3-synced JSON reports in Prometheus format."""

from __future__ import annotations

import json
import math
import os
import threading
import time
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Dict, Iterable, List, Optional, Tuple

REPORTS_DIR = os.getenv("REPORTS_DIR", "/data/reports")
PORT = int(os.getenv("PORT", "8080"))
CACHE_TTL_SECONDS = int(os.getenv("CACHE_TTL_SECONDS", "60"))
WINDOWS_DAYS = (1, 7, 30)
REPORT_FILENAMES = ("ci-pipeline-metrics.json", "cd-apply-metrics.json")

CACHE_LOCK = threading.Lock()
CACHE_STATE = {
    "expires_at": 0.0,
    "payload": "",
    "refresh_timestamp": 0.0,
    "reports_loaded": 0,
}


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def parse_timestamp(raw: object) -> Optional[datetime]:
    if not raw or not isinstance(raw, str):
        return None

    normalized = raw[:-1] + "+00:00" if raw.endswith("Z") else raw

    try:
        value = datetime.fromisoformat(normalized)
    except ValueError:
        return None

    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)

    return value.astimezone(timezone.utc)


def escape_label(value: object) -> str:
    raw = "" if value is None else str(value)
    return raw.replace("\\", "\\\\").replace("\n", "\\n").replace('"', '\\"')


def metric_line(name: str, value: float, labels: Optional[Dict[str, object]] = None) -> str:
    if labels:
        rendered = ",".join(
            f'{key}="{escape_label(labels[key])}"' for key in sorted(labels)
        )
        return f"{name}{{{rendered}}} {value}"

    return f"{name} {value}"


def percentile(values: List[float], rank: float) -> Optional[float]:
    if not values:
        return None

    ordered = sorted(values)
    if len(ordered) == 1:
        return float(ordered[0])

    index = (len(ordered) - 1) * rank
    lower = math.floor(index)
    upper = math.ceil(index)

    if lower == upper:
        return float(ordered[int(index)])

    fraction = index - lower
    lower_value = ordered[lower]
    upper_value = ordered[upper]
    return float(lower_value + (upper_value - lower_value) * fraction)


def read_reports() -> List[dict]:
    reports: List[dict] = []

    if not os.path.isdir(REPORTS_DIR):
        return reports

    for root, _, files in os.walk(REPORTS_DIR):
        for report_name in REPORT_FILENAMES:
            if report_name not in files:
                continue

            report_path = os.path.join(root, report_name)
            try:
                with open(report_path, "r", encoding="utf-8") as handle:
                    payload = json.load(handle)
            except (OSError, json.JSONDecodeError):
                continue

            if isinstance(payload, dict) and payload.get("available", True):
                reports.append(payload)

    return reports


def to_float(value: object) -> Optional[float]:
    if isinstance(value, bool):
        return float(value)

    if isinstance(value, (int, float)) and math.isfinite(value):
        return float(value)

    return None


def aggregate_metrics(reports: Iterable[dict]) -> Tuple[str, int]:
    groups: Dict[Tuple[str, str, str], List[dict]] = {}

    for report in reports:
        repository = report.get("repository") or "unknown"
        workflow = report.get("workflow") or "unknown"
        branch = report.get("branch") or "unknown"
        groups.setdefault((repository, workflow, branch), []).append(report)

    lines = [
        "# HELP cicd_metrics_exporter_reports_loaded Number of CI/CD pipeline metric reports loaded from disk.",
        "# TYPE cicd_metrics_exporter_reports_loaded gauge",
        "# HELP cicd_metrics_exporter_last_refresh_timestamp_seconds Unix timestamp of the last successful metrics refresh.",
        "# TYPE cicd_metrics_exporter_last_refresh_timestamp_seconds gauge",
        "# HELP cicd_pipeline_runs_total Number of CI/CD pipeline runs observed in the selected time window.",
        "# TYPE cicd_pipeline_runs_total gauge",
        "# HELP cicd_pipeline_failed_runs_total Number of failed CI/CD pipeline runs observed in the selected time window.",
        "# TYPE cicd_pipeline_failed_runs_total gauge",
        "# HELP cicd_pipeline_success_rate Ratio of successful CI/CD pipeline runs in the selected time window.",
        "# TYPE cicd_pipeline_success_rate gauge",
        "# HELP cicd_automated_test_pass_rate Average automated test pass rate in the selected time window.",
        "# TYPE cicd_automated_test_pass_rate gauge",
        "# HELP cicd_pipeline_execution_time_seconds Pipeline execution time from commit to workflow completion in seconds.",
        "# TYPE cicd_pipeline_execution_time_seconds gauge",
        "# HELP cicd_plan_age_seconds Age of the plan artifact or source revision at pipeline completion time in seconds.",
        "# TYPE cicd_plan_age_seconds gauge",
        "# HELP cicd_pipeline_last_run_success Whether the latest observed CI/CD pipeline run succeeded (1) or failed (0).",
        "# TYPE cicd_pipeline_last_run_success gauge",
        "# HELP cicd_pipeline_last_run_timestamp_seconds Unix timestamp of the latest observed CI/CD pipeline completion.",
        "# TYPE cicd_pipeline_last_run_timestamp_seconds gauge",
        "# HELP cicd_checkov_failed_checks Latest observed count of failed Checkov checks.",
        "# TYPE cicd_checkov_failed_checks gauge",
    ]

    now = utc_now()
    reports_loaded = 0

    for (repository, workflow, branch), items in sorted(groups.items()):
        prepared = []
        for item in items:
            completed_at = parse_timestamp(item.get("completed_at"))
            if completed_at is None:
                continue

            prepared.append((completed_at, item))

        if not prepared:
            continue

        prepared.sort(key=lambda pair: pair[0])
        reports_loaded += len(prepared)

        latest_timestamp, latest = prepared[-1]
        base_labels = {
            "branch": branch,
            "repository": repository,
            "workflow": workflow,
        }

        latest_success = 1.0 if to_float(latest.get("pipeline_success")) == 1.0 else 0.0
        lines.append(metric_line("cicd_pipeline_last_run_success", latest_success, base_labels))
        lines.append(
            metric_line(
                "cicd_pipeline_last_run_timestamp_seconds",
                latest_timestamp.timestamp(),
                base_labels,
            )
        )

        latest_checkov_failures = to_float(latest.get("checkov_failures"))
        if latest_checkov_failures is not None:
            lines.append(metric_line("cicd_checkov_failed_checks", latest_checkov_failures, base_labels))

        latest_execution_time = to_float(latest.get("pipeline_execution_time_seconds"))
        if latest_execution_time is not None:
            lines.append(
                metric_line(
                    "cicd_pipeline_execution_time_seconds",
                    latest_execution_time,
                    {**base_labels, "stat": "latest", "window": "all"},
                )
            )

        latest_plan_age = to_float(latest.get("plan_age_seconds"))
        if latest_plan_age is not None:
            lines.append(
                metric_line(
                    "cicd_plan_age_seconds",
                    latest_plan_age,
                    {**base_labels, "stat": "latest", "window": "all"},
                )
            )

        for window_days in WINDOWS_DAYS:
            cutoff = now - timedelta(days=window_days)
            recent = [item for timestamp, item in prepared if timestamp >= cutoff]

            window_labels = {**base_labels, "window": f"{window_days}d"}
            runs_total = float(len(recent))
            failed_total = float(
                sum(1 for item in recent if to_float(item.get("pipeline_success")) != 1.0)
            )

            lines.append(metric_line("cicd_pipeline_runs_total", runs_total, window_labels))
            lines.append(metric_line("cicd_pipeline_failed_runs_total", failed_total, window_labels))

            if recent:
                lines.append(
                    metric_line(
                        "cicd_pipeline_success_rate",
                        (runs_total - failed_total) / runs_total,
                        window_labels,
                    )
                )

            pass_rates = [
                value
                for value in (to_float(item.get("automated_test_pass_rate")) for item in recent)
                if value is not None
            ]
            if pass_rates:
                lines.append(
                    metric_line(
                        "cicd_automated_test_pass_rate",
                        sum(pass_rates) / len(pass_rates),
                        window_labels,
                    )
                )

            execution_times = [
                value
                for value in (to_float(item.get("pipeline_execution_time_seconds")) for item in recent)
                if value is not None
            ]
            if execution_times:
                for stat, value in (
                    ("p50", percentile(execution_times, 0.50)),
                    ("p95", percentile(execution_times, 0.95)),
                ):
                    if value is not None:
                        lines.append(
                            metric_line(
                                "cicd_pipeline_execution_time_seconds",
                                value,
                                {**window_labels, "stat": stat},
                            )
                        )

            plan_ages = [
                value for value in (to_float(item.get("plan_age_seconds")) for item in recent) if value is not None
            ]
            if plan_ages:
                for stat, value in (
                    ("p50", percentile(plan_ages, 0.50)),
                    ("p95", percentile(plan_ages, 0.95)),
                ):
                    if value is not None:
                        lines.append(
                            metric_line(
                                "cicd_plan_age_seconds",
                                value,
                                {**window_labels, "stat": stat},
                            )
                        )

    refresh_timestamp = time.time()
    lines.append(metric_line("cicd_metrics_exporter_reports_loaded", float(reports_loaded)))
    lines.append(metric_line("cicd_metrics_exporter_last_refresh_timestamp_seconds", refresh_timestamp))
    lines.append("")

    return "\n".join(lines), reports_loaded


def get_cached_payload() -> str:
    now = time.time()

    with CACHE_LOCK:
        if now < CACHE_STATE["expires_at"] and CACHE_STATE["payload"]:
            return CACHE_STATE["payload"]

    payload, reports_loaded = aggregate_metrics(read_reports())

    with CACHE_LOCK:
        CACHE_STATE["payload"] = payload
        CACHE_STATE["expires_at"] = now + CACHE_TTL_SECONDS
        CACHE_STATE["refresh_timestamp"] = now
        CACHE_STATE["reports_loaded"] = reports_loaded

    return payload


class Handler(BaseHTTPRequestHandler):
    def do_GET(self) -> None:  # noqa: N802
        if self.path == "/-/ready":
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.end_headers()
            self.wfile.write(b"ready\n")
            return

        if self.path != "/metrics":
            self.send_response(404)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.end_headers()
            self.wfile.write(b"not found\n")
            return

        payload = get_cached_payload().encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, format_string: str, *args: object) -> None:
        return


def main() -> None:
    server = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    server.serve_forever()


if __name__ == "__main__":
    main()
