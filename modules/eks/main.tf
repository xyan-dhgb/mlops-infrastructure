locals {
  cluster_name = var.cluster_name
}

# ci-test: trigger PR pipeline validation

# CloudWatch Log Group for EKS Cluster Logs
resource "aws_cloudwatch_log_group" "eks_cluster_logs" {
  name              = "/aws/eks/${local.cluster_name}/cluster"
  retention_in_days = var.cluster_log_retention_days

  tags = {
    Name = "${local.cluster_name}-logs"
  }
}

# EKS Cluster
resource "aws_eks_cluster" "main" {
  name     = local.cluster_name
  role_arn = aws_iam_role.eks_cluster_role.arn
  version  = var.cluster_version

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  vpc_config {
    subnet_ids = concat(var.public_subnet_ids, var.private_subnet_ids)
    # Attach the custom control plane security group so the cluster SG rules are applied
    security_group_ids      = [var.control_plane_security_group_id]
    endpoint_private_access = true
    # Public endpoint disabled: kubectl must be run from within the VPC (bastion / VPN).
    # This is the most secure posture and avoids exposing the K8s API to the internet.
    endpoint_public_access = false
  }

  # Enable cluster logging
  enabled_cluster_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]

  # Ensure log group exists before cluster creation
  depends_on = [
    aws_cloudwatch_log_group.eks_cluster_logs,
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_vpc_resource_controller
  ]

  tags = {
    Name = local.cluster_name
  }
}

# Launch Template for Worker Nodes - required to attach a custom security group.
# Without this, nodes only inherit the auto-created cluster SG and cannot be
# reached by the control plane on kubelet port 10250.
resource "aws_launch_template" "eks_nodes" {
  name_prefix = "${local.cluster_name}-node-lt-"
  description = "Launch template for EKS worker nodes"

  # Attach the custom worker node security group IN ADDITION to the cluster SG.
  # The cluster SG is added automatically by EKS when using a managed node group.
  vpc_security_group_ids = [var.worker_nodes_security_group_id]

  # Use IMDSv2 (Instance Metadata Service v2) - security best practice
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${local.cluster_name}-node-lt"
  }
}

# EKS Node Group
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${local.cluster_name}-node-group"
  node_role_arn   = aws_iam_role.worker_nodes_role.arn
  subnet_ids      = var.private_subnet_ids
  capacity_type   = var.node_capacity_type
  instance_types  = var.node_instance_types

  # Reference the launch template so the worker node SG is attached
  launch_template {
    id      = aws_launch_template.eks_nodes.id
    version = aws_launch_template.eks_nodes.latest_version
  }

  # Node group scaling configuration
  scaling_config {
    desired_size = var.node_desired_size
    max_size     = var.node_max_size
    min_size     = var.node_min_size
  }

  # Update strategy
  update_config {
    max_unavailable_percentage = 50
  }

  # Ensure IAM roles are created before node group
  depends_on = [
    aws_iam_role_policy_attachment.worker_nodes_policy,
    aws_iam_role_policy_attachment.worker_nodes_cni_policy,
    aws_iam_role_policy_attachment.worker_nodes_registry_policy
  ]

  tags = {
    Name = "${local.cluster_name}-node-group"
  }
}

# OIDC (OpenID Connect) Provider for IRSA (AWS IAM Roles for Service Accounts)
# Get the EKS cluster OIDC issuer URL through the SSL/TLS certificate
data "tls_certificate" "eks" {
  # This block checks that URL, downloads the security certificate, and extracts a hash code called a Thumbprint (digital fingerprint).
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

# Register the OIDC provider with AWS IAM
resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]                                       # STS: Security Token Service
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint] # Get the thumbprint from the certificate
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_eks_node_group" "ml_nodes" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${local.cluster_name}-ml-node-group"
  node_role_arn   = aws_iam_role.worker_nodes_role.arn
  subnet_ids      = var.private_subnet_ids
  capacity_type   = var.ml_node_capacity_type
  instance_types  = var.ml_node_instance_types

  # Reference the launch template so the worker node SG is attached
  launch_template {
    id      = aws_launch_template.eks_nodes.id
    version = aws_launch_template.eks_nodes.latest_version
  }

  # Node group scaling configuration - starts at 0, Cluster Autoscaler scales up on demand
  scaling_config {
    desired_size = var.ml_node_desired_size
    max_size     = var.ml_node_max_size
    min_size     = var.ml_node_min_size
  }

  # Update strategy
  update_config {
    max_unavailable_percentage = 50
  }

  # Isolate ML workload: system/ingress pods cannot be scheduled here
  labels = {
    role     = "ml-pipeline"
    workload = "gpu-training"
  }

  # Taint: only pods with matching toleration will be scheduled
  taint {
    key    = "workload"
    value  = "ml"
    effect = "NO_SCHEDULE"
  }

  # Ensure IAM roles are created before node group
  depends_on = [
    aws_iam_role_policy_attachment.worker_nodes_policy,
    aws_iam_role_policy_attachment.worker_nodes_cni_policy,
    aws_iam_role_policy_attachment.worker_nodes_registry_policy
  ]

  tags = {
    Name = "${local.cluster_name}-ml-node-group"
  }
}
