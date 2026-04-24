'use strict';

const fs = require('fs');
const path = require('path');

const [, , outputPath] = process.argv;

if (!outputPath) {
  console.error('Usage: node build-ci-pipeline-metrics.js <output-json>');
  process.exit(1);
}

const readJson = (filePath) => {
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch (_) {
    return null;
  }
};

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
const summaryFile = process.env.CHECKOV_SUMMARY_FILE ?? 'reports/checkov-summary.json';
const checkovSummary = readJson(summaryFile);

const stepOutcomes = {
  init: process.env.INIT_OUTCOME ?? 'unknown',
  import: process.env.IMPORT_OUTCOME ?? 'unknown',
  fmt: process.env.FMT_OUTCOME ?? 'unknown',
  validate: process.env.VALIDATE_OUTCOME ?? 'unknown',
  plan: process.env.PLAN_OUTCOME ?? 'unknown',
  checkov: process.env.CHECKOV_OUTCOME ?? 'unknown',
};

const requiredBlockingSteps = ['init', 'import', 'fmt', 'validate', 'plan'];
const pipelineSuccess = requiredBlockingSteps.every((stepName) => stepOutcomes[stepName] === 'success');

const output = {
  available: true,
  generated_at: completedAt,
  repository: process.env.GITHUB_REPOSITORY ?? null,
  workflow: process.env.GITHUB_WORKFLOW ?? null,
  job: process.env.PIPELINE_JOB_NAME ?? process.env.GITHUB_JOB ?? null,
  event_name: process.env.GITHUB_EVENT_NAME ?? null,
  environment: process.env.ENVIRONMENT_NAME ?? null,
  branch: process.env.PIPELINE_BRANCH ?? process.env.GITHUB_HEAD_REF ?? process.env.GITHUB_REF_NAME ?? null,
  sha: process.env.PIPELINE_SHA ?? process.env.GITHUB_SHA ?? null,
  actor: process.env.GITHUB_ACTOR ?? null,
  run_id: process.env.GITHUB_RUN_ID ?? null,
  run_attempt: process.env.GITHUB_RUN_ATTEMPT ?? null,
  commit_timestamp: process.env.COMMIT_TIMESTAMP ?? null,
  run_started_at: process.env.RUN_STARTED_AT ?? null,
  completed_at: completedAt,
  pipeline_execution_time_seconds: secondsBetween(process.env.COMMIT_TIMESTAMP, completedAt),
  workflow_duration_seconds: secondsBetween(process.env.RUN_STARTED_AT, completedAt),
  pipeline_success: pipelineSuccess ? 1 : 0,
  pipeline_status: pipelineSuccess ? 'success' : 'failure',
  infra_validation_result: process.env.INFRA_VALIDATION_RESULT ?? null,
  automated_test_pass_rate: checkovSummary?.available ? checkovSummary.pass_rate ?? null : null,
  checkov_outcome: stepOutcomes.checkov,
  checkov_failures: checkovSummary?.available ? checkovSummary.failures ?? null : null,
  checkov_passed: checkovSummary?.available ? checkovSummary.passed ?? null : null,
  checkov_executed: checkovSummary?.available ? checkovSummary.executed ?? null : null,
  checkov_artifact_name: checkovSummary?.available ? checkovSummary.artifact_name ?? null : null,
  steps: stepOutcomes,
};

fs.mkdirSync(path.dirname(outputPath), { recursive: true });
fs.writeFileSync(outputPath, `${JSON.stringify(output, null, 2)}\n`, 'utf8');
