variable "prd_domain" {}
variable "stg_domain" {}
variable "prd_route53_zone_id" {}
variable "stg_route53_zone_id" {}

provider "aws" {
  profile = "private"
  region = "ap-northeast-1"
}

provider "aws" {
  alias = "acm-region"
  profile = "private"
  region = "us-east-1"
}


########## ASSET S3 BUCKET ##########
resource "aws_s3_bucket" "stg-asset" {
  bucket = var.stg_domain
  acl    = "public-read"
  policy = "${data.template_file.stg-cdn-policy.rendered}"

  website {
    index_document = "index.html"
    error_document = "error.html"
  }

  logging {
    target_bucket = "${aws_s3_bucket.stg-log-bucket.id}"
    target_prefix = "${var.stg_domain}/log/s3/"
  }
}

locals {
  stg_s3_origin_id = "stg-s3-origin"
}

resource "aws_s3_bucket" "prd-asset" {
  bucket = var.prd_domain
  acl    = "public-read"
  policy = "${data.template_file.prd-cdn-policy.rendered}"

  website {
    index_document = "index.html"
    error_document = "error.html"
  }

  logging {
    target_bucket = "${aws_s3_bucket.prd-log-bucket.id}"
    target_prefix = "${var.prd_domain}/log/s3/"
  }
}

locals {
  prd_s3_origin_id = "prd-s3-origin"
}

########## ASSET ACCESS RISTRICT CONFIGURATION ##########

resource "aws_cloudfront_origin_access_identity" "stg-origin-access-identity" {
  comment = var.stg_domain
}

data "template_file" "stg-cdn-policy" {
  template = "${file("cdn-policy.json.tpl")}"

  vars = {
    bucket_name            = var.stg_domain
    origin_access_identity = "${aws_cloudfront_origin_access_identity.stg-origin-access-identity.id}"
  }
}

resource "aws_cloudfront_origin_access_identity" "prd-origin-access-identity" {
  comment = var.prd_domain
}

data "template_file" "prd-cdn-policy" {
  template = "${file("cdn-policy.json.tpl")}"

  vars = {
    bucket_name            = var.prd_domain
    origin_access_identity = "${aws_cloudfront_origin_access_identity.prd-origin-access-identity.id}"
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

resource "aws_acm_certificate" "stg-cert" {
  provider          = "aws.acm-region"
  domain_name       = var.stg_domain
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_acm_certificate" "prd-cert" {
  provider          = "aws.acm-region"
  domain_name       = var.prd_domain
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

########## CERTIFICATE VALIDATION ##########

resource "aws_route53_record" "stg-cert-validation-record" {
  name    = "${aws_acm_certificate.stg-cert.domain_validation_options.0.resource_record_name}"
  type    = "${aws_acm_certificate.stg-cert.domain_validation_options.0.resource_record_type}"
  zone_id = var.stg_route53_zone_id
  records = ["${aws_acm_certificate.stg-cert.domain_validation_options.0.resource_record_value}"]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "stg-cert-validation" {
  provider          = "aws.acm-region"
  certificate_arn         = "${aws_acm_certificate.stg-cert.arn}"
  validation_record_fqdns = ["${aws_route53_record.stg-cert-validation-record.fqdn}"]
}

resource "aws_route53_record" "prd-cert-validation-record" {
  name    = "${aws_acm_certificate.prd-cert.domain_validation_options.0.resource_record_name}"
  type    = "${aws_acm_certificate.prd-cert.domain_validation_options.0.resource_record_type}"
  zone_id = var.prd_route53_zone_id
  records = ["${aws_acm_certificate.prd-cert.domain_validation_options.0.resource_record_value}"]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "prd-cert-validation" {
  provider          = "aws.acm-region"
  certificate_arn         = "${aws_acm_certificate.prd-cert.arn}"
  validation_record_fqdns = ["${aws_route53_record.prd-cert-validation-record.fqdn}"]
}

########## DNS RECORD ##########

resource "aws_route53_record" "stg-dns" {
  zone_id = var.stg_route53_zone_id
  name    = var.stg_domain
  type    = "A"
  ttl     = "300"
  records = ["${aws_cloudfront_distribution.stg-distribution.domain_name}"]
}

resource "aws_route53_record" "prd-dns" {
  zone_id = var.prd_route53_zone_id
  name    = var.prd_domain
  type    = "A"
  ttl     = "300"
  records = ["${aws_cloudfront_distribution.prd-distribution.domain_name}"]
}

########## CDN ##########

resource "aws_cloudfront_distribution" "stg-distribution" {
  origin {
    domain_name = "${aws_s3_bucket.stg-asset.bucket_regional_domain_name}"
    origin_id   = "${local.stg_s3_origin_id}"

    s3_origin_config {
      origin_access_identity = "${aws_cloudfront_origin_access_identity.stg-origin-access-identity.cloudfront_access_identity_path}"
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  logging_config {
    include_cookies = false
    bucket          = "${aws_s3_bucket.stg-log-bucket.id}.s3.amazonaws.com"
    prefix          = "${var.stg_domain}/log/cloudfront/"
  }

  aliases = [var.stg_domain]

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "${local.stg_s3_origin_id}"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  price_class = "PriceClass_200"

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }


  viewer_certificate {
    acm_certificate_arn = "${aws_acm_certificate.stg-cert.arn}"
    ssl_support_method = "sni-only"
  }
}

resource "aws_cloudfront_distribution" "prd-distribution" {
  origin {
    domain_name = "${aws_s3_bucket.prd-asset.bucket_regional_domain_name}"
    origin_id   = "${local.prd_s3_origin_id}"

    s3_origin_config {
      origin_access_identity = "${aws_cloudfront_origin_access_identity.prd-origin-access-identity.cloudfront_access_identity_path}"
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  logging_config {
    include_cookies = false
    bucket          = "${aws_s3_bucket.prd-log-bucket.id}.s3.amazonaws.com"
    prefix          = "${var.prd_domain}/log/cloudfront/"
  }

  aliases = [var.prd_domain]

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "${local.prd_s3_origin_id}"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  price_class = "PriceClass_200"

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn = "${aws_acm_certificate.prd-cert.arn}"
    ssl_support_method = "sni-only"
  }
}
