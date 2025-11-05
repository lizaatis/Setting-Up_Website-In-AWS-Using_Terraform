# AWS S3 Static Website with CloudFront, Custom Domain, and SSL using Terraform

This project demonstrates how to deploy a static website to AWS S3, distribute it globally via CloudFront, and configure a custom domain with SSL certificate using Terraform.

## Table of Contents
- [Prerequisites](#prerequisites)
- [Project Structure](#project-structure)
- [Step-by-Step Setup](#step-by-step-setup)
- [Common Errors and Solutions](#common-errors-and-solutions)
- [Final Configuration](#final-configuration)
- [Testing](#testing)

## Prerequisites

### 1. Install Required Tools
```bash
# Install Terraform
brew install terraform

# Install AWS CLI
brew install awscli

# Verify installations
terraform --version
aws --version
```

### 2. AWS Account Setup
- Create an AWS account
- Set up IAM user with appropriate permissions
- Configure AWS credentials

### 3. Domain Registration
- Register a domain (we used `atisportfolio.com`)
- Domain can be registered through AWS Route53 Domains or external registrar

## Project Structure

```
learn-terraform-get-started-aws/
├── main.tf                    # S3 bucket and website configuration
├── provider.tf                 # AWS provider configuration
├── variables.tf               # Variable definitions
├── s3-policy.tf              # S3 bucket policy for CloudFront
├── cloudfront_route53.tf     # CloudFront distribution and Route53 records
├── ssl-certificate.tf        # SSL certificate and validation
├── domain.tf                 # Domain registration (if using AWS Route53 Domains)
└── s3-site/                  # Static website files
    ├── index.html
    ├── about.html
    ├── contact.html
    ├── education.html
    ├── experience.html
    ├── project.html
    ├── skills.html
    └── static/
        ├── style.css
        └── Images/
            ├── A.jpg
            ├── background.jpeg
            ├── Cybersec.jpg
            ├── Data Analysis.jpg
            ├── IT.jpg
            ├── logo.jpeg
            ├── Project.jpg
            └── Web Development.jpg
```

## Step-by-Step Setup

### Step 1: Configure AWS Provider

**File: `provider.tf`**
```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}
```

### Step 2: Create S3 Bucket and Upload Files

**File: `main.tf`**
```hcl
# S3 bucket for static website
resource "aws_s3_bucket" "my_bucket" {
  bucket = "my-aws-website-portfolio-bucket"
  
  tags = {
    Name        = "My AWS Website Bucket"
    Environment = "production"
  }
}

# S3 bucket website configuration
resource "aws_s3_bucket_website_configuration" "website" {
  bucket = aws_s3_bucket.my_bucket.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }
}

# Upload frontend files to S3
locals {
  frontend_dir = "${path.module}/../s3-site"
}

resource "aws_s3_object" "frontend_files" {
  for_each = {
    for file in fileset(local.frontend_dir, "**") : file => file
    if !startswith(file, ".git/")
  }

  bucket = aws_s3_bucket.my_bucket.id
  key    = each.value
  source = "${local.frontend_dir}/${each.value}"
  
  content_type = lookup({
    "html" = "text/html"
    "css"  = "text/css"
    "js"   = "application/javascript"
    "png"  = "image/png"
    "jpg"  = "image/jpeg"
    "jpeg" = "image/jpeg"
    "gif"  = "image/gif"
    "svg"  = "image/svg+xml"
  }, split(".", each.value)[1], "application/octet-stream")
  
  etag = filemd5("${local.frontend_dir}/${each.value}")
}
```

### Step 3: Configure S3 Bucket Policy

**File: `s3-policy.tf`**
```hcl
# S3 bucket policy to allow CloudFront access
resource "aws_s3_bucket_policy" "allow_cloudfront" {
  bucket = aws_s3_bucket.my_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudFrontServicePrincipal"
        Effect    = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.my_bucket.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.cdn.arn
          }
        }
      }
    ]
  })
}
```

### Step 4: Create CloudFront Distribution

**File: `cloudfront_route53.tf`**
```hcl
# CloudFront distribution
resource "aws_cloudfront_distribution" "cdn" {
  origin {
    domain_name = aws_s3_bucket_website_configuration.website.website_endpoint
    origin_id   = "S3-${aws_s3_bucket.my_bucket.id}"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
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

    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 3600
    max_ttl     = 86400
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
```

### Step 5: Configure SSL Certificate

**File: `ssl-certificate.tf`**
```hcl
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
```

### Step 6: Domain Registration (Optional)

**File: `domain.tf`**
```hcl
# Domain is already registered on AWS Route53 Domains
# No need to register it again
```

## Common Errors and Solutions

### Error 1: Terraform not detecting files to upload
**Problem:** `fileset` function not finding files in the specified directory.

**Error Message:**
```
Error: Invalid function argument
```

**Solution:** 
- Check the `frontend_dir` path in `main.tf`
- Ensure the path is correct relative to the Terraform configuration
- Use `ls -la` to verify directory structure

**Fixed Code:**
```hcl
locals {
  frontend_dir = "${path.module}/../s3-site"  # Correct path
}
```

### Error 2: Terraform attempting to upload .git directory
**Problem:** `fileset` function including `.git` files in upload.

**Error Message:**
```
Error: Failed to upload file
```

**Solution:** Filter out `.git` files using conditional logic.

**Fixed Code:**
```hcl
resource "aws_s3_object" "frontend_files" {
  for_each = {
    for file in fileset(local.frontend_dir, "**") : file => file
    if !startswith(file, ".git/")  # Exclude .git files
  }
  # ... rest of configuration
}
```

### Error 3: Terraform state lock
**Problem:** Another Terraform process is running or was interrupted.

**Error Message:**
```
Error: Error acquiring the state lock
```

**Solutions:**
1. **Wait:** If another process is running, wait for it to complete
2. **Force unlock:** `terraform force-unlock <LOCK_ID>`
3. **Check processes:** `ps aux | grep terraform`

### Error 4: ACM certificate validation stuck
**Problem:** Certificate validation taking too long (40+ minutes).

**Error Message:**
```
aws_acm_certificate_validation.cert_validation: Still creating...
```

**Root Cause:** Domain nameservers not pointing to AWS Route53.

**Solutions:**
1. **Check domain resolution:** `nslookup atisportfolio.com`
2. **Update nameservers:** Point domain nameservers to AWS Route53
3. **Wait for DNS propagation:** Can take up to 48 hours
4. **Use existing Route53 zone:** If domain is registered on AWS Route53 Domains

### Error 5: Domain not available for registration
**Problem:** Domain name already taken.

**Error Message:**
```
Error: mywebsiteportfolio.com is not available
```

**Solution:** Choose a different domain name and update all references.

### Error 6: Multiple Route53 zones matched
**Problem:** Multiple hosted zones with the same name.

**Error Message:**
```
Error: multiple Route 53 Hosted Zones matched
```

**Solution:** Use specific zone ID instead of data source.

**Fixed Code:**
```hcl
locals {
  route53_zone_id = "Z07280751P7QV0D6CGYVH"  # Specific zone ID
}
```

### Error 7: Route53 zone not found after destruction
**Problem:** Referencing destroyed Route53 zone.

**Error Message:**
```
Error: reading Route 53 Hosted Zone: couldn't find resource
```

**Solution:** Use the correct zone ID from existing domain registration.

**Fixed Code:**
```hcl
# Get correct zone ID from existing domain
aws route53 list-hosted-zones --query "HostedZones[?Name=='atisportfolio.com.'].{Id:Id,Name:Name}"
```

### Error 8: Content type not set for images
**Problem:** Images not displaying correctly due to wrong content type.

**Solution:** Add content type mapping for image files.

**Fixed Code:**
```hcl
content_type = lookup({
  "html" = "text/html"
  "css"  = "text/css"
  "js"   = "application/javascript"
  "png"  = "image/png"
  "jpg"  = "image/jpeg"
  "jpeg" = "image/jpeg"  # Added jpeg support
  "gif"  = "image/gif"
  "svg"  = "image/svg+xml"
}, split(".", each.value)[1], "application/octet-stream")
```

## Final Configuration

### Deploy the Infrastructure
```bash
# Initialize Terraform
terraform init

# Plan the deployment
terraform plan

# Apply the configuration
terraform apply -auto-approve
```

### Verify Deployment
```bash
# Check S3 bucket
aws s3 ls s3://my-aws-website-portfolio-bucket

# Check CloudFront distribution
aws cloudfront list-distributions

# Check Route53 records
aws route53 list-resource-record-sets --hosted-zone-id Z07280751P7QV0D6CGYVH
```

## Testing

### 1. Test CloudFront URL
Visit the CloudFront distribution URL to ensure the website loads.

### 2. Test Custom Domain
- Visit `https://atisportfolio.com`
- Visit `https://www.atisportfolio.com`
- Verify SSL certificate is working
- Check that both HTTP and HTTPS redirect properly

### 3. Test Global Performance
Use tools like GTmetrix or Pingdom to test global performance.

## Troubleshooting

### Common Issues
1. **DNS not resolving:** Wait for DNS propagation (up to 48 hours)
2. **SSL certificate not working:** Ensure certificate validation completed
3. **CloudFront not updating:** Wait for CloudFront distribution deployment
4. **Files not uploading:** Check file paths and permissions

### Useful Commands
```bash
# Check DNS resolution
nslookup atisportfolio.com

# Check SSL certificate
openssl s_client -connect atisportfolio.com:443 -servername atisportfolio.com

# Check CloudFront status
aws cloudfront get-distribution --id E2K54VAG0QD8S7
```

## Cleanup

To destroy all resources:
```bash
terraform destroy -auto-approve
```

**Note:** This will delete all resources including the S3 bucket and CloudFront distribution. Make sure to backup any important data.

## Cost Optimization

- Use CloudFront's `PriceClass_100` for cost-effective global distribution
- Consider S3 Intelligent Tiering for storage optimization
- Monitor CloudWatch metrics for usage patterns

## Security Best Practices

- Use Origin Access Identity (OAI) for S3 bucket access
- Enable HTTPS redirect in CloudFront
- Use modern TLS protocols (TLS 1.2+)
- Regularly rotate SSL certificates
- Monitor access logs for suspicious activity

## Conclusion

This setup provides a robust, scalable, and secure static website hosting solution on AWS with global CDN distribution, custom domain, and SSL encryption. The Terraform configuration ensures infrastructure as code best practices and easy replication.

## **IAM Policies for Cost Management**

### **1. AWS Budgets Policy**
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "budgets:ViewBudget",
                "budgets:DescribeBudgets",
                "budgets:DescribeBudgetActions",
                "budgets:DescribeBudgetActionHistories",
                "budgets:DescribeBudgetPerformanceHistory"
            ],
            "Resource": "*"
        }
    ]
}
```

### **2. AWS Cost Explorer Policy**
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ce:GetCostAndUsage",
                "ce:GetCostAndUsageWithResources",
                "ce:GetDimensionValues",
                "ce:GetReservationCoverage",
                "ce:GetReservationPurchaseRecommendation",
                "ce:GetReservationUtilization",
                "ce:GetSavingsPlansUtilization",
                "ce:GetSavingsPlansUtilizationDetails",
                "ce:GetUsageReport",
                "ce:ListCostCategoryDefinitions",
                "ce:GetCostCategories",
                "ce:GetAnomalies",
                "ce:GetAnomalyMonitors",
                "ce:GetAnomalySubscriptions"
            ],
            "Resource": "*"
        }
    ]
}
```

### **3. AWS Billing Policy**
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "aws-portal:ViewBilling",
                "aws-portal:ViewUsage",
                "aws-portal:ViewAccount",
                "aws-portal:ViewPaymentMethods",
                "aws-portal:ModifyBilling",
                "aws-portal:ModifyAccount",
                "aws-portal:ModifyPaymentMethods"
            ],
            "Resource": "*"
        }
    ]
}
```

### **4. CloudWatch Billing Alarms Policy**
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "cloudwatch:GetMetricStatistics",
                "cloudwatch:ListMetrics",
                "cloudwatch:PutMetricAlarm",
                "cloudwatch:DescribeAlarms",
                "cloudwatch:DeleteAlarms",
                "cloudwatch:SetAlarmState"
            ],
            "Resource": "*"
        }
    ]
}
```

## **How to Apply These Policies**

### **Option 1: Create Custom Policy**
1. Go to **IAM Console** → **Policies** → **Create Policy**
2. Choose **JSON** tab
3. Paste one of the policies above
4. Name it (e.g., "CostManagementPolicy")
5. Attach to your user/role

### **Option 2: Use AWS Managed Policies**
AWS provides some built-in policies:
- `AWSBillingReadOnlyAccess` - Read-only billing access
- `Billing` - Full billing access (use with caution)

### **Option 3: Create a Combined Policy**
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "budgets:*",
                "ce:*",
                "aws-portal:ViewBilling",
                "aws-portal:ViewUsage",
                "aws-portal:ViewAccount",
                "cloudwatch:GetMetricStatistics",
                "cloudwatch:ListMetrics",
                "cloudwatch:PutMetricAlarm",
                "cloudwatch:DescribeAlarms"
            ],
            "Resource": "*"
        }
    ]
}
```

## **Setting Up Cost Monitoring**

### **1. Enable Cost Explorer**
- Go to **AWS Billing Console**
- Click **Cost Explorer** in the left menu
- Click **Enable Cost Explorer**

### **2. Create Budgets**
- Go to **AWS Budgets** in the Billing Console
- Create budget for:
  - **Monthly cost budget** (e.g., $50/month)
  - **Service-specific budgets** (e.g., S3, CloudFront)
  - **Usage budgets** (e.g., data transfer)

### **3. Set Up Billing Alarms**
```bash
# Create CloudWatch billing alarm
aws cloudwatch put-metric-alarm \
    --alarm-name "MonthlyBillingAlarm" \
    --alarm-description "Alert when monthly charges exceed $50" \
    --metric-name EstimatedCharges \
    --namespace AWS/Billing \
    --statistic Maximum \
    --period 86400 \
    --threshold 50.0 \
    --comparison-operator GreaterThanThreshold \
    --evaluation-periods 1
```

## **Recommended Cost Monitoring Setup**

### **For Your Static Website Project:**
1. **S3 Storage Budget**: $5/month
2. **CloudFront Data Transfer**: $10/month  
3. **Route53 Queries**: $1/month
4. **SSL Certificate**: Free (AWS Certificate Manager)
5. **Total Expected Cost**: ~$15-20/month

### **Cost Optimization Tips:**
- Use **S3 Intelligent Tiering** for storage
- Set **CloudFront cache headers** properly
- Use **Route53 alias records** (free)
- Monitor **data transfer costs**

## **Quick Setup Commands**

If you want to set this up via CLI:

```bash
# Attach billing policy to your user
aws iam attach-user-policy \
    --user-name YOUR_USERNAME \
    --policy-arn arn:aws:iam::aws:policy/AWSBillingReadOnlyAccess

# Create custom cost management policy
aws iam create-policy \
    --policy-name CostManagementPolicy \
    --policy-document file://cost-policy.json
```

Would you like me to help you create any specific cost monitoring setup for your current Terraform project?
