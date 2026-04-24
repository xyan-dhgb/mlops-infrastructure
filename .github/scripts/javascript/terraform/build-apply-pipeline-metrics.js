'use strict';

const fs = require('fs');
const path = require('path');

const [, , outputPath] = process.argv;

if (!outputPath) {
  console.error('Usage: node build-apply-pipeline-metrics.js <output-json>');
  process.exit(1);
}

const parseTimestamp = (value) => {
  if (!value) {
    return null;
  }

  const millis = Date.parse(value);
  return Number.isFinite(millis) ? millis : null;
};

const secondsBetween = (startValue, endValue) => {
  const start = parseTimestamp(startValue);
  const end = parseTimestamp(endValue);

  if (start === null || end === null || end < start) {
    return null;
  }

  return Number(((end - start) / 1000).toFixed(2));
};

const completedAt = new Date().toISOString();

const envOutcome = (name) => {
  const value = process.env[name];
  return value && value.trim() ? value.trim() : 'unknown';
};

const stepOutcomes = {
  verify_branch: envOutcome('VERIFY_BRANCH_OUTCOME'),
  init: envOutcome('INIT_OUTCOME'),
  download_plan: envOutcome('DOWNLOAD_PLAN_OUTCOME'),
  verify_plan: envOutcome('VERIFY_PLAN_OUTCOME'),
  import: envOutcome('IMPORT_OUTCOME'),
  apply: envOutcome('APPLY_OUTCOME'),
};

const requiredBlockingSteps = ['verify_branch', 'init', 'download_plan', 'verify_plan', 'import', 'apply'];
const pipelineSuccess = requiredBlockingSteps.every((stepName) => stepOutcomes[stepName] === 'success');

const output = {
  available: true,
  generated_at: completedAt,
  repository: process.env.GITHUB_REPOSITORY ?? null,
  workflow: process.env.GITHUB_WORKFLOW ?? null,
  job: process.env.PIPELINE_JOB_NAME ?? process.env.GITHUB_JOB ?? null,
  event_name: process.env.GITHUB_EVENT_NAME ?? null,
  environment: process.env.ENVIRONMENT_NAME ?? null,
  branch: process.env.PIPELINE_BRANCH ?? process.env.GITHUB_REF_NAME ?? null,
  sha: process.env.PIPELINE_SHA ?? process.env.GITHUB_SHA ?? null,
  actor: process.env.GITHUB_ACTOR ?? null,
  run_id: process.env.GITHUB_RUN_ID ?? null,
  run_attempt: process.env.GITHUB_RUN_ATTEMPT ?? null,
  run_started_at: process.env.RUN_STARTED_AT ?? null,
  completed_at: completedAt,
  plan_commit_sha: process.env.PLAN_COMMIT_SHA ?? null,
  plan_commit_timestamp: process.env.PLAN_COMMIT_TIMESTAMP ?? null,
  pipeline_execution_time_seconds: secondsBetween(process.env.RUN_STARTED_AT, completedAt),
  workflow_duration_seconds: secondsBetween(process.env.RUN_STARTED_AT, completedAt),
  plan_age_seconds: secondsBetween(process.env.PLAN_COMMIT_TIMESTAMP, completedAt),
  pipeline_success: pipelineSuccess ? 1 : 0,
  pipeline_status: pipelineSuccess ? 'success' : 'failure',
  infra_validation_result: process.env.APPLY_JOB_RESULT ?? null,
  automated_test_pass_rate: null,
  checkov_outcome: null,
  checkov_failures: null,
  checkov_passed: null,
  checkov_executed: null,
  checkov_artifact_name: null,
  steps: stepOutcomes,
};

fs.mkdirSync(path.dirname(outputPath), { recursive: true });
fs.writeFileSync(outputPath, `${JSON.stringify(output, null, 2)}\n`, 'utf8');
