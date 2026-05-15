{{/*
Common labels for all resources
*/}}
{{- define "isic-ml-pipeline.labels" -}}
app.kubernetes.io/managed-by: argocd
app.kubernetes.io/part-of: isic-ml-pipeline
{{- end }}

{{/*
Full ECR image URL: <registry>/<image>:<tag>
Usage: {{ include "isic-ml-pipeline.image" (list . "train") }}
*/}}
{{- define "isic-ml-pipeline.image" -}}
{{- $root := index . 0 -}}
{{- $imageName := index . 1 -}}
{{- printf "%s/%s:%s" $root.Values.global.ecrRegistry $imageName $root.Values.global.imageTag -}}
{{- end }}
