resource "helm_release" "ingress_nginx" {
  name             = var.ingress_name
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = true

  timeout = 900 # 15 minutes
  wait    = true

  cleanup_on_fail = true
  force_update    = true

  # Pass replica_count into the templatefile so values.yaml can use it
  values = [
    templatefile("${path.module}/values.yaml", {
      replica_count = var.replica_count
    })
  ]
}
