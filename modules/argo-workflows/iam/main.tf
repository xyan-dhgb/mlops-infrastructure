data "aws_iam_policy_document" "ml_pipeline_irsa_assume" {
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
      values   = ["system:serviceaccount:kltn-mul-mlops:isic-ml-workflow"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(var.eks_oidc_provider_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ml_pipeline_irsa" {
  name               = "${var.project_name}-ml-pipeline-irsa-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.ml_pipeline_irsa_assume.json

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

# S3 permissions: read from input bucket, read/write to output bucket
data "aws_iam_policy_document" "ml_pipeline_s3" {
  # Read from source dataset bucket
  statement {
    sid    = "ReadInputBucket"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:ListBucket",
    ]
    resources = [
      "arn:aws:s3:::kltn-isic-2024-challenge",
      "arn:aws:s3:::kltn-isic-2024-challenge/*",
    ]
  }

  # Full access to output/working bucket
  statement {
    sid    = "ReadWriteOutputBucket"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
      "s3:ListMultipartUploadParts",
      "s3:AbortMultipartUpload",
    ]
    resources = [
      "arn:aws:s3:::kltn-isic-2024-colab",
      "arn:aws:s3:::kltn-isic-2024-colab/*",
    ]
  }
}

resource "aws_iam_role_policy" "ml_pipeline_s3" {
  name   = "${var.project_name}-ml-pipeline-s3-policy"
  role   = aws_iam_role.ml_pipeline_irsa.id
  policy = data.aws_iam_policy_document.ml_pipeline_s3.json
}
