# ─── SECRETS MANAGER — RDS CREDENTIALS ──────────────────────────────────────
# Stores RDS MySQL username and password
# App fetches credentials at runtime via AWS SDK
# Credentials never stored in files on EC2 or in Git
#
# Note: Currently uses aws/secretsmanager AWS managed key
# Improvement: migrate to CMK aws_kms_key.main.arn for full key control

resource "aws_secretsmanager_secret" "rds" {
  name        = "prod/netflix-app/rds"
  description = "RDS MySQL credentials for onlineBakala production"

  # To use your CMK instead of AWS managed key, replace with:
  kms_key_id = aws_kms_key.main.arn

  recovery_window_in_days = 7

  tags = {
    Name = "prod/netflix-app/rds"
  }
}

# ─── SECRET VALUE ────────────────────────────────────────────────────────────
# Stores the actual credentials as JSON
# username and password are the keys your server.js reads

resource "aws_secretsmanager_secret_version" "rds" {
  secret_id = aws_secretsmanager_secret.rds.id

  secret_string = jsonencode({
    username = "admin"
    password = var.db_password
    engine   = "mysql"
    host     = "netflix-production-db-v2.c76msgoueoc9.eu-west-1.rds.amazonaws.com"
    port     = 3306
    dbname   = "netflix"
  })
}

# ---------------------------------------------------------
# Secrets Manager Rotation — RDS MySQL Single User
# Lambda deployed via AWS SAR (not managed by Terraform)
# Rotates credentials every 30 days, zero downtime
# ---------------------------------------------------------

data "aws_lambda_function" "rotation_lambda" {
  function_name = "SecretsManagerRDSMySQLRotation"
}

resource "aws_lambda_permission" "allow_secretsmanager" {
  statement_id  = "AllowSecretsManagerInvoke"
  action        = "lambda:InvokeFunction"
  function_name = data.aws_lambda_function.rotation_lambda.function_name
  principal     = "secretsmanager.amazonaws.com"
  source_arn    = aws_secretsmanager_secret.rds.arn
}

resource "aws_secretsmanager_secret_rotation" "rds_rotation" {
  secret_id           = aws_secretsmanager_secret.rds.id
  rotation_lambda_arn = data.aws_lambda_function.rotation_lambda.arn

  rotation_rules {
    automatically_after_days = 30
  }
}
