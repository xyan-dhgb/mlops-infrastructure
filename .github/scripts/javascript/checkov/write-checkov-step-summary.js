'use strict';

const fs = require('fs');

const [, , summaryPath] = process.argv;

if (!summaryPath) {
  console.error('Usage: node write-checkov-step-summary.js <summary-json>');
  process.exit(1);
}

const formatPercent = (value) => {
  if (typeof value !== 'number') {
    return 'n/a';
  }

  return `${(value * 100).toFixed(2)}%`;
};

const summary = JSON.parse(fs.readFileSync(summaryPath, 'utf8'));

if (!summary.available) {
  console.log('## Checkov Summary');
  console.log('');
  console.log(`Checkov summary is unavailable: ${summary.reason ?? 'unknown reason'}`);
  process.exit(0);
}

console.log('## Checkov Summary');
console.log('');
console.log('| Metric | Value |');
console.log('|--------|-------|');
console.log(`| Outcome | \`${summary.checkov_outcome ?? 'unknown'}\` |`);
console.log(`| Passed checks | \`${summary.passed}\` |`);
console.log(`| Failed checks | \`${summary.failures}\` |`);
console.log(`| Skipped checks | \`${summary.skipped}\` |`);
console.log(`| Executed checks | \`${summary.executed}\` |`);
console.log(`| Pass rate | \`${formatPercent(summary.pass_rate)}\` |`);
console.log(`| Checkov version | \`${summary.checkov_version ?? 'unknown'}\` |`);

if (summary.s3_uri) {
  console.log(`| CLI log in S3 | \`${summary.s3_uri}/checkov-cli.log\` |`);
  console.log(`| Raw JSON in S3 | \`${summary.s3_uri}/checkov.json\` |`);
}

if (summary.artifact_name) {
  console.log(`| JUnit artifact | \`${summary.artifact_name}\` |`);
}

if (Array.isArray(summary.top_failed_checks) && summary.top_failed_checks.length > 0) {
  console.log('');
  console.log('### Top Failed Checks');
  console.log('');

  for (const item of summary.top_failed_checks.slice(0, 5)) {
    const severity = item.severity ? `[${item.severity}] ` : '';
    const checkId = item.check_id ?? 'unknown-check';
    const checkName = item.check_name ?? 'Unnamed check';
    const resource = item.resource ? ` on \`${item.resource}\`` : '';
    const filePath = item.file_path ? ` in \`${item.file_path}\`` : '';
    console.log(`- ${severity}\`${checkId}\` ${checkName}${resource}${filePath}`);
  }
}
