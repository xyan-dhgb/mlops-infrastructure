# Policy of role definition for aws load balancer controller
resource "aws_iam_policy" "aws_load_balancer_controller" {
  name        = "${var.cluster_name}-aws-load-balancer-controller"
  path        = "/"
  description = "AWS Load Balancer Controller IAM Policy"
  policy      = file("${path.module}/iam_policy.json") # The official AWS policy document required for the controller.
}

# Trust policy for aws load balancer controller
# "Who can use this role" definition
data "aws_iam_policy_document" "aws_load_balancer_controller_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringEquals"
      variable = "${replace(var.oidc_issuer_url, "https://", "")}:sub"
      # Only the Service Account named aws-load-balancer-controller in the kube-system namespace is allowed to assume this Role.
      values = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(var.oidc_issuer_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Specify the OIDC Provider that was created in the previous step as the trusted authentication source.
    principals {
      identifiers = [var.oidc_provider_arn]
      type        = "Federated"
    }
  }
}

# IAM Role for aws load balancer controller
resource "aws_iam_role" "aws_load_balancer_controller" {
  name               = "${var.cluster_name}-aws-load-balancer-controller"
  assume_role_policy = data.aws_iam_policy_document.aws_load_balancer_controller_assume_role_policy.json
}

resource "aws_iam_role_policy_attachment" "aws_load_balancer_controller_attach" {
  role       = aws_iam_role.aws_load_balancer_controller.name
  policy_arn = aws_iam_policy.aws_load_balancer_controller.arn
}
