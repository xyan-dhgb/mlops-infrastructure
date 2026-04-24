locals {
  kubernetes_namespace = "prometheus"
  service_account_name = "cicd-metrics-exporter"
  irsa_role_name       = "mlops-cicd-metrics-exporter-irsa-${var.environment}"
  reports_prefixes = [
    for prefix_root in var.reports_prefix_roots : "${trim(prefix_root, "/")}/${var.environment}"
  ]
  reports_prefix_globs = [
    for prefix in local.reports_prefixes : "${prefix}/*"
  ]
  reports_object_arns = [
    for prefix_glob in local.reports_prefix_globs : "arn:aws:s3:::${var.reports_bucket_name}/${prefix_glob}"
  ]
}

data "aws_iam_policy_document" "cicd_metrics_irsa_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.eks_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(var.eks_oidc_provider_url, "https://", "")}:sub"
      values = [
        "system:serviceaccount:${local.kubernetes_namespace}:${local.service_account_name}",
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(var.eks_oidc_provider_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cicd_metrics_irsa" {
  name               = local.irsa_role_name
  assume_role_policy = data.aws_iam_policy_document.cicd_metrics_irsa_assume.json

  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

data "aws_iam_policy_document" "cicd_metrics_s3_read" {
  statement {
    effect = "Allow"
    actions = [
      "s3:GetBucketLocation",
      "s3:ListBucket",
    ]
    resources = ["arn:aws:s3:::${var.reports_bucket_name}"]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = concat(local.reports_prefixes, local.reports_prefix_globs)
    }
  }

  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
    ]
    resources = local.reports_object_arns
  }
}

resource "aws_iam_role_policy" "cicd_metrics_s3_read" {
  name   = "mlops-cicd-metrics-s3-read-policy"
  role   = aws_iam_role.cicd_metrics_irsa.id
  policy = data.aws_iam_policy_document.cicd_metrics_s3_read.json
}
