# ─── LAMBDA EXECUTION ROLE ───────────────────────────────────────────────────
# Lambda needs permission to send emails via SES
# and write logs to CloudWatch

resource "aws_iam_role" "lambda_order" {
  name = "order-notification-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "order-notification-role"
  }
}

resource "aws_iam_role_policy" "lambda_order" {
  name = "order-notification-policy"
  role = aws_iam_role.lambda_order.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SESsend"
        Effect = "Allow"
        Action = [
          "ses:SendEmail",
          "ses:SendRawEmail"
        ]
        Resource = "*"
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:eu-west-1:${data.aws_caller_identity.current.account_id}:*"
      }
    ]
  })
}

# ─── LAMBDA FUNCTION — ORDER NOTIFICATION ────────────────────────────────────
# Triggered after a customer places an order
# Sends order confirmation email via SES
# Runtime: Node.js 22.x — ES modules syntax (import not require)
# Currently tested manually — will be invoked from server.js
# after SES production access is approved
#
# SES sandbox limitation: currently only sends to verified addresses
# Production access pending AWS approval — then sends to any customer email

resource "aws_lambda_function" "order_notification" {
  function_name = "order-notification"
  role          = aws_iam_role.lambda_order.arn
  handler       = "index.handler"
  runtime       = "nodejs22.x"
  timeout       = 3
  memory_size   = 128

  # Filename placeholder — actual code deployed via console or CI/CD
  # Lambda code is managed separately from infrastructure
  filename = "lambda_placeholder.zip"

  lifecycle {
    ignore_changes = [filename, source_code_hash]
  }

  tags = {
    Name = "order-notification"
  }
}
