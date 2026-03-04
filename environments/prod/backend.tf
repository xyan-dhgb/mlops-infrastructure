terraform {
  backend "s3" {
    bucket         = "kltn-tfstate-prod"
    key            = "eks/prod/terraform.tfstate"
    region         = "ap-southeast-1"

    dynamodb_table = "tf-lock-prod"
    encrypt        = true

    # optional but recommended
    acl            = "private"
  }
}