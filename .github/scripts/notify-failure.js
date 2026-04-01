'use strict';

/**
 * Creates a GitHub Issue to notify about a Terraform workflow failure.
 *
 * Required env vars (set in the workflow step):
 * TF_ENVIRONMENT - target environment (e.g. "dev", "prod")
 * WORKFLOW_TYPE  - "apply" | "destroy"
 *
 * For WORKFLOW_TYPE=apply:
 * APPLY_OUTCOME  - outcome of the apply step
 * VERIFY_OUTCOME - outcome of the verify step (optional)
 *
 * For WORKFLOW_TYPE=destroy:
 * REF_NAME       - the branch name (e.g. "dev")
 */
module.exports = async ({ github, context }) => {
  const sha = context.sha.substring(0, 7);
  const runUrl = `${context.serverUrl}/${context.repo.owner}/${context.repo.repo}/actions/runs/${context.runId}`;
  const environment = process.env.TF_ENVIRONMENT;
  const workflowType = process.env.WORKFLOW_TYPE;

  let title, body;

  if (workflowType === 'apply') {
    const applyOutcome = process.env.APPLY_OUTCOME;
    const verifyOutcome = process.env.VERIFY_OUTCOME;

    let failReason = 'Unknown failure — check the run log.';
    if (applyOutcome === 'failure') {
      failReason = '`terraform apply` failed. Check output in run log.';
    } else if (verifyOutcome === 'failure') {
      failReason =
        '`terraform apply` succeeded but **ingress-nginx is not healthy**. ' +
        'Run `helm status ingress-nginx -n ingress-nginx` to investigate.';
    }

    title = `❌ Terraform Apply FAILED on ${environment} — ${sha}`;
    body = [
      '## Terraform Apply Failed',
      '',
      `**Environment:** \`${environment}\``,
      '**Branch:** `dev`',
      `**Commit:** \`${context.sha}\``,
      `**Triggered by:** \`${context.actor}\``,
      '',
      `**Nguyên nhân:** ${failReason}`,
      '',
      `[🔗 View failed run](${runUrl})`,
      '',
      '> Kiểm tra và fix trước khi deploy lại.',
    ].join('\n');
  } else {
    title = `Terraform Destroy FAILED on ${environment} — ${sha}`;
    body = [
      '## Terraform Destroy Failed',
      '',
      `**Environment:** \`${environment}\``,
      `**Branch:** \`${process.env.REF_NAME}\``,
      `**Commit:** \`${context.sha}\``,
      `**Triggered by:** \`${context.actor}\``,
      '',
      `[View failed run](${runUrl})`,
      '',
      '> Infrastructure may be in a partial state. Manual intervention required.',
    ].join('\n');
  }

  await github.rest.issues.create({
    owner: context.repo.owner,
    repo: context.repo.repo,
    title,
    body,
    labels: ['terraform', 'infrastructure', 'bug'],
  });
};
