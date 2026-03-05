terraform {
  backend "s3" {
    bucket = "kltn-tfstate-dev"
    key    = "eks/dev/terraform.tfstate"
    region = "ap-southeast-1"

    dynamodb_table = "tf-lock-dev"
    encrypt        = true

    # optional but recommended
    acl = "private"
  }
}