output "bucket_name" {
  value = aws_s3_bucket.mlflow_artifact.bucket
}

output "bucket_arn" {
  value = aws_s3_bucket.mlflow_artifact.arn
}
