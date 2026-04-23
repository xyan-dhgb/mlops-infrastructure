'use strict';

const fs = require('fs');

/**
 * Posts (or updates) a Terraform plan comment on a GitHub PR.
 *
 * Required env vars (set in the workflow step):
 * FMT_OUTCOME      - outcome of the fmt step
 * VALIDATE_OUTCOME - outcome of the validate step
 * PLAN_OUTCOME     - outcome of the plan step
 * COMMIT_SHA       - the commit SHA for this run
 * PLAN_FILE        - path to the plan text file
 */
module.exports = async ({ github, context }) => {
  const fmt = process.env.FMT_OUTCOME;
  const validate = process.env.VALIDATE_OUTCOME;
  const plan = process.env.PLAN_OUTCOME;
  const sha = process.env.COMMIT_SHA;
  const planFile = process.env.PLAN_FILE ?? 'environments/dev/plan.txt';

  const icon = (outcome) =>
    outcome === 'success' ? 'OK' : outcome === 'failure' ? 'FAIL' : 'WARN';

  let planText = '(could not read plan output)';
  try {
    const raw = fs.readFileSync(planFile, 'utf8');
    const maxLength = 65000;
    planText = raw.length > maxLength ? `${raw.substring(0, maxLength)}\n...(truncated)` : raw;
  } catch (_) {
    // Keep the fallback text above.
  }

  const statusSection =
    plan === 'success'
      ? `> OK **Plan OK.** To apply, run the workflow [Terraform Apply](../.github/workflows/terraform-apply.yml) with:\n` +
        `> - **Environment:** \`dev\`\n` +
        `> - **Plan Commit SHA:** \`${sha}\``
      : '> FAIL **Plan failed.** Please check the plan output and fix the issue before merging.';

  const resultRows = [
    '| Step     | Result |',
    '|----------|--------|',
    `| Format   | ${icon(fmt)} \`${fmt}\` |`,
    `| Validate | ${icon(validate)} \`${validate}\` |`,
    `| Plan     | ${icon(plan)} \`${plan}\` |`,
  ];

  const body = [
    '## Terraform Plan - DEV Environment',
    '',
    ...resultRows,
    '',
    '<details><summary>Show plan output</summary>',
    '',
    '```hcl',
    planText,
    '```',
    '</details>',
    '',
    '---',
    statusSection,
    '',
    `> Commit: \`${sha}\``,
  ]
    .filter(Boolean)
    .join('\n');

  const { data: comments } = await github.rest.issues.listComments({
    owner: context.repo.owner,
    repo: context.repo.repo,
    issue_number: context.issue.number,
  });

  const existing = comments.find(
    (comment) => comment.user.type === 'Bot' && comment.body.includes('Terraform Plan')
  );

  if (existing) {
    await github.rest.issues.updateComment({
      owner: context.repo.owner,
      repo: context.repo.repo,
      comment_id: existing.id,
      body,
    });
  } else {
    await github.rest.issues.createComment({
      owner: context.repo.owner,
      repo: context.repo.repo,
      issue_number: context.issue.number,
      body,
    });
  }
};
