# Allow public read access to the bucket for website hosting
resource "aws_s3_bucket_public_access_block" "public_access" {
  bucket = aws_s3_bucket.my_bucket.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# Configure the bucket for public read access
resource "aws_s3_bucket_ownership_controls" "bucket_ownership" {
  bucket = aws_s3_bucket.my_bucket.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

# Public read access ACL
resource "aws_s3_bucket_acl" "public_acl" {
  depends_on = [
    aws_s3_bucket_ownership_controls.bucket_ownership,
    aws_s3_bucket_public_access_block.public_access
  ]

  bucket = aws_s3_bucket.my_bucket.id
  acl    = "public-read"
}

# Bucket policy to allow public read access
resource "aws_s3_bucket_policy" "allow_public_read" {
  depends_on = [aws_s3_bucket_public_access_block.public_access]

  bucket = aws_s3_bucket.my_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "PublicReadGetObject"
        Effect = "Allow"
        Principal = "*"
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.my_bucket.arn}/*"
      },
      {
        Sid    = "CloudFrontAccess"
        Effect = "Allow"
        Principal = {
          AWS = aws_cloudfront_origin_access_identity.oai.iam_arn
        }
        Action = "s3:GetObject"
        Resource = "${aws_s3_bucket.my_bucket.arn}/*"
      }
    ]
  })
}