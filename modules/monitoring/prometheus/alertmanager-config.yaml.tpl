global:
  resolve_timeout: 5m
inhibit_rules:
  - source_matchers:
      - severity = critical
    target_matchers:
      - severity =~ warning|info
    equal:
      - namespace
      - alertname
  - source_matchers:
      - severity = warning
    target_matchers:
      - severity = info
    equal:
      - namespace
      - alertname
  - source_matchers:
      - alertname = InfoInhibitor
    target_matchers:
      - severity = info
    equal:
      - namespace
  - target_matchers:
      - alertname = InfoInhibitor
route:
  group_by:
    - alertname
    - namespace
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
  receiver: "null"
  routes:
    - receiver: "null"
      matchers:
        - alertname = "Watchdog"
    - receiver: eks-sns
      matchers:
        - team = "platform"
receivers:
  - name: "null"
  - name: eks-sns
    sns_configs:
      - api_url: 'https://sns.__AWS_REGION__.amazonaws.com'
        topic_arn: __ALERT_SNS_TOPIC_ARN__
        sigv4:
          region: __AWS_REGION__
        subject: '[EKS] {{ .CommonLabels.alertname }}'
        send_resolved: true
