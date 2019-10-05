provider "aws" {
  profile = "private"
  region = "us-east-1"
}

resource "aws_s3_bucket" "stg-asset" {
}

resource "aws_s3_bucket" "prd-asset" {
}
