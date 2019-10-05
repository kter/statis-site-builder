variable "prd_domain" {}
variable "stg_domain" {}

provider "aws" {
  profile = "private"
  region = "us-east-1"
}

########## ASSET S3 BUCKET ##########
resource "aws_s3_bucket" "stg-asset" {
  bucket = var.stg_domain
  acl    = "public-read"
  # auto configuration by cloudfront
  # policy = "${file("stg-asset-policy.json")}"

  website {
    index_document = "index.html"
    error_document = "error.html"
  }

  logging {
    target_bucket = "${aws_s3_bucket.stg-log-bucket.id}"
    target_prefix = "${var.stg_domain}/log/"
  }
}

resource "aws_s3_bucket" "prd-asset" {
  bucket = var.prd_domain
  acl    = "public-read"
  # auto configuration by cloudfront
  # policy = "${file("prd-asset-policy.json")}"

  website {
    index_document = "index.html"
    error_document = "error.html"
  }

  logging {
    target_bucket = "${aws_s3_bucket.prd-log-bucket.id}"
    target_prefix = "${var.prd_domain}/log/"
  }
}

########## LOG S3 BUCKET ##########

resource "aws_s3_bucket" "stg-log-bucket" {
  bucket = "log.${var.stg_domain}"
  acl    = "log-delivery-write"
}

resource "aws_s3_bucket" "prd-log-bucket" {
  bucket = "log.${var.prd_domain}"
  acl    = "log-delivery-write"
}

########## CERTIFICATE ##########

resource "aws_acm_certificate" "prd-cert" {
  domain_name       = var.prd_domain
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_acm_certificate" "stg-cert" {
  domain_name       = var.stg_domain
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}
