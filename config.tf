# ─── AWS CONFIG S3 BUCKET ────────────────────────────────────────────────────
# Config stores configuration snapshots and history in S3
# Separate dedicated bucket — keeps audit data isolated

resource "aws_s3_bucket" "config" {
  bucket = "aws-config-logs-${data.aws_caller_identity.current.account_id}-eu-west-1"

  tags = {
    Name    = "aws-config-logs"
    Purpose = "aws-config-configuration-history"
  }
}

resource "aws_s3_bucket_public_access_block" "config" {
  bucket = aws_s3_bucket.config.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "config" {
  bucket = aws_s3_bucket.config.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.main.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_policy" "config" {
  bucket = aws_s3_bucket.config.id

  depends_on = [aws_s3_bucket_public_access_block.config]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSConfigBucketPermissionsCheck"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = "arn:aws:s3:::aws-config-logs-${data.aws_caller_identity.current.account_id}-eu-west-1"
      },
      {
        Sid    = "AWSConfigBucketDelivery"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "arn:aws:s3:::aws-config-logs-${data.aws_caller_identity.current.account_id}-eu-west-1/AWSLogs/${data.aws_caller_identity.current.account_id}/Config/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}

# ─── AWS CONFIG RECORDER ─────────────────────────────────────────────────────
# Records configuration of ALL supported resource types continuously
# IAM resources recorded daily — reduces Config costs
# Uses AWS service-linked role — no custom role needed

resource "aws_config_configuration_recorder" "main" {
  name     = "default"
  role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/config.amazonaws.com/AWSServiceRoleForConfig"

  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }
}

resource "aws_config_delivery_channel" "main" {
  name           = "default"
  s3_bucket_name = aws_s3_bucket.config.bucket

  depends_on = [aws_config_configuration_recorder.main]
}

resource "aws_config_configuration_recorder_status" "main" {
  name       = aws_config_configuration_recorder.main.name
  is_enabled = true

  depends_on = [aws_config_delivery_channel.main]
}

# ─── AWS CONFIG RULES ────────────────────────────────────────────────────────
# 7 custom managed rules — evaluate resources against security policies
# Findings appear in Security Hub via integration

resource "aws_config_config_rule" "imdsv2" {
  name = "ec2-imdsv2-check"

  source {
    owner             = "AWS"
    source_identifier = "EC2_IMDSV2_REQUIRED"
  }

  depends_on = [aws_config_configuration_recorder.main]

  tags = { Name = "ec2-imdsv2-check" }
}

resource "aws_config_config_rule" "encrypted_volumes" {
  name = "encrypted-volumes"

  source {
    owner             = "AWS"
    source_identifier = "ENCRYPTED_VOLUMES"
  }

  depends_on = [aws_config_configuration_recorder.main]

  tags = { Name = "encrypted-volumes" }
}

resource "aws_config_config_rule" "root_access_key" {
  name = "iam-root-access-key-check"

  source {
    owner             = "AWS"
    source_identifier = "IAM_ROOT_ACCESS_KEY_CHECK"
  }

  depends_on = [aws_config_configuration_recorder.main]

  tags = { Name = "iam-root-access-key-check" }
}

resource "aws_config_config_rule" "mfa_enabled" {
  name = "iam-user-mfa-enabled"

  source {
    owner             = "AWS"
    source_identifier = "IAM_USER_MFA_ENABLED"
  }

  depends_on = [aws_config_configuration_recorder.main]

  tags = { Name = "iam-user-mfa-enabled" }
}

resource "aws_config_config_rule" "rds_deletion_protection" {
  name = "rds-instance-deletion-protection-enabled"

  source {
    owner             = "AWS"
    source_identifier = "RDS_INSTANCE_DELETION_PROTECTION_ENABLED"
  }

  depends_on = [aws_config_configuration_recorder.main]

  tags = { Name = "rds-instance-deletion-protection-enabled" }
}

resource "aws_config_config_rule" "restricted_ssh" {
  name = "restricted-ssh"

  source {
    owner             = "AWS"
    source_identifier = "INCOMING_SSH_DISABLED"
  }

  depends_on = [aws_config_configuration_recorder.main]

  tags = { Name = "restricted-ssh" }
}

resource "aws_config_config_rule" "s3_public_read" {
  name = "s3-bucket-public-read-prohibited"

  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_PUBLIC_READ_PROHIBITED"
  }

  depends_on = [aws_config_configuration_recorder.main]

  tags = { Name = "s3-bucket-public-read-prohibited" }
}
