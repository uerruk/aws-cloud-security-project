# ─── GITHUB OIDC IDENTITY PROVIDER ──────────────────────────────────────────
# Allows GitHub Actions to authenticate to AWS without stored credentials
# GitHub generates a short-lived JWT token per workflow run
# AWS verifies the token and issues temporary credentials

resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com"
  ]

  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd"
  ]

  tags = {
    Name = "github-actions-oidc-provider"
  }
}

# ─── GITHUB ACTIONS ROLE ─────────────────────────────────────────────────────
# Assumed by GitHub Actions workflows via OIDC
# Only workflows from repo uerruk/aws-onlinebaqqala can assume this role
# No stored credentials anywhere — pure token-based auth

resource "aws_iam_role" "github_actions" {
  name        = "github-actions-oidc-role"
  description = "Role for GitHub Actions OIDC authentication"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = [
              "repo:uerruk/aws-onlinebaqqala:*"
            ]
          }
        }
      }
    ]
  })

  tags = {
    Name = "github-actions-oidc-role"
  }
}

# ─── GITHUB ACTIONS PERMISSIONS ──────────────────────────────────────────────
# Consolidated single policy — AMI bake + Launch Template update + SSM deploy
# SSM resource uses * for instance — covers both old and new private instances

resource "aws_iam_role_policy" "github_actions_deploy" {
  name = "github-actions-deploy-policy"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SSMDeploy"
        Effect = "Allow"
        Action = [
          "ssm:SendCommand",
          "ssm:GetCommandInvocation",
          "ssm:ListCommandInvocations"
        ]
        Resource = [
          "arn:aws:ssm:eu-west-1::document/AWS-RunShellScript",
          "arn:aws:ec2:eu-west-1:${data.aws_caller_identity.current.account_id}:instance/*"
        ]
      },
      {
        Sid    = "AMIBakeAndTemplateUpdate"
        Effect = "Allow"
        Action = [
          "ec2:CreateImage",
          "ec2:DescribeInstances",
          "ec2:DescribeImages",
          "ec2:CreateTags",
          "ec2:CreateLaunchTemplateVersion",
          "ec2:ModifyLaunchTemplate"
        ]
        Resource = "*"
      }
    ]
  })
}

# ─── EC2 INSTANCE ROLE ───────────────────────────────────────────────────────
# Attached to all EC2 instances via instance profile
# Temporary credentials — auto-rotated by AWS, never stored on disk
# Follows least privilege — only what the app needs

resource "aws_iam_role" "ec2" {
  name        = "Netflix-EC2-Role"
  description = "EC2 instance role for onlinebaqqala app"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "Netflix-EC2-Role"
  }
}

# ─── EC2 INLINE POLICIES ─────────────────────────────────────────────────────

resource "aws_iam_role_policy" "ec2_ami_creation" {
  name = "allow-ami-creation"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowAMICreation"
        Effect = "Allow"
        Action = [
          "ec2:CreateImage",
          "ec2:DescribeInstances",
          "ec2:DescribeImages",
          "ec2:CreateTags"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "ec2_s3_buckets" {
  name = "allow-app-buckets-only"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ListAppBuckets"
        Effect = "Allow"
        Action = "s3:ListBucket"
        Resource = [
          "arn:aws:s3:::netflix-frontend-ryzk-441464446441-eu-west-1-an",
          "arn:aws:s3:::netflix-videos-ryzk-441464446441-eu-west-1-an"
        ]
      },
      {
        Sid      = "ReadFrontendBucket"
        Effect   = "Allow"
        Action   = "s3:GetObject"
        Resource = "arn:aws:s3:::netflix-frontend-ryzk-441464446441-eu-west-1-an/*"
      },
      {
        Sid    = "ReadWriteVideosBucket"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "arn:aws:s3:::netflix-videos-ryzk-441464446441-eu-west-1-an/*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "ec2_cloudwatch" {
  name = "allow-cloudwatch-metrics"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "ec2_secrets" {
  name = "netflix-db"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = "arn:aws:secretsmanager:eu-west-1:${data.aws_caller_identity.current.account_id}:secret:prod/netflix-app/rds*"
      }
    ]
  })
}

# ─── AWS MANAGED POLICIES ATTACHED TO EC2 ROLE ───────────────────────────────
# AmazonSSMManagedInstanceCore — enables SSM Session Manager (no SSH needed)
# CloudWatchAgentServerPolicy — allows CloudWatch agent to send metrics/logs

resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "ec2_cloudwatch_agent" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# ─── EC2 INSTANCE PROFILE ────────────────────────────────────────────────────
# Instance profile is the container that holds the role
# This is what you attach to EC2 — not the role directly

resource "aws_iam_instance_profile" "ec2" {
  name = "Netflix-EC2-Role"
  role = aws_iam_role.ec2.name
}

# ─── IAM ACCOUNT PASSWORD POLICY ─────────────────────────────────────────────
# Enforces strong passwords for all IAM users
# Fixes: securityhub-iam-password-policy-minimum-length-check
#        securityhub-iam-password-policy-prevent-reuse-check

resource "aws_iam_account_password_policy" "main" {
  minimum_password_length        = 14
  require_uppercase_characters   = true
  require_lowercase_characters   = true
  require_numbers                = true
  require_symbols                = true
  allow_users_to_change_password = true
  max_password_age               = 90
  password_reuse_prevention      = 24
  hard_expiry                    = false
}

# ─── AWS SUPPORT ACCESS ───────────────────────────────────────────────────────
# Fixes: securityhub-iam-support-policy-in-use
# At least one entity must have AWSSupportAccess policy
# Allows raising AWS support cases

resource "aws_iam_user_policy_attachment" "support_access" {
  user       = "ryzk-admin"
  policy_arn = "arn:aws:iam::aws:policy/AWSSupportAccess"
}
