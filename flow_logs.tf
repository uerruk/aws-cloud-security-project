# ─── VPC FLOW LOGS IAM ROLE ──────────────────────────────────────────────────
# Flow Logs service needs permission to write to CloudWatch Logs
# Trust policy allows vpc-flow-logs.amazonaws.com to assume this role

resource "aws_iam_role" "flow_logs" {
  name = "Netflix-FlowLogs-Role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "Netflix-FlowLogs-Role"
  }
}

resource "aws_iam_role_policy" "flow_logs" {
  name = "flow-logs-cloudwatch-policy"
  role = aws_iam_role.flow_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      }
    ]
  })
}

# ─── VPC FLOW LOGS ───────────────────────────────────────────────────────────
# Captures all IP traffic metadata for the entire VPC
# TrafficType ALL — both ACCEPT and REJECT records
# REJECT records reveal blocked connection attempts — NACL and SG denies
# ACCEPT records show actual traffic flows
#
# 60 second aggregation — records delivered every minute
# Standard 14-field format — compatible with CloudWatch Logs Insights
#
# SCS-C02 use case:
# Query REJECT records on port 3306 to diagnose RDS connectivity issues
# Query unusual srcAddr patterns to detect port scanning
# Query large bytes values to detect data exfiltration

resource "aws_flow_log" "main" {
  vpc_id          = aws_vpc.main.id
  traffic_type    = "ALL"
  iam_role_arn    = aws_iam_role.flow_logs.arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_logs.arn

  max_aggregation_interval = 60

  log_format = "$${version} $${account-id} $${interface-id} $${srcaddr} $${dstaddr} $${srcport} $${dstport} $${protocol} $${packets} $${bytes} $${start} $${end} $${action} $${log-status}"

  tags = {
    Name = "Netflix-VPC-FlowLogs"
  }
}
