# IAM Role IRSA for KServe Storage Initializer
# KServe Storage Initializer is an init container that automatically downloads model artifacts from S3 to /mnt/models before the serving container starts.
# ServiceAccount is bound: kserve/kserve-storage-initializer (automatically created by KServe Helm chart when installed into the kserve namespace)

# Trust Policy
data "aws_iam_policy_document" "kserve_storage_irsa_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.eks_oidc_provider_arn]
    }

    # Only allow ServiceAccount kserve/kserve-storage-initializer to assume this role
    condition {
      test     = "StringEquals"
      variable = "${replace(var.eks_oidc_provider_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kserve:kserve-storage-initializer"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(var.eks_oidc_provider_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

# IAM Role
resource "aws_iam_role" "kserve_storage_irsa" {
  name               = "${var.project_name}-kserve-storage-irsa-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.kserve_storage_irsa_assume.json

  tags = {
    Project     = var.project_name
    Environment = var.environment
    Component   = "kserve-storage-initializer"
  }
}

# S3 Policy
# Storage Initializer only needs to read model artifacts - no write permission required
data "aws_iam_policy_document" "kserve_storage_s3" {
  statement {
    sid    = "ReadModelArtifacts"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:ListBucket",
      "s3:HeadObject",
    ]
    resources = [
      "arn:aws:s3:::kltn-isic-2024-colab",
      "arn:aws:s3:::kltn-isic-2024-colab/*",
    ]
  }
}

resource "aws_iam_role_policy" "kserve_storage_s3" {
  name   = "${var.project_name}-kserve-storage-s3-policy-${var.environment}"
  role   = aws_iam_role.kserve_storage_irsa.id
  policy = data.aws_iam_policy_document.kserve_storage_s3.json
}
