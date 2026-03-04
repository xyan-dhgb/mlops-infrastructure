# Security group for EKS Control Plane: Allow HTTPS access to Kubernetes API
resource "aws_security_group" "eks_control_plane" {
  name_prefix = "${var.project_name}-eks-cp-"
  description = "Security group for EKS control plane - Kubernetes API access"
  vpc_id      = var.vpc_id

  # Allow HTTPS only from within the VPC (removes 0.0.0.0/0 public exposure).
  # Public access CIDRs are further restricted at the EKS endpoint level via
  # cluster_endpoint_public_access_cidrs in each environment's tfvars.
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "Kubernetes API - HTTPS from VPC only"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name = "${var.project_name}-eks-control-plane-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Security group for EKS Worker Nodes: Minimal required ports only
resource "aws_security_group" "eks_worker_nodes" {
  name_prefix = "${var.project_name}-eks-nodes-"
  description = "Security group for EKS worker nodes - pod, node, and control plane communication"
  vpc_id      = var.vpc_id

  # Ephemeral / high ports for TCP responses (pod-to-pod, inter-node communication).
  # Lower ports (0–1024) are deliberately excluded; specific low ports added below.
  ingress {
    from_port   = 1025
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "Ephemeral TCP ports - pod and inter-node communication"
  }

  # DNS (UDP 53) — required for CoreDNS / kube-dns to resolve service names
  ingress {
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = [var.vpc_cidr]
    description = "DNS (UDP) - CoreDNS service resolution"
  }

  # DNS (TCP 53) — fallback for large DNS responses
  ingress {
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "DNS (TCP) - CoreDNS fallback for large responses"
  }

  # VXLAN / Geneve (UDP 4789) — overlay network encapsulation used by AWS VPC CNI and Calico
  ingress {
    from_port   = 4789
    to_port     = 4789
    protocol    = "udp"
    cidr_blocks = [var.vpc_cidr]
    description = "CNI overlay (VXLAN/Geneve) - inter-node pod networking"
  }

  # NodePort services (TCP 30000-32767) — required to expose Kubernetes Services of type NodePort
  ingress {
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "NodePort services - Kubernetes NodePort range"
  }

  # Allow all outbound traffic (required to reach EKS API, ECR, S3, etc.)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name = "${var.project_name}-eks-worker-nodes-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ── Cross-SG rules (separated to break circular dependency) ─────────────────
#
# Control plane → worker nodes: kubelet API (port 10250)
# Required for: kubectl logs, kubectl exec, liveness/readiness probes, metrics-server.
resource "aws_security_group_rule" "control_plane_to_nodes_kubelet" {
  type                     = "ingress"
  from_port                = 10250
  to_port                  = 10250
  protocol                 = "tcp"
  security_group_id        = aws_security_group.eks_worker_nodes.id
  source_security_group_id = aws_security_group.eks_control_plane.id
  description              = "Kubelet API - from EKS control plane"
}

# Control plane → worker nodes: HTTPS (port 443)
# Required for webhook aggregation layer traffic.
resource "aws_security_group_rule" "control_plane_to_nodes_https" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.eks_worker_nodes.id
  source_security_group_id = aws_security_group.eks_control_plane.id
  description              = "HTTPS from EKS control plane (webhook aggregation)"
}

# Worker nodes → control plane: HTTPS (port 443)
# Required for nodes to call the Kubernetes API server.
resource "aws_security_group_rule" "nodes_to_control_plane_https" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.eks_control_plane.id
  source_security_group_id = aws_security_group.eks_worker_nodes.id
  description              = "Kubernetes API - HTTPS from worker nodes"
}

