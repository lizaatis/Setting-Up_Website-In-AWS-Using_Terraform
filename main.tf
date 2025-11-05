#Create an S3 bucket
resource "aws_s3_bucket" "my_bucket" {
  bucket = var.my_bucket
  # Removed deprecated "acl" argument

  tags = {
    Name = "my-aws-website-portfolio-bucket"
    Environment = "Dev"
  }
} 

# Enable static website hosting
resource "aws_s3_bucket_website_configuration" "website" {
  bucket = aws_s3_bucket.my_bucket.id
  # Removed invalid "key" attribute

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }
}
# Upload frontend files to S3 bucket
locals {
  frontend_dir = "${path.module}/s3-site"
}

resource "aws_s3_object" "frontend_files" {
  for_each = {
    for file in fileset(local.frontend_dir, "**") : file => file
    if !startswith(file, ".git/")
  }

  bucket       = aws_s3_bucket.my_bucket.id
  key          = each.value
  source       = "${local.frontend_dir}/${each.value}"
  etag         = filemd5("${local.frontend_dir}/${each.value}")
  content_type = lookup({
    html = "text/html",
    css  = "text/css",
    js   = "application/javascript",
    png  = "image/png",
    jpg  = "image/jpeg",
    jpeg = "image/jpeg"
  }, replace(each.value, "/.*\\./", ""), "application/octet-stream")
}
