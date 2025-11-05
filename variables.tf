variable "my_bucket" {
  description = "The name of the S3 bucket"
  type        = string
  default    = "my-aws-website-portfolio-bucket"
}

variable "domain_name" {
  description = "The domain name for the Route53 zone"
  type        = string
  default     = "mywebsiteportfolio.com"
}