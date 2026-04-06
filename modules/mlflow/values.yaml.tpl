# Helm values template for community-charts/mlflow
serviceAccount:
  create: true
  name: "mlflow-sa"
  annotations:
    eks.amazonaws.com/role-arn: "${irsa_role_arn}"

backendStore:
  databaseMigration: true
  postgres:
    enabled: true
    host:
      valueFrom:
        secretKeyRef:
          name: "mlflow-secret"
          key: "db-host"
    port:
      valueFrom:
        secretKeyRef:
          name: "mlflow-secret"
          key: "db-port"
    database:
      valueFrom:
        secretKeyRef:
          name: "mlflow-secret"
          key: "db-name"
    user:
      valueFrom:
        secretKeyRef:
          name: "mlflow-secret"
          key: "db-user"
    password:
      valueFrom:
        secretKeyRef:
          name: "mlflow-secret"
          key: "db-pass"

artifactRoot:
  proxiedArtifactStorage: true
  s3:
    enabled: true
    bucket: "${s3_bucket}"
    awsRegion: "${aws_region}"

service:
  type: ClusterIP
  port: 5000

ingress:
  enabled: false

resources:
  requests:
    cpu: "250m"
    memory: "512Mi"
  limits:
    cpu: "500m"
    memory: "1Gi"
