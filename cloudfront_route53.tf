# Create a CloudFront distribution for the S3 bucket
resource "aws_cloudfront_distribution" "cdn" {
  origin {
    domain_name = aws_s3_bucket.my_bucket.bucket_regional_domain_name
    origin_id   = "S3-${aws_s3_bucket.my_bucket.id}"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.oai.cloudfront_access_identity_path
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  # Custom domain aliases
  aliases = ["atisportfolio.com", "www.atisportfolio.com"]

  default_cache_behavior {
    target_origin_id       = "S3-${aws_s3_bucket.my_bucket.id}"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  price_class = "PriceClass_100"

  # Use the custom SSL certificate
  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.cert_validation.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    Name = "my-aws-website-cdn"
  }
}
# Create an Origin Access Identity (OAI) for CloudFront
resource "aws_cloudfront_origin_access_identity" "oai" {
  comment = "OAI for S3 bucket ${aws_s3_bucket.my_bucket.id}"
}

# Route53 records for the custom domain
resource "aws_route53_record" "main" {
  zone_id = local.route53_zone_id
  name    = "atisportfolio.com"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.cdn.domain_name
    zone_id                = aws_cloudfront_distribution.cdn.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "www" {
  zone_id = local.route53_zone_id
  name    = "www.atisportfolio.com"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.cdn.domain_name
    zone_id                = aws_cloudfront_distribution.cdn.hosted_zone_id
    evaluate_target_health = false
  }
}

