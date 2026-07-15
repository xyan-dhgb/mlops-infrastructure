apiVersion: apps/v1
kind: Deployment
metadata:
  name: cicd-metrics-exporter
  namespace: prometheus
  labels:
    app.kubernetes.io/name: cicd-metrics-exporter
    app.kubernetes.io/part-of: kube-prometheus-stack
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: cicd-metrics-exporter
  template:
    metadata:
      labels:
        app.kubernetes.io/name: cicd-metrics-exporter
        app.kubernetes.io/part-of: kube-prometheus-stack
    spec:
      serviceAccountName: cicd-metrics-exporter
      containers:
        - name: exporter
          image: public.ecr.aws/docker/library/python:3.11-slim
          imagePullPolicy: IfNotPresent
          command:
            - python
            - /etc/cicd-metrics/exporter.py
          env:
            - name: REPORTS_DIR
              value: /data/reports
            - name: PORT
              value: "8080"
            - name: CACHE_TTL_SECONDS
              value: "60"
          ports:
            - name: http
              containerPort: 8080
          readinessProbe:
            httpGet:
              path: /-/ready
              port: http
            initialDelaySeconds: 5
            periodSeconds: 15
          livenessProbe:
            httpGet:
              path: /metrics
              port: http
            initialDelaySeconds: 10
            periodSeconds: 30
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 250m
              memory: 256Mi
          volumeMounts:
            - name: exporter-script
              mountPath: /etc/cicd-metrics/exporter.py
              subPath: exporter.py
            - name: reports-data
              mountPath: /data/reports
        - name: s3-sync
          image: public.ecr.aws/aws-cli/aws-cli:latest
          imagePullPolicy: IfNotPresent
          command:
            - /bin/sh
            - -ec
            - |
              mkdir -p /data/reports
              while true; do
                aws s3 sync "s3://__PIPELINE_REPORTS_BUCKET__/__CI_REPORTS_PREFIX__" /data/reports/terraform-ci \
                  --exclude "*" \
                  --include "*/ci-pipeline-metrics.json"
                aws s3 sync "s3://__PIPELINE_REPORTS_BUCKET__/__CD_APPLY_REPORTS_PREFIX__" /data/reports/terraform-apply \
                  --exclude "*" \
                  --include "*/cd-apply-metrics.json"
                sleep 60
              done
          env:
            - name: AWS_REGION
              value: ap-southeast-1
            - name: AWS_DEFAULT_REGION
              value: ap-southeast-1
          resources:
            requests:
              cpu: 25m
              memory: 64Mi
            limits:
              cpu: 100m
              memory: 128Mi
          volumeMounts:
            - name: reports-data
              mountPath: /data/reports
      volumes:
        - name: exporter-script
          configMap:
            name: cicd-metrics-exporter-script
        - name: reports-data
          emptyDir: {}
