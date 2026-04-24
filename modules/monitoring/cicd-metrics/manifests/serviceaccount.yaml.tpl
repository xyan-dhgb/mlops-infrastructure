apiVersion: v1
kind: ServiceAccount
metadata:
  name: cicd-metrics-exporter
  namespace: prometheus
  labels:
    app.kubernetes.io/name: cicd-metrics-exporter
    app.kubernetes.io/part-of: kube-prometheus-stack
  annotations:
    eks.amazonaws.com/role-arn: __CICD_METRICS_EXPORTER_IRSA_ROLE_ARN__
