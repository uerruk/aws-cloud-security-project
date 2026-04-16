# ─── SECURITY HUB ────────────────────────────────────────────────────────────
# Aggregates findings from GuardDuty, Config, Inspector into one place
# Runs automated security standard checks across the account
# Auto-enables new controls as AWS adds them

resource "aws_securityhub_account" "main" {
  auto_enable_controls      = true
  control_finding_generator = "SECURITY_CONTROL"
}

# ─── CIS AWS FOUNDATIONS BENCHMARK v1.2.0 ────────────────────────────────────
# Industry standard security baseline for AWS accounts
# Covers IAM, logging, monitoring, networking

resource "aws_securityhub_standards_subscription" "cis" {
  depends_on    = [aws_securityhub_account.main]
  standards_arn = "arn:aws:securityhub:::ruleset/cis-aws-foundations-benchmark/v/1.2.0"
}

# ─── AWS FOUNDATIONAL SECURITY BEST PRACTICES v1.0.0 ─────────────────────────
# AWS-curated checks across 30+ services
# Checks encryption, public access, logging, backup, MFA etc

resource "aws_securityhub_standards_subscription" "aws_fsbp" {
  depends_on    = [aws_securityhub_account.main]
  standards_arn = "arn:aws:securityhub:eu-west-1::standards/aws-foundational-security-best-practices/v/1.0.0"
}
