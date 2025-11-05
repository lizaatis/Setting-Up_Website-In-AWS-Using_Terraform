# Use the existing Route53 zone that AWS created for the domain
# The zone already exists and is managed by AWS Route53 Domains
# We'll use the zone ID directly since there are multiple zones
locals {
  route53_zone_id = "Z07280751P7QV0D6CGYVH"  # Your existing zone ID from domain registration
}

# SSL Certificate for the custom domain
resource "aws_acm_certificate" "ssl_certificate" {
  domain_name       = "atisportfolio.com"
  subject_alternative_names = ["www.atisportfolio.com"]
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "atisportfolio-ssl-cert"
    Environment = "production"
  }
}

# DNS validation records for the SSL certificate
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.ssl_certificate.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = local.route53_zone_id
}

# Certificate validation
resource "aws_acm_certificate_validation" "cert_validation" {
  certificate_arn         = aws_acm_certificate.ssl_certificate.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}
