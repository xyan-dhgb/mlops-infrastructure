output "argocd_release_name" {
  description = "The name of the ArgoCD Helm release"
  value       = helm_release.argocd.name
}

output "argocd_namespace" {
  description = "The namespace where ArgoCD is installed"
  value       = helm_release.argocd.namespace
}
