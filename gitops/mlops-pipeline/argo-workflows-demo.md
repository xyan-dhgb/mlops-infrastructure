# Argo Workflows demo

This directory contains a small MLOps-shaped demo for checking the Argo Workflows UI.

Resources:

- `mlops-demo-template`: reusable `WorkflowTemplate` with a simple DAG.
- `mlops-demo-smoke-test`: one workflow run created by GitOps.
- `mlops-demo-nightly`: suspended `CronWorkflow` that can be resumed from the UI.
- `mlops-demo-runner`: service account and minimal namespace RBAC for workflow pods.

After Argo CD syncs `argo-workflows-demo`, open Argo Workflows in the `argo-workflows` namespace and check:

- Workflows: `mlops-demo-smoke-test`
- Workflow Templates: `mlops-demo-template`
- Cron Workflows: `mlops-demo-nightly`

To run another copy from the UI, open `mlops-demo-smoke-test` and use **Resubmit**, or open `mlops-demo-template` and use **Submit**.
