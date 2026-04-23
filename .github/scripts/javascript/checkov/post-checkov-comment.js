'use strict';

const fs = require('fs');

const formatPercent = (value) => {
  if (typeof value !== 'number') {
    return 'n/a';
  }

  return `${(value * 100).toFixed(2)}%`;
};

const statusEmoji = (value) => {
  if (value === 'success') {
    return '✅';
  }

  if (value === 'failure') {
    return '⚠️';
  }

  if (value === 'skipped') {
    return '⏭️';
  }

  return '❔';
};

module.exports = async ({ github, context }) => {
  const checkovOutcome = process.env.CHECKOV_OUTCOME ?? 'unknown';
  const summaryFile = process.env.CHECKOV_SUMMARY_FILE ?? 'reports/checkov-summary.json';
  const artifactName = process.env.CHECKOV_ARTIFACT_NAME ?? null;

  let summary = null;
  try {
    const raw = fs.readFileSync(summaryFile, 'utf8');
    summary = JSON.parse(raw);
  } catch (_) {
    summary = {
      available: false,
      reason: 'Could not read Checkov summary file',
    };
  }

  const body = [];
  body.push('## 🔍 Checkov Scan - DEV Environment');
  body.push('');

  if (!summary.available) {
    body.push(`> ⚠️ Checkov summary is unavailable: ${summary.reason ?? 'unknown reason'}`);
  } else {
    body.push('> 🟡 Report-only mode: Checkov findings are logged, commented, and stored in S3, but they do not fail this CI run.');
    body.push('');
    body.push('| Metric | Value |');
    body.push('|--------|-------|');
    body.push(`| Outcome | ${statusEmoji(checkovOutcome)} \`${checkovOutcome}\` |`);
    body.push(`| Passed checks | \`${summary.passed}\` |`);
    body.push(`| Failed checks | \`${summary.failures}\` |`);
    body.push(`| Skipped checks | \`${summary.skipped}\` |`);
    body.push(`| Executed checks | \`${summary.executed}\` |`);
    body.push(`| Pass rate | \`${formatPercent(summary.pass_rate)}\` |`);
    body.push(`| Checkov version | \`${summary.checkov_version ?? 'unknown'}\` |`);

    if (artifactName) {
      body.push(`| JUnit artifact | \`${artifactName}\` |`);
    }

    if (summary.s3_uri) {
      body.push(`| CLI log (S3) | \`${summary.s3_uri}/checkov-cli.log\` |`);
      body.push(`| JSON report (S3) | \`${summary.s3_uri}/checkov.json\` |`);
      body.push(`| Summary JSON (S3) | \`${summary.s3_uri}/checkov-summary.json\` |`);
    }

    if (Array.isArray(summary.top_failed_checks) && summary.top_failed_checks.length > 0) {
      body.push('');
      body.push('### ⚠️ Top Failed Checks');
      body.push('');

      for (const item of summary.top_failed_checks.slice(0, 5)) {
        const severity = item.severity ? `[${item.severity}] ` : '';
        const checkId = item.check_id ?? 'unknown-check';
        const checkName = item.check_name ?? 'Unnamed check';
        const resource = item.resource ? ` on \`${item.resource}\`` : '';
        const filePath = item.file_path ? ` in \`${item.file_path}\`` : '';
        body.push(`- ${severity}\`${checkId}\` ${checkName}${resource}${filePath}`);
      }
    }
  }

  const { data: comments } = await github.rest.issues.listComments({
    owner: context.repo.owner,
    repo: context.repo.repo,
    issue_number: context.issue.number,
  });

  const existing = comments.find(
    (comment) => comment.user.type === 'Bot' && comment.body.includes('Checkov Scan - DEV Environment')
  );

  if (existing) {
    await github.rest.issues.updateComment({
      owner: context.repo.owner,
      repo: context.repo.repo,
      comment_id: existing.id,
      body: body.join('\n'),
    });
  } else {
    await github.rest.issues.createComment({
      owner: context.repo.owner,
      repo: context.repo.repo,
      issue_number: context.issue.number,
      body: body.join('\n'),
    });
  }
};
