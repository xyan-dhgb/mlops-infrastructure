'use strict';

/**
 * Creates a GitHub Issue to notify about a Terraform workflow failure.
 *
 * Required env vars (set in the workflow step):
 * TF_ENVIRONMENT - target environment (e.g. "dev", "prod")
 * WORKFLOW_TYPE  - "apply" | "destroy"
 *
 * For WORKFLOW_TYPE=apply:
 * VERIFY_BRANCH_OUTCOME - outcome of the branch guard step
 * INIT_OUTCOME          - outcome of terraform init
 * DOWNLOAD_PLAN_OUTCOME - outcome of the plan download step
 * VERIFY_PLAN_OUTCOME   - outcome of the plan verification step
 * IMPORT_OUTCOME        - outcome of the import step
 * APPLY_OUTCOME         - outcome of terraform apply
 *
 * For WORKFLOW_TYPE=destroy:
 * REF_NAME - the branch name (e.g. "dev")
 */
module.exports = async ({ github, context }) => {
  const sha = context.sha.substring(0, 7);
  const runUrl = `${context.serverUrl}/${context.repo.owner}/${context.repo.repo}/actions/runs/${context.runId}`;
  const environment = process.env.TF_ENVIRONMENT;
  const workflowType = process.env.WORKFLOW_TYPE;
  const branch = context.ref.replace('refs/heads/', '');

  let title;
  let body;

  if (workflowType === 'apply') {
    const verifyBranchOutcome = process.env.VERIFY_BRANCH_OUTCOME;
    const initOutcome = process.env.INIT_OUTCOME;
    const downloadPlanOutcome = process.env.DOWNLOAD_PLAN_OUTCOME;
    const verifyPlanOutcome = process.env.VERIFY_PLAN_OUTCOME ?? process.env.VERIFY_OUTCOME;
    const importOutcome = process.env.IMPORT_OUTCOME;
    const applyOutcome = process.env.APPLY_OUTCOME;

    let failReason = 'Unknown failure. Check the workflow run log for the exact failing step.';
    if (verifyBranchOutcome === 'failure') {
      failReason = 'Branch guard failed. Dispatch this workflow from the expected deployment branch.';
    } else if (initOutcome === 'failure') {
      failReason = '`terraform init` failed while preparing the working directory.';
    } else if (downloadPlanOutcome === 'failure') {
      failReason = 'The saved Terraform plan could not be downloaded from S3.';
    } else if (verifyPlanOutcome === 'failure') {
      failReason =
        'The downloaded Terraform plan failed verification or could not be decoded with `terraform show`.';
    } else if (importOutcome === 'failure') {
      failReason =
        'The pre-apply import step failed while reconciling existing AWS resources into Terraform state.';
    } else if (applyOutcome === 'failure') {
      failReason = '`terraform apply` failed. Check the apply log in the workflow run or S3 report path.';
    }

    title = `Terraform Apply FAILED on ${environment} - ${sha}`;
    body = [
      '## Terraform Apply Failed',
      '',
      `**Environment:** \`${environment}\``,
      `**Branch:** \`${branch}\``,
      `**Commit:** \`${context.sha}\``,
      `**Triggered by:** \`${context.actor}\``,
      '',
      `**Reason:** ${failReason}`,
      '',
      `[View failed run](${runUrl})`,
      '',
      '> Investigate and fix the failure before re-running the deployment.',
    ].join('\n');
  } else {
    title = `Terraform Destroy FAILED on ${environment} - ${sha}`;
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
