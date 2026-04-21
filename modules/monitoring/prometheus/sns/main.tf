# Local variable values
locals {
  alertmanager_namespace            = "prometheus"
  alertmanager_service_account_name = "alertmanager-sns"
  alertmanager_irsa_role_name       = "mlops-alertmanager-sns-irsa-${var.environment}"
  eks_alerts_topic_name             = "mlops-eks-alerts-${var.environment}"
}

# SNS Topic for EKS Alerts
resource "aws_sns_topic" "eks_alerts" {
  name         = local.eks_alerts_topic_name
  display_name = "EKS Alerts ${upper(var.environment)}"

  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# SNS Topic Subscription for Email Endpoints
resource "aws_sns_topic_subscription" "email" {
  for_each  = toset(var.alert_email_endpoints)
  topic_arn = aws_sns_topic.eks_alerts.arn
  protocol  = "email"
  endpoint  = each.value
}

# IAM Policy Document for Alertmanager IRSA Assume Role
data "aws_iam_policy_document" "alertmanager_irsa_assume" {
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
        "system:serviceaccount:${local.alertmanager_namespace}:${local.alertmanager_service_account_name}",
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(var.eks_oidc_provider_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

# IAM Role for Alertmanager IRSA
resource "aws_iam_role" "alertmanager_sns_irsa" {
  name               = local.alertmanager_irsa_role_name
  assume_role_policy = data.aws_iam_policy_document.alertmanager_irsa_assume.json

  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# IAM Policy Document for Alertmanager SNS Publish
data "aws_iam_policy_document" "alertmanager_sns_publish" {
  statement {
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.eks_alerts.arn]
  }
}

# IAM Role Policy for Alertmanager SNS Publish
resource "aws_iam_role_policy" "alertmanager_sns_publish" {
  name   = "mlops-alertmanager-sns-publish-policy"
  role   = aws_iam_role.alertmanager_sns_irsa.id
  policy = data.aws_iam_policy_document.alertmanager_sns_publish.json
}
