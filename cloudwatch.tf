# ─── SNS TOPICS ──────────────────────────────────────────────────────────────
# Each security event has its own topic
# Allows different subscribers per event type
# e.g. root login alerts go to security team, CPU alerts go to ops team

resource "aws_sns_topic" "netflix_alerts" {
  name = "Netflix-Alerts"
  tags = { Name = "Netflix-Alerts" }
}

resource "aws_sns_topic" "security_alerts" {
  name = "security-alerts"
  tags = { Name = "security-alerts" }
}

resource "aws_sns_topic" "iam_policy_change" {
  name = "security-alerts-iam-policy-change"
  tags = { Name = "security-alerts-iam-policy-change" }
}

resource "aws_sns_topic" "cloudtrail_stopped" {
  name = "security-event-cloudtrail-stopped"
  tags = { Name = "security-event-cloudtrail-stopped" }
}

resource "aws_sns_topic" "failed_login" {
  name = "security-event-failed-login-count"
  tags = { Name = "security-event-failed-login-count" }
}

resource "aws_sns_topic" "sg_change" {
  name = "security-event-security-group-change"
  tags = { Name = "security-event-security-group-change" }
}

# ─── CLOUDWATCH LOG GROUPS ───────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "cloudtrail" {
  name              = "/aws/cloudtrail/online-baqqala"
  retention_in_days = 90

  tags = { Name = "cloudtrail-logs" }
}

resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  name              = "/aws/vpc/flowlogs"
  retention_in_days = 90

  tags = { Name = "vpc-flow-logs" }
}

resource "aws_cloudwatch_log_group" "app_errors" {
  name              = "/onlinebakala/app/errors"
  retention_in_days = 30

  tags = { Name = "app-errors" }
}

resource "aws_cloudwatch_log_group" "app_stdout" {
  name              = "/onlinebakala/app/stdout"
  retention_in_days = 30

  tags = { Name = "app-stdout" }
}

resource "aws_cloudwatch_log_group" "rds_error" {
  name              = "/aws/rds/instance/netflix-production-db-v2/error"
  retention_in_days = 30

  tags = { Name = "rds-error-logs" }
}

resource "aws_cloudwatch_log_group" "lambda_order" {
  name              = "/aws/lambda/order-notification"
  retention_in_days = 30

  tags = { Name = "lambda-order-notification" }
}

resource "aws_cloudwatch_log_group" "lambda_iss" {
  name              = "/aws/lambda/ISS-Tracker"
  retention_in_days = 30

  tags = { Name = "lambda-iss-tracker" }
}

# ─── CLOUDTRAIL METRIC FILTERS ───────────────────────────────────────────────
# These filters watch CloudTrail logs for specific API events
# Pattern matches → metric increments → alarm triggers → SNS notification
# This is the detection pipeline for security events

resource "aws_cloudwatch_log_metric_filter" "root_login" {
  name           = "root-login-detected"
  log_group_name = aws_cloudwatch_log_group.cloudtrail.name
  pattern        = "{ $.userIdentity.type = \"Root\" && $.eventType = \"AwsConsoleSignIn\" }"

  metric_transformation {
    name      = "RootLoginCount"
    namespace = "SecurityMetrics"
    value     = "1"
  }
}

resource "aws_cloudwatch_log_metric_filter" "iam_policy_changes" {
  name           = "iam-policy-changes"
  log_group_name = aws_cloudwatch_log_group.cloudtrail.name
  pattern        = "{ $.eventName = \"PutUserPolicy\" || $.eventName = \"AttachUserPolicy\" || $.eventName = \"DetachUserPolicy\" || $.eventName = \"AttachRolePolicy\" || $.eventName = \"DetachRolePolicy\" }"

  metric_transformation {
    name      = "IAMPolicyChangeCount"
    namespace = "SecurityMetrics"
    value     = "1"
  }
}

resource "aws_cloudwatch_log_metric_filter" "security_group_changes" {
  name           = "security-group-changes"
  log_group_name = aws_cloudwatch_log_group.cloudtrail.name
  pattern        = "{ $.eventName = \"AuthorizeSecurityGroupIngress\" || $.eventName = \"RevokeSecurityGroupIngress\" || $.eventName = \"CreateSecurityGroup\" || $.eventName = \"DeleteSecurityGroup\" }"

  metric_transformation {
    name      = "SecurityGroupChangeCount"
    namespace = "SecurityMetrics"
    value     = "1"
  }
}

resource "aws_cloudwatch_log_metric_filter" "failed_logins" {
  name           = "failed-console-logins"
  log_group_name = aws_cloudwatch_log_group.cloudtrail.name
  pattern        = "{ $.eventName = \"ConsoleLogin\" && $.errorMessage = \"Failed authentication\" }"

  metric_transformation {
    name      = "FailedLoginCount"
    namespace = "SecurityMetrics"
    value     = "1"
  }
}

resource "aws_cloudwatch_log_metric_filter" "cloudtrail_stopped" {
  name           = "cloudtrail-stopped"
  log_group_name = aws_cloudwatch_log_group.cloudtrail.name
  pattern        = "{ $.eventName = \"StopLogging\" }"

  metric_transformation {
    name      = "CloudTrailStoppedCount"
    namespace = "SecurityMetrics"
    value     = "1"
  }
}

# ─── SECURITY ALARMS ─────────────────────────────────────────────────────────
# Each alarm watches its metric filter output
# Threshold of 1 — any occurrence triggers immediately
# These are the 5 SCS-C02 security event alarms

resource "aws_cloudwatch_metric_alarm" "root_login" {
  alarm_name          = "root-login-detected"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "RootLoginCount"
  namespace           = "SecurityMetrics"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "Root account login detected"
  alarm_actions       = [aws_sns_topic.security_alerts.arn]
  treat_missing_data  = "notBreaching"

  tags = { Name = "root-login-detected" }
}

resource "aws_cloudwatch_metric_alarm" "iam_policy_changes" {
  alarm_name          = "iam-policy-changes"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "IAMPolicyChangeCount"
  namespace           = "SecurityMetrics"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "IAM policy change detected"
  alarm_actions       = [aws_sns_topic.iam_policy_change.arn]
  treat_missing_data  = "notBreaching"

  tags = { Name = "iam-policy-changes" }
}

resource "aws_cloudwatch_metric_alarm" "security_group_changes" {
  alarm_name          = "security-group-changes"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "SecurityGroupChangeCount"
  namespace           = "SecurityMetrics"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "Security group change detected"
  alarm_actions       = [aws_sns_topic.sg_change.arn]
  treat_missing_data  = "notBreaching"

  tags = { Name = "security-group-changes" }
}

resource "aws_cloudwatch_metric_alarm" "failed_logins" {
  alarm_name          = "failed-console-logins"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "FailedLoginCount"
  namespace           = "SecurityMetrics"
  period              = 300
  statistic           = "Sum"
  threshold           = 3
  alarm_description   = "3 or more failed console login attempts"
  alarm_actions       = [aws_sns_topic.failed_login.arn]
  treat_missing_data  = "notBreaching"

  tags = { Name = "failed-console-logins" }
}

resource "aws_cloudwatch_metric_alarm" "cloudtrail_stopped" {
  alarm_name          = "cloudtrail-stopped"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "CloudTrailStoppedCount"
  namespace           = "SecurityMetrics"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "CloudTrail logging stopped — potential attacker covering tracks"
  alarm_actions       = [aws_sns_topic.cloudtrail_stopped.arn]
  treat_missing_data  = "notBreaching"

  tags = { Name = "cloudtrail-stopped" }
}

# ─── INFRASTRUCTURE ALARMS ───────────────────────────────────────────────────

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "Netflix-CPU-High"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "EC2 CPU above 80%"
  alarm_actions       = [aws_sns_topic.netflix_alerts.arn]
  treat_missing_data  = "notBreaching"

  tags = { Name = "Netflix-CPU-High" }
}

resource "aws_cloudwatch_metric_alarm" "rds_connections" {
  alarm_name          = "rds-connections-spike"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "RDS connections above 80"
  alarm_actions       = [aws_sns_topic.netflix_alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = "netflix-production-db-v2"
  }

  tags = { Name = "rds-connections-spike" }
}

resource "aws_cloudwatch_metric_alarm" "high_response_time" {
  alarm_name          = "high-response-time"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "AvgResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = 2000
  alarm_description   = "ALB average response time above 2 seconds"
  alarm_actions       = [aws_sns_topic.netflix_alerts.arn]
  treat_missing_data  = "notBreaching"

  tags = { Name = "high-response-time" }
}

resource "aws_cloudwatch_metric_alarm" "high_error_rate" {
  alarm_name          = "high-error-rate-500s"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ErrorCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "More than 10 HTTP 500 errors in 1 minute"
  alarm_actions       = [aws_sns_topic.netflix_alerts.arn]
  treat_missing_data  = "notBreaching"

  tags = { Name = "high-error-rate-500s" }
}

# ─── CLOUDWATCH DASHBOARD ────────────────────────────────────────────────────
# Single pane of glass — network traffic, ALB requests, healthy hosts

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "Netflix-Dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 8
        height = 6
        properties = {
          title  = "NetworkIn, NetworkOut"
          view   = "timeSeries"
          region = "eu-west-1"
          metrics = [
            ["AWS/EC2", "NetworkIn"],
            ["AWS/EC2", "NetworkOut"]
          ]
          period = 300
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 0
        width  = 8
        height = 6
        properties = {
          title  = "RequestCount"
          view   = "timeSeries"
          region = "eu-west-1"
          metrics = [
            ["AWS/ApplicationELB", "RequestCount",
            "LoadBalancer", "app/aws-onlinebaqqala-store/6fb75064023014e9"]
          ]
          period = 300
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 0
        width  = 8
        height = 6
        properties = {
          title  = "HealthyHostCount"
          view   = "timeSeries"
          region = "eu-west-1"
          metrics = [
            ["AWS/ApplicationELB", "HealthyHostCount",
              "LoadBalancer", "app/aws-onlinebaqqala-store/6fb75064023014e9",
            "TargetGroup", "targetgroup/Netflix-WebServers-TG/72f615db3ab9f1f5"]
          ]
          period = 300
        }
      }
    ]
  })
}
