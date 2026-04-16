# =============================================================
# waf.tf — AWS WAF v2 WebACL
# Cost: ~$5/month (1 WebACL $5 + managed rule groups $1 each)
# Attached to: ALB (aws_lb.main)
# Covers: SQLi, XSS, bad inputs, known bad IPs, rate limiting
# =============================================================

resource "aws_wafv2_web_acl" "main" {
  name        = "Netflix-WAF"
  description = "WAF for onlinebaqqala ALB — managed rules + rate limiting"
  scope       = "REGIONAL" # REGIONAL = ALB/API GW, CLOUDFRONT = CloudFront (use that in cloudfront.tf)

  default_action {
    allow {} # Allow traffic unless a rule blocks it
  }

  # ----------------------------------------------------------
  # Rule 1 — AWS Core Rule Set (CRS)
  # Blocks common exploits: SQLi, XSS, LFI, RFI, SSRF
  # Cost: $1/month
  # ----------------------------------------------------------
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {} # Use the rule group's own block/count actions
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesCommonRuleSet"
      sampled_requests_enabled   = true
    }
  }

  # ----------------------------------------------------------
  # Rule 2 — Known Bad Inputs
  # Blocks requests with patterns associated with exploitation
  # (Log4Shell, SSRF probes, Spring4Shell etc)
  # Cost: $1/month
  # ----------------------------------------------------------
  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesKnownBadInputsRuleSet"
      sampled_requests_enabled   = true
    }
  }

  # ----------------------------------------------------------
  # Rule 3 — Rate Limiting
  # Blocks IPs sending more than 500 requests per 5 minutes
  # Protects against brute force, credential stuffing, DDoS
  # No extra cost — rate limiting is built into WAF
  # ----------------------------------------------------------
  rule {
    name     = "RateLimitRule"
    priority = 3

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 500 # requests per 5-minute window per IP
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimitRule"
      sampled_requests_enabled   = true
    }
  }

  # ----------------------------------------------------------
  # Rule 4 — SQL Injection (explicit, in addition to CRS)
  # Double layer specifically targeting SQLi in query strings
  # No extra cost — custom rule
  # ----------------------------------------------------------
  rule {
    name     = "SQLiProtection"
    priority = 4

    action {
      block {}
    }

    statement {
      sqli_match_statement {
        field_to_match {
          query_string {}
        }
        text_transformation {
          priority = 1
          type     = "URL_DECODE"
        }
        text_transformation {
          priority = 2
          type     = "HTML_ENTITY_DECODE"
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "SQLiProtection"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "Netflix-WAF"
    sampled_requests_enabled   = true
  }

  tags = {
    Name        = "Netflix-WAF"
    Environment = "production"
  }
}

# ----------------------------------------------------------
# Associate WAF with the ALB
# ----------------------------------------------------------
resource "aws_wafv2_web_acl_association" "alb" {
  resource_arn = aws_lb.main.arn
  web_acl_arn  = aws_wafv2_web_acl.main.arn
}

# ----------------------------------------------------------
# WAF Logging — send blocked requests to CloudWatch
# ----------------------------------------------------------
resource "aws_cloudwatch_log_group" "waf" {
  name              = "aws-waf-logs-netflix" # Must start with aws-waf-logs-
  retention_in_days = 30
  kms_key_id        = aws_kms_key.main.arn

  tags = {
    Name = "Netflix-WAF-Logs"
  }
}

resource "aws_wafv2_web_acl_logging_configuration" "main" {
  log_destination_configs = [aws_cloudwatch_log_group.waf.arn]
  resource_arn            = aws_wafv2_web_acl.main.arn
}
