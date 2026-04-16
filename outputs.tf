# ─── OUTPUTS ─────────────────────────────────────────────────────────────────
# Printed after terraform apply
# Also usable by other Terraform projects via remote state

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "alb_dns_name" {
  description = "ALB DNS name — use this to access the site"
  value       = aws_lb.main.dns_name
}

output "alb_arn" {
  description = "ALB ARN"
  value       = aws_lb.main.arn
}

output "rds_endpoint" {
  description = "RDS primary endpoint"
  value       = aws_db_instance.main.endpoint
  sensitive   = true
}

output "rds_replica_endpoint" {
  description = "RDS read replica endpoint"
  value       = aws_db_instance.replica.endpoint
  sensitive   = true
}

output "kms_key_arn" {
  description = "KMS CMK ARN — used for encryption across all services"
  value       = aws_kms_key.main.arn
}

output "kms_key_id" {
  description = "KMS CMK key ID"
  value       = aws_kms_key.main.key_id
}

output "cloudtrail_bucket" {
  description = "S3 bucket storing CloudTrail logs"
  value       = aws_s3_bucket.cloudtrail.bucket
}

output "frontend_bucket" {
  description = "S3 frontend bucket name"
  value       = aws_s3_bucket.frontend.bucket
}

output "frontend_website_endpoint" {
  description = "S3 static website endpoint"
  value       = aws_s3_bucket_website_configuration.frontend.website_endpoint
}

output "guardduty_detector_id" {
  description = "GuardDuty detector ID"
  value       = aws_guardduty_detector.main.id
}

output "nat_gateway_ip" {
  description = "NAT Gateway public IP — all private EC2 outbound traffic uses this"
  value       = aws_eip.nat.public_ip
}

output "private_app_subnet_ids" {
  description = "Private app subnet IDs — where EC2 and ASG run"
  value = [
    aws_subnet.private_app_1a.id,
    aws_subnet.private_app_1b.id,
    aws_subnet.private_app_1c.id,
  ]
}

output "db_subnet_ids" {
  description = "DB subnet IDs — where RDS runs"
  value = [
    aws_subnet.private_db_1a.id,
    aws_subnet.private_db_1b.id,
  ]
}

output "account_id" {
  description = "AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}
