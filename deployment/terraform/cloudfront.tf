data "aws_route53_zone" "stevek_com_website" {
  name = var.domain
}

resource "aws_route53_record" "stevek_com_website" {
  zone_id = data.aws_route53_zone.stevek_com_website.zone_id
  name    = var.domain
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.stevek_com_website.domain_name
    zone_id                = aws_cloudfront_distribution.stevek_com_website.hosted_zone_id
    evaluate_target_health = false
  }
}

data "aws_acm_certificate" "stevek_com_website" {
  provider = aws.us_east_1
  domain   = var.domain
  statuses = ["ISSUED"]
}

data "aws_cloudfront_cache_policy" "managed_caching_optimized" {
  name = "Managed-CachingOptimized"
}

resource "aws_wafv2_web_acl" "cloudfront" {
  provider = aws.us_east_1
  name     = "stevekc-cloudfront"
  scope    = "CLOUDFRONT"

  default_action {
    allow {}
  }

  rule {
    name     = "AWSManagedRulesAmazonIpReputationList"
    priority = 0

    # Monitor mode: count matches without blocking requests.
    override_action {
      count {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "stevekc-cloudfront-ip-reputation"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1

    # Monitor mode: count matches without blocking requests.
    override_action {
      count {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "stevekc-cloudfront-common-rules"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 2

    # Monitor mode: count matches without blocking requests.
    override_action {
      count {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "stevekc-cloudfront-known-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "stevekc-cloudfront-waf"
    sampled_requests_enabled   = true
  }
}

resource "aws_cloudfront_origin_access_control" "stevekc_OAC" {
  name                              = "stevekc_OAC"
  description                       = "OAC for stevekc.com website"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "stevek_com_website" {
  comment             = "stevekc_com_website"
  enabled             = true
  aliases             = [var.domain]
  default_root_object = "index.html"
  price_class         = "PriceClass_All"
  http_version        = "http2"
  web_acl_id          = aws_wafv2_web_acl.cloudfront.arn

  origin {
    domain_name              = aws_s3_bucket.web-bucket.bucket_regional_domain_name
    origin_id                = "s3-${aws_s3_bucket.web-bucket.id}"
    origin_access_control_id = aws_cloudfront_origin_access_control.stevekc_OAC.id
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "s3-${aws_s3_bucket.web-bucket.id}"
    viewer_protocol_policy = "redirect-to-https"
    cache_policy_id        = data.aws_cloudfront_cache_policy.managed_caching_optimized.id
    compress               = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = data.aws_acm_certificate.stevek_com_website.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}
