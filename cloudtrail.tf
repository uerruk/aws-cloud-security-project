# ─── CLOUDTRAIL S3 BUCKET ────────────────────────────────────────────────────
# Dedicated bucket for CloudTrail logs — separate from app buckets
# Block all public access — audit logs must never be public
# Encrypted with CMK — only principals with kms:Decrypt can read logs

resource "aws_s3_bucket" "cloudtrail" {
  bucket = "aws-cloudtrail-logs-441464446441-9b067ce7"

  tags = {
    Name    = "aws-cloudtrail-logs-441464446441-9b067ce7"
    Purpose = "cloudtrail-audit-logs"
  }
}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.main.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_versioning" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  depends_on = [aws_s3_bucket_public_access_block.cloudtrail]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = "arn:aws:s3:::aws-cloudtrail-logs-441464446441-9b067ce7"
        Condition = {
          StringEquals = {
            "aws:SourceArn" = "arn:aws:cloudtrail:eu-west-1:${data.aws_caller_identity.current.account_id}:trail/Netflix-Audit-Trail"
          }
        }
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "arn:aws:s3:::aws-cloudtrail-logs-441464446441-9b067ce7/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"  = "bucket-owner-full-control"
            "aws:SourceArn" = "arn:aws:cloudtrail:eu-west-1:${data.aws_caller_identity.current.account_id}:trail/Netflix-Audit-Trail"
          }
        }
      },
      {
        Sid    = "AWSALBAccessLogs"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::156460612806:root"
        }
        Action   = "s3:PutObject"
        Resource = "arn:aws:s3:::aws-cloudtrail-logs-441464446441-9b067ce7/alb-access-logs/*"
      }
    ]
  })
}

# ─── CLOUDTRAIL IAM ROLE ─────────────────────────────────────────────────────
# CloudTrail needs permission to write to CloudWatch Logs

resource "aws_iam_role" "cloudtrail_cloudwatch" {
  name = "CloudTrail-CloudWatch-Role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "CloudTrail-CloudWatch-Role"
  }
}

resource "aws_iam_role_policy" "cloudtrail_cloudwatch" {
  name = "cloudtrail-cloudwatch-policy"
  role = aws_iam_role.cloudtrail_cloudwatch.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
      }
    ]
  })
}

# ─── CLOUDTRAIL TRAIL ────────────────────────────────────────────────────────
# Multi-region trail — captures API calls across all AWS regions
# Encrypted with CMK — logs unreadable without kms:Decrypt
# CloudWatch Logs integration — enables metric filters and alarms
# Log file validation ENABLED — SHA-256 digest proves logs not tampered
#
# Management events: All — captures both read and write API calls

resource "aws_cloudtrail" "main" {
  name                          = "Netflix-Audit-Trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true
  cloud_watch_logs_group_arn    = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
  cloud_watch_logs_role_arn     = aws_iam_role.cloudtrail_cloudwatch.arn
  kms_key_id                    = aws_kms_key.main.arn

  event_selector {
    read_write_type           = "All"
    include_management_events = true
  }

  tags = {
    Name = "Netflix-Audit-Trail"
  }
}
