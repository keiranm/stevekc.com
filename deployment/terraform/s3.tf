#
# Upload Bucket
#

resource "aws_s3_bucket" "stevekc-uploads" {
  bucket = var.bucket_name
}

resource "aws_s3_bucket_public_access_block" "stevekc-uploads" {
  bucket                  = aws_s3_bucket.stevekc-uploads.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_cors_configuration" "stevekc-uploads" {
  bucket = aws_s3_bucket.stevekc-uploads.id
  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["PUT", "POST", "GET"]
    allowed_origins = ["https://${var.domain}"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "stevekc-uploads" {
  bucket = aws_s3_bucket.stevekc-uploads.id
  rule {
    id = "expired-pending"
    filter {
      prefix = "uploads/pending/"
    }
    status = "Enabled"
    expiration {
      days = 90
    }
  }
  rule {
    id = "expire-pending-thumbnails"
    filter {
      prefix = "uploads/pending-thumbnails/"
    }
    status = "Enabled"
    expiration {
      days = 90
    }
  }
}

#
# Web Bucket
#

resource "aws_s3_bucket" "web-bucket" {
  bucket = var.web_bucket_name
}

resource "aws_s3_bucket_website_configuration" "web-bucket" {
  bucket = aws_s3_bucket.web-bucket.id
  index_document {
    suffix = "index.html"
  }
  error_document {
    key = "error.html"
  }
}

resource "aws_s3_bucket_public_access_block" "web-bucket" {
  bucket                  = aws_s3_bucket.web-bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "web-bucket" {
  statement {
    sid    = "AllowCloudFrontRead"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    actions = [
      "s3:GetObject"
    ]
    resources = [
      "${aws_s3_bucket.web-bucket.arn}/*"
    ]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.stevek_com_website.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "web-bucket" {
  bucket = aws_s3_bucket.web-bucket.id
  policy = data.aws_iam_policy_document.web-bucket.json
}

