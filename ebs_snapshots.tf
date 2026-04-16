# ─── EBS ACCOUNT-LEVEL ENCRYPTION ────────────────────────────────────────────
# Encrypts all new EBS volumes by default — account-wide setting
# Any EC2 launched without explicit encryption gets encrypted automatically
# Fixes: encrypted-volumes Config rule

resource "aws_ebs_encryption_by_default" "main" {
  enabled = true
}

# ─── EBS SNAPSHOT PUBLIC ACCESS BLOCK ────────────────────────────────────────
# Prevents any EBS snapshot from being shared publicly — account-wide
# An attacker cannot make a snapshot public even if they compromise an EC2
# Fixes: securityhub-ebs-snapshot-block-public-access

resource "aws_ebs_snapshot_block_public_access" "main" {
  state = "block-all-sharing"
}
