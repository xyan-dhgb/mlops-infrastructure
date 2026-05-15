{{/*
Common labels for all resources
*/}}
{{- define "isic-ml-pipeline.labels" -}}
app.kubernetes.io/managed-by: argocd
app.kubernetes.io/part-of: isic-ml-pipeline
{{- end }}

{{/*
Full ECR image URL for single-repo pattern: <registry>/<repo>:<image-prefix>-<tag>
All images live in one ECR repository (kltn-mutimodal-images).
Usage: {{ include "isic-ml-pipeline.image" (list . "train" "20260512-1457") }}
*/}}
{{- define "isic-ml-pipeline.image" -}}
{{- $root := index . 0 -}}
{{- $imagePrefix := index . 1 -}}
{{- $imageTag := index . 2 -}}
{{- printf "%s/%s:%s-%s" $root.Values.global.ecrRegistry $root.Values.global.ecrRepository $imagePrefix $imageTag -}}
{{- end }}
