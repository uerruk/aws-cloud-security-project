# ─── GUARDDUTY ───────────────────────────────────────────────────────────────
# Managed threat detection — analyses CloudTrail, VPC Flow Logs, DNS logs
# Uses ML and AWS threat intelligence feeds
# No rules to configure — enable and review findings
#
# Detects: port scanning, crypto mining, C2 communication,
# credential compromise, unusual API patterns, brute force attacks

resource "aws_guardduty_detector" "main" {
  enable = true

  datasources {
    s3_logs {
      enable = true
    }
    kubernetes {
      audit_logs {
        enable = false
      }
    }
    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes {
          enable = true
        }
      }
    }
  }

  tags = {
    Name = "onlinebaqqala-guardduty"
  }
}
