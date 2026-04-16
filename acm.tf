# ─── ACM CERTIFICATE ─────────────────────────────────────────────────────────
# Data source — certificate already exists, we reference it not create it
# aws.onlinebaqqala.store — active, attached to ALB HTTPS listener
# ACM auto-renews before expiry — no manual certificate management
# DNS validation records added to Spaceship DNS

data "aws_acm_certificate" "main" {
  domain      = "aws.onlinebaqqala.store"
  statuses    = ["ISSUED"]
  most_recent = true
}

output "acm_certificate_arn" {
  description = "Active ACM certificate ARN for aws.onlinebaqqala.store"
  value       = data.aws_acm_certificate.main.arn
}
