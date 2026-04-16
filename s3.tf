# ─── FRONTEND BUCKET ─────────────────────────────────────────────────────────
# Hosts static frontend assets — HTML, CSS, JavaScript
# Public read access — website visitors need to download these files
# Static website hosting enabled
# Encrypted with CMK — objects encrypted at rest even though publicly readable
# Versioning enabled — recover from accidental overwrites

resource "aws_s3_bucket" "frontend" {
  bucket = "netflix-frontend-ryzk-441464446441-eu-west-1-an"

  tags = {
    Name    = "netflix-frontend-ryzk-441464446441-eu-west-1-an"
    Purpose = "frontend-static-assets"
  }
}

resource "aws_s3_bucket_versioning" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  rule {
    bucket_key_enabled = true

    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.main.arn
    }
  }
}

# Frontend is publicly readable — static website
# Block Public Access must be OFF for public website hosting
resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  depends_on = [aws_s3_bucket_public_access_block.frontend]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "arn:aws:s3:::netflix-frontend-ryzk-441464446441-eu-west-1-an/*"
      }
    ]
  })
}

resource "aws_s3_bucket_website_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }
}

# ─── VIDEOS BUCKET ───────────────────────────────────────────────────────────
# Stores video content — private, app access only
# Block Public Access ON — no internet access
# Bucket policy explicitly denies everyone except EC2 role and admin
# Encrypted with CMK — videos protected at rest
# Versioning enabled — recover deleted or overwritten videos

resource "aws_s3_bucket" "videos" {
  bucket = "netflix-videos-ryzk-441464446441-eu-west-1-an"

  tags = {
    Name    = "netflix-videos-ryzk-441464446441-eu-west-1-an"
    Purpose = "video-content-private"
  }
}

resource "aws_s3_bucket_versioning" "videos" {
  bucket = aws_s3_bucket.videos.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "videos" {
  bucket = aws_s3_bucket.videos.id

  rule {
    bucket_key_enabled = true

    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.main.arn
    }
  }
}

# Videos bucket — fully private
resource "aws_s3_bucket_public_access_block" "videos" {
  bucket = aws_s3_bucket.videos.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "videos" {
  bucket = aws_s3_bucket.videos.id

  depends_on = [aws_s3_bucket_public_access_block.videos]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyPublicAccess"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          "arn:aws:s3:::netflix-videos-ryzk-441464446441-eu-west-1-an",
          "arn:aws:s3:::netflix-videos-ryzk-441464446441-eu-west-1-an/*"
        ]
        Condition = {
          StringNotEquals = {
            "aws:PrincipalArn" = [
              "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/Netflix-EC2-Role",
              "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/ryzk-admin",
              "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
            ]
          }
        }
      }
    ]
  })
}
