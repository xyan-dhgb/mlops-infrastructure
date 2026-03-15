output "namespace" {
  description = "Kubernetes namespace where ingress-nginx is installed"
  value       = helm_release.ingress_nginx.namespace
}

output "chart_version" {
  description = "Deployed ingress-nginx Helm chart version"
  value       = helm_release.ingress_nginx.version
}
