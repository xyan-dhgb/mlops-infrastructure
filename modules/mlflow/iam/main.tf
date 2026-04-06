# IAM Role IRSA for MLflow Pod
data "aws_iam_policy_document" "mlflow_irsa_assume" {
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
      values   = ["system:serviceaccount:mlops:mlflow-sa"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(var.eks_oidc_provider_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "mlflow_irsa" {
  name               = "mlops-mlflow-irsa-dev"
  assume_role_policy = data.aws_iam_policy_document.mlflow_irsa_assume.json

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

data "aws_iam_policy_document" "mlflow_s3" {
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListMultipartUploadParts",
      "s3:AbortMultipartUpload",
    ]
    resources = ["${var.s3_bucket_arn}/*"]
  }

  statement {
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [var.s3_bucket_arn]
  }
}

resource "aws_iam_role_policy" "mlflow_s3" {
  name   = "mlops-mlflow-s3-policy"
  role   = aws_iam_role.mlflow_irsa.id
  policy = data.aws_iam_policy_document.mlflow_s3.json
}
