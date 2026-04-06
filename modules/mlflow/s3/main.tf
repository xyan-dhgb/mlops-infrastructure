resource "aws_s3_bucket" "mlflow_artifact" {
  bucket        = var.bucket_name
  force_destroy = true

  tags = {
    Project     = var.project_name
    Environment = var.environment
    Component   = "mlflow"
  }
}

resource "aws_s3_bucket_versioning" "mlflow_artifact" {
  bucket = aws_s3_bucket.mlflow_artifact.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "mlflow_artifacts" {
  bucket = aws_s3_bucket.mlflow_artifact.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "mlflow_artifacts" {
  bucket = aws_s3_bucket.mlflow_artifact.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
