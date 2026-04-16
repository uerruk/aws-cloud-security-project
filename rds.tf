# ─── DB SUBNET GROUP ─────────────────────────────────────────────────────────
# Defines which subnets RDS can use
# Only DB subnets — 10.0.20.0/24 and 10.0.21.0/24
# Kept separate from app and public subnets — most restricted tier

resource "aws_db_subnet_group" "main" {
  name        = "netflix-db-subnet-group"
  description = "Managed by Terraform"

  subnet_ids = [
    aws_subnet.private_db_1a.id,
    aws_subnet.private_db_1b.id,
  ]

  tags = {
    Name        = "Netflix DB Subnet Group"
    Environment = "production"
  }
}

# ─── RDS MYSQL PRIMARY INSTANCE ──────────────────────────────────────────────
# MySQL 8.4.7 — db.t4g.micro — 20GB gp2
# Encrypted with CMK netflix-production-key
# No public access — private DB subnets only
# Deletion protection enabled — cannot be deleted from console accidentally

resource "aws_db_instance" "main" {
  identifier     = "netflix-production-db-v2"
  engine         = "mysql"
  engine_version = "8.4.7"
  instance_class = "db.t4g.micro"

  db_name  = "netflix"
  username = "admin"
  password = var.db_password

  # Storage
  allocated_storage = 20
  storage_type      = "gp2"
  storage_encrypted = true
  kms_key_id        = aws_kms_key.main.arn

  # Network
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  availability_zone      = "eu-west-1b"

  # Backup
  backup_retention_period = 7
  backup_window           = "23:39-00:09"
  copy_tags_to_snapshot   = true

  # Maintenance
  maintenance_window         = "Sun:07:09-Sun:07:39"
  auto_minor_version_upgrade = true

  # Logs to CloudWatch
  enabled_cloudwatch_logs_exports = ["error", "slowquery"]

  # Enhanced monitoring — 60 second granularity
  # Fixes: securityhub-rds-enhanced-monitoring-enabled
  monitoring_interval = 60
  monitoring_role_arn = "arn:aws:iam::441464446441:role/rds-monitoring-role"

  # IAM database authentication
  # Fixes: securityhub-rds-instance-iam-authentication-enabled
  iam_database_authentication_enabled = true

  # Protection
  deletion_protection       = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "netflix-production-db-v2-final-snapshot"

  # Multi-AZ disabled — single AZ, read replica used for read scaling
  multi_az = false

  tags = {
    Name = "netflix-production-db-v2"
  }
}

# ─── RDS READ REPLICA ────────────────────────────────────────────────────────
# Asynchronous replica of primary — used for SELECT queries
# Reduces load on primary — separates read and write traffic
# Encrypted — inherits encryption from primary
# Deletion protection enabled

resource "aws_db_instance" "replica" {
  identifier          = "netflix-production-db-replica"
  replicate_source_db = aws_db_instance.main.identifier
  instance_class      = "db.t4g.micro"

  # Storage — inherited from primary
  storage_type      = "gp2"
  storage_encrypted = true
  kms_key_id        = aws_kms_key.main.arn

  # Network
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  availability_zone      = "eu-west-1b"

  # No backup on replica
  backup_retention_period = 0

  # Maintenance
  auto_minor_version_upgrade = true

  # Protection
  deletion_protection = true
  skip_final_snapshot = true

  tags = {
    Name = "netflix-production-db-replica"
  }
}
