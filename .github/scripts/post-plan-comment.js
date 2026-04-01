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
 * PLAN_FILE        - path to the plan text file (default: environments/dev/plan.txt)
 */
module.exports = async ({ github, context }) => {
  const fmt = process.env.FMT_OUTCOME;
  const validate = process.env.VALIDATE_OUTCOME;
  const plan = process.env.PLAN_OUTCOME;
  const sha = process.env.COMMIT_SHA;
  const planFile = process.env.PLAN_FILE ?? 'environments/dev/plan.txt';

  const icon = (outcome) =>
    outcome === 'success' ? '✅' : outcome === 'failure' ? '❌' : '⚠️';

  let planText = '(could not read plan output)';
  try {
    const raw = fs.readFileSync(planFile, 'utf8');
    const MAX = 65000;
    planText = raw.length > MAX ? raw.substring(0, MAX) + '\n...(truncated)' : raw;
  } catch (_) { }

  const statusSection =
    plan === 'success'
      ? `> ✅ **Plan OK.** To apply, run the workflow [Terraform Apply](../.github/workflows/terraform-apply.yml) with:\n` +
      `> - **Environment:** \`dev\`\n` +
      `> - **Plan Commit SHA:** \`${sha}\``
      : `> ❌ **Plan FAILED.** Please check the output above and fix the error before merging.`;

  const body = [
    '## Terraform Plan — DEV Environment',
    '',
    '| Step     | Result |',
    '|----------|--------|',
    `| Format   | ${icon(fmt)} \`${fmt}\` |`,
    `| Validate | ${icon(validate)} \`${validate}\` |`,
    `| Plan     | ${icon(plan)} \`${plan}\` |`,
    '',
    '<details><summary>📄 Show Plan Output</summary>',
    '',
    '```hcl',
    planText,
    '```',
    '</details>',
    '',
    '---',
    statusSection,
    '',
    `> *Commit: \`${sha}\`*`,
  ].join('\n');

  const { data: comments } = await github.rest.issues.listComments({
    owner: context.repo.owner,
    repo: context.repo.repo,
    issue_number: context.issue.number,
  });

  const existing = comments.find(
    (c) => c.user.type === 'Bot' && c.body.includes('Terraform Plan — DEV Environment')
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
