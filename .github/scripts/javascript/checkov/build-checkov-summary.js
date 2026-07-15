'use strict';

const fs = require('fs');
const path = require('path');

const [, , inputPath, outputPath] = process.argv;

if (!inputPath || !outputPath) {
  console.error('Usage: node build-checkov-summary.js <input-checkov-json> <output-json>');
  process.exit(1);
}

const writeSummary = (summary) => {
  fs.mkdirSync(path.dirname(outputPath), { recursive: true });
  fs.writeFileSync(outputPath, `${JSON.stringify(summary, null, 2)}\n`, 'utf8');
};

if (!fs.existsSync(inputPath)) {
  writeSummary({
    available: false,
    reason: 'Checkov JSON report not found',
  });
  process.exit(0);
}

const toArray = (value) => {
  if (!value) {
    return [];
  }

  return Array.isArray(value) ? value : [value];
};

const readNumber = (value, fallback = 0) => {
  return typeof value === 'number' && Number.isFinite(value) ? value : fallback;
};

let raw;
try {
  raw = JSON.parse(fs.readFileSync(inputPath, 'utf8'));
} catch (_) {
  writeSummary({
    available: false,
    reason: 'Could not parse Checkov JSON report',
  });
  process.exit(0);
}

const reports = toArray(raw);

let passed = 0;
let failures = 0;
let skipped = 0;
let parsingErrors = 0;
let resourceCount = 0;
let checkovVersion = null;

const frameworks = new Set();
const topFailedChecks = [];

for (const report of reports) {
  if (!report || typeof report !== 'object') {
    continue;
  }

  if (report.check_type) {
    frameworks.add(report.check_type);
  }

  const summary = report.summary ?? {};
  const results = report.results ?? {};

  passed += readNumber(summary.passed, Array.isArray(results.passed_checks) ? results.passed_checks.length : 0);
  failures += readNumber(summary.failed, Array.isArray(results.failed_checks) ? results.failed_checks.length : 0);
  skipped += readNumber(summary.skipped, Array.isArray(results.skipped_checks) ? results.skipped_checks.length : 0);
  parsingErrors += readNumber(summary.parsing_errors, Array.isArray(results.parsing_errors) ? results.parsing_errors.length : 0);
  resourceCount += readNumber(summary.resource_count, 0);

  if (!checkovVersion && summary.checkov_version) {
    checkovVersion = summary.checkov_version;
  }

  const failedChecks = Array.isArray(results.failed_checks) ? results.failed_checks : [];
  for (const failedCheck of failedChecks) {
    if (topFailedChecks.length >= 10) {
      break;
    }

    topFailedChecks.push({
      check_id: failedCheck.check_id ?? failedCheck.bc_check_id ?? null,
      check_name: failedCheck.check_name ?? null,
      resource: failedCheck.resource ?? null,
      file_path: failedCheck.file_path ?? failedCheck.repo_file_path ?? null,
      severity: failedCheck.severity ?? null,
      guideline: failedCheck.guideline ?? null,
    });
  }
}

const executed = passed + failures;
const tests = passed + failures + skipped;

writeSummary({
  available: true,
  generated_at: new Date().toISOString(),
  repository: process.env.GITHUB_REPOSITORY ?? null,
  workflow: process.env.GITHUB_WORKFLOW ?? null,
  job: process.env.GITHUB_JOB ?? null,
  event_name: process.env.GITHUB_EVENT_NAME ?? null,
  ref: process.env.GITHUB_REF ?? null,
  ref_name: process.env.GITHUB_REF_NAME ?? process.env.GITHUB_HEAD_REF ?? null,
  sha: process.env.GITHUB_SHA ?? null,
  actor: process.env.GITHUB_ACTOR ?? null,
  run_id: process.env.GITHUB_RUN_ID ?? null,
  run_attempt: process.env.GITHUB_RUN_ATTEMPT ?? null,
  checkov_outcome: process.env.CHECKOV_OUTCOME ?? null,
  checkov_version: checkovVersion ?? process.env.CHECKOV_VERSION ?? null,
  frameworks: Array.from(frameworks),
  resource_count: resourceCount,
  parsing_errors: parsingErrors,
  tests,
  failures,
  skipped,
  passed,
  executed,
  pass_rate: executed === 0 ? null : Number((passed / executed).toFixed(4)),
  artifact_name: process.env.CHECKOV_ARTIFACT_NAME ?? null,
  s3_uri: process.env.CHECKOV_REPORTS_S3_URI ?? null,
  top_failed_checks: topFailedChecks,
});
