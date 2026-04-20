# onlinebaqqala.store — AWS Cloud Security Project

Built this as a hands-on AWS learning project. Every component was first built manually through the console to understand it, then written as Terraform IaC.

**Live site:** https://aws.onlinebaqqala.store

---

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [VPC + Networking](#vpc--networking)
- [Security Groups](#security-groups)
- [Network ACLs](#network-acls)
- [KMS — Customer Managed Key](#kms--customer-managed-key)
- [Secrets Manager](#secrets-manager)
- [IAM](#iam)
- [RDS MySQL](#rds-mysql)
- [S3 Buckets](#s3-buckets)
- [ALB — Application Load Balancer](#alb--application-load-balancer)
- [Launch Template + Auto Scaling Group](#launch-template--auto-scaling-group)
- [CloudWatch — Monitoring + Security Detection](#cloudwatch--monitoring--security-detection)
- [CloudTrail](#cloudtrail)
- [VPC Flow Logs](#vpc-flow-logs)
- [GuardDuty](#guardduty)
- [Security Hub](#security-hub)
- [AWS Config](#aws-config)
- [Lambda — Order Notification](#lambda--order-notification)
- [ISS Tracker](#iss-tracker-separate-project)
- [Roadmap](#roadmap)

---

## Architecture Overview

Three-tier VPC architecture across 3 availability zones in `eu-west-1`.

```
Internet
   │
   ▼
[ALB — Public Subnets]
   │  HTTPS only, TLS 1.3 minimum
   ▼
[EC2 / ASG — Private App Subnets]
   │  Port 80 from ALB SG only
   ▼
[RDS MySQL — Private DB Subnets]
      Port 3306 from EC2 SG only
```

> 📸 `docs/screenshots/architecture-overview.png`

---

## VPC + Networking

**VPC:** `NetflixProductionVPC` — `10.0.0.0/16`

Three subnet tiers, defence in depth:

| Tier | Subnets | CIDR Range | Purpose |
|------|---------|------------|---------|
| Public | 1a, 1b, 1c | 10.0.1–3.0/24 | ALB, NAT Gateway |
| Private App | 1a, 1b, 1c | 10.0.10–12.0/24 | EC2, ASG |
| Private DB | 1a, 1b | 10.0.20–21.0/24 | RDS MySQL |

**Internet Gateway:** `NetflixProductionIGW` — attached to VPC, used by public subnets only.

**NAT Gateway:** Single NAT in public subnet 1a — allows private EC2 to reach internet for Secrets Manager, package updates etc. Outbound only — nothing reaches EC2 from internet directly.

**Route tables:**
- Public RT — `0.0.0.0/0` → IGW
- Private RT — `0.0.0.0/0` → NAT Gateway
- DB RT — local only, no internet route

ALB sits in public subnets. EC2 moved to private subnets — no public IPs. RDS in DB subnets — no internet at all. An attacker has to breach three network layers to reach the database.

> 📸 `docs/screenshots/vpc-subnets.png`
> 📸 `docs/screenshots/route-tables.png`

---

## Security Groups

Three security groups, chained by identity not IP address.

| Security Group | ID | Purpose |
|---|---|---|
| `Netflix-WebServer-SG` | sg-09e600db03308b475 | ALB — accepts HTTP/HTTPS from internet |
| `Netflix-Private-EC2-SG` | sg-07e0e46e4f2fc9af9 | EC2 — accepts port 80 from ALB SG only |
| `Netflix-DB-SG` | sg-00c763275de9788b8 | RDS — accepts 3306 from EC2 SG only |

Security group chaining — RDS doesn't allow a CIDR range, it allows traffic only from instances carrying `Netflix-Private-EC2-SG`. An EC2 in the same VPC without that SG cannot reach the database.

> 📸 `docs/screenshots/security-groups.png`

---

## Network ACLs

Stateless subnet-level firewall — second layer of defence after security groups. Three NACLs, one per tier.

| NACL | Subnets | Inbound | Outbound |
|---|---|---|---|
| `Netflix-NACL-Public` | 3 public | HTTP, HTTPS, ephemeral, SSH from admin IP | HTTP, HTTPS, MySQL to DB subnets, ephemeral |
| `Netflix-NACL-Private` | 3 private app | HTTP/HTTPS from public subnets only, ephemeral | MySQL to DB subnets, HTTP/HTTPS to internet, ephemeral to public |
| `Netflix-NACL-Database` | 2 DB subnets | MySQL 3306 from private app subnets only | Ephemeral 1024–65535 back to private app subnets only |

NACLs are stateless — every connection needs explicit inbound AND outbound rules including return traffic on ephemeral ports 1024–65535. The DB NACL has zero internet access — inbound MySQL only, outbound ephemeral only. Nothing else gets in or out.

Learned this the hard way — spent hours debugging why private EC2 couldn't reach RDS. Wrong NACL was being edited. The DB subnets were using the default VPC NACL, not the named one. Always check which NACL is actually attached to the subnet, not just which one has the right name.

> 📸 `docs/screenshots/nacl-rules-database.png`

---

## KMS — Customer Managed Key

One CMK covers all encryption across the project.

**Key:** `netflix-production-key`
**ID:** `572926c2-6e1b-4ccf-ac3b-cf2cce95d588`
**Type:** Symmetric, AES-256
**Rotation:** Enabled — auto-rotates annually
**Used by:** RDS at-rest encryption, CloudTrail log encryption, Secrets Manager, S3

Key policy separates administration from usage:
- `ryzk-admin` — full key management + usage
- `cloudtrail.amazonaws.com` — `GenerateDataKey` only (envelope encryption for logs)
- `Netflix-EC2-Role` — `Encrypt`/`Decrypt` (for Secrets Manager access)

Envelope encryption — KMS generates a data key, data key encrypts the actual data, CMK encrypts the data key. CMK never touches raw data.

> 📸 `docs/screenshots/kms-key-policy.png`

---

## Secrets Manager

**Secret:** `prod/netflix-app/rds`
**ARN:** `arn:aws:secretsmanager:eu-west-1:441464446441:secret:prod/netflix-app/rds-87S0rA`
**Encryption:** `netflix-production-key` (CMK)
**Rotation:** Manual

Stores RDS credentials as JSON — username, password, host, port, dbname. App fetches at runtime using AWS SDK `GetSecretValue` call. Credentials exist only in memory, never written to disk or config files.

Two permission checks on every fetch:
- IAM — does `Netflix-EC2-Role` have `secretsmanager:GetSecretValue`?
- KMS — does `Netflix-EC2-Role` have `kms:Decrypt` on `netflix-production-key`?

Both must allow or the fetch fails.

> 📸 `docs/screenshots/secrets-manager.png`

---

## IAM

**User:** `ryzk-admin` — MFA enabled, used for console and CLI access only. Root account locked down — never used after initial setup.

**`Netflix-EC2-Role`** — attached to all EC2 instances via instance profile. Temporary credentials auto-rotated by AWS. Never stored on disk.

Inline policies follow least privilege:
- `allow-ami-creation` — EC2 image operations only
- `allow-app-buckets-only` — specific S3 buckets, specific actions
- `allow-cloudwatch-metrics` — put/get/list metrics only
- `netflix-db` — `GetSecretValue` on `prod/netflix-app/rds` only
- `AmazonSSMManagedInstanceCore` — SSM Session Manager (no SSH needed)
- `CloudWatchAgentServerPolicy` — CloudWatch agent metrics and logs

**`github-actions-oidc-role`** — assumed by GitHub Actions via OIDC. No stored credentials anywhere. GitHub generates a short-lived JWT per workflow run. AWS verifies it and issues temporary credentials. Only repo `uerruk/aws-onlinebaqqala` can assume this role.

Trust policy uses `StringLike` on the `sub` claim so any branch or workflow in that repo can deploy — tightening to `refs/heads/main` only is on the roadmap.

**OIDC Provider:** `token.actions.githubusercontent.com` — eliminates the need for long-lived AWS access keys in GitHub secrets.

> 📸 `docs/screenshots/iam-roles.png`
> 📸 `docs/screenshots/github-oidc-trust-policy.png`

---

## RDS MySQL

**Primary:** `netflix-production-db-v2`
**Engine:** MySQL 8.4.7
**Class:** db.t4g.micro
**Storage:** 20GB gp2
**AZ:** eu-west-1b
**Multi-AZ:** No — single AZ with read replica for read scaling
**Encryption:** Enabled — `netflix-production-key` (CMK)
**Public access:** Disabled — private DB subnets only
**Backup:** 7 days retention, daily automated snapshots
**Deletion protection:** Enabled on both primary and replica

**Read Replica:** `netflix-production-db-replica`
Asynchronous replication from primary. Used to offload SELECT queries. Tested and verified — site loaded products from replica endpoint with 0 seconds replication lag.

**Subnet group:** `netflix-db-subnet-group`
Covers only DB subnets `10.0.20.0/24` and `10.0.21.0/24`. No public or app subnets included — RDS cannot be placed outside DB tier.

Multi-AZ vs Read Replica distinction:
- Read Replica = async replication, readable standby, manual promotion
- Multi-AZ = sync replication, non-readable standby, automatic failover

> 📸 `docs/screenshots/rds-primary.png`
> 📸 `docs/screenshots/rds-replica-lag.png`

---

## S3 Buckets

Two buckets, opposite security postures by design.

**`netflix-frontend-ryzk-441464446441-eu-west-1-an`**
- Purpose: static frontend assets
- Public read: enabled — website visitors download HTML/CSS/JS
- Block Public Access: off — required for static website hosting
- Encryption: SSE-KMS with `netflix-production-key`
- Versioning: enabled
- Static website hosting: enabled
- Bucket Key: enabled — reduces KMS API calls, lowers cost

**`netflix-videos-ryzk-441464446441-eu-west-1-an`**
- Purpose: video and media content
- Public read: blocked — app access only
- Block Public Access: on
- Bucket policy: explicit deny to everyone except `Netflix-EC2-Role`, `ryzk-admin`, and root account
- Encryption: SSE-KMS with `netflix-production-key`
- Versioning: enabled

Both buckets use SSE-KMS with the project CMK — encrypted at rest even though frontend objects are publicly readable. Encryption protects data at the storage layer regardless of access policy.

Intended architecture with CloudFront (pending AWS approval):
- CloudFront → static assets from S3 (images, CSS, JS)
- CloudFront → dynamic requests via ALB → EC2 → Node.js

This offloads static serving from EC2 entirely.

> 📸 `docs/screenshots/s3-buckets.png`
> 📸 `docs/screenshots/s3-videos-bucket-policy.png`

---

## ALB — Application Load Balancer

**Name:** `aws-onlinebaqqala-store`
**Scheme:** Internet-facing
**Subnets:** 3 public subnets across eu-west-1a, eu-west-1b, eu-west-1c
**Security group:** `Netflix-WebServer-SG` — port 80 and 443 from internet only

**Listeners:**
- `HTTPS:443` → forward to `Netflix-WebServers-TG`
  - Certificate: `aws.onlinebaqqala.store` (ACM)
  - TLS policy: `ELBSecurityPolicy-TLS13-1-2-2021-06` — TLS 1.3 minimum
- `HTTP:80` → redirect to HTTPS (301 permanent) — no plain HTTP ever reaches EC2

**Target Group:** `Netflix-WebServers-TG`
Protocol: HTTP, Port: 80
Health check: `GET /health` → expects 200, 30s interval, 2/2 threshold
ALB removes instance from rotation if 2 consecutive checks fail.

SSL termination at ALB — EC2 instances receive plain HTTP internally. Certificate managed by ACM — auto-renews, no manual certificate management. EC2 in private subnets with no public IP — only reachable through ALB. Direct access to EC2 port 80 from internet is impossible.

> 📸 `docs/screenshots/alb-listeners.png`
> 📸 `docs/screenshots/alb-target-group-healthy.png`

---

## Launch Template + Auto Scaling Group

**Launch Template:** `onlinebaqqala.store` (`lt-0d60a1503c2d77f71`)
- Current version: 11 — updated by CI/CD after every deployment
- AMI: `ami-05508268899a20e73` (`onlinebaqqala-private-production-v1`)
- Instance type: t2.micro
- Security group: `Netflix-Private-EC2-SG` — port 80 from ALB only
- IAM profile: `Netflix-EC2-Role`
- IMDSv2: Required — blocks SSRF credential theft attacks

**Auto Scaling Group:** `onlinebaqqala-asg`
- Capacity: min 1, desired 1, max 3
- Subnets: 3 private app subnets across all AZs
- Health checks: EC2 + ELB — both must pass
- Grace period: 120 seconds — allows app startup before health checks begin
- Cooldown: 300 seconds — prevents scaling thrash

CI/CD flow: git push → GitHub Actions → SSM deploy to EC2 → bake new AMI → create new Launch Template version → set as default → ASG uses new AMI on next instance refresh or scale-out event.

IMDSv2 explanation: IMDSv1 allowed any GET request to `169.254.169.254` to steal IAM credentials via SSRF. IMDSv2 requires a PUT request first to get a session token — most SSRF only allows GET so credential theft is blocked.

> 📸 `docs/screenshots/launch-template.png`
> 📸 `docs/screenshots/asg-activity.png`

---

## CloudWatch — Monitoring + Security Detection

**Dashboard:** `Netflix-Dashboard`
3 widgets — NetworkIn/NetworkOut, ALB RequestCount, HealthyHostCount

**Log Groups (8):**
- `/aws/cloudtrail/online-baqqala` — CloudTrail API logs, 5 metric filters
- `/aws/vpc/flowlogs` — VPC network flow data
- `/aws/rds/instance/netflix-production-db-v2/error` — RDS error logs
- `/aws/lambda/order-notification` — Lambda execution logs
- `/aws/lambda/ISS-Tracker` — ISS project Lambda logs
- `/onlinebakala/app/errors` — Node.js application errors
- `/onlinebakala/app/stdout` — Node.js application output

**5 Security Event Alarms (CloudTrail → Metric Filter → Alarm → SNS):**

| Alarm | Trigger | SNS Topic |
|---|---|---|
| `root-login-detected` | Any root account login | `security-alerts` |
| `iam-policy-changes` | IAM policy attach/detach | `security-alerts-iam-policy-change` |
| `security-group-changes` | SG create/delete/modify | `security-event-security-group-change` |
| `failed-console-logins` | 3+ failed logins in 5 min | `security-event-failed-login-count` |
| `cloudtrail-stopped` | `StopLogging` API call | `security-event-cloudtrail-stopped` |

`cloudtrail-stopped` is the most critical — an attacker's first move after compromising an account is often to stop CloudTrail to cover their tracks. This alarm fires within 5 minutes.

**4 Infrastructure Alarms:**
- `Netflix-CPU-High` — EC2 CPU > 80%
- `rds-connections-spike` — RDS connections > 80
- `high-response-time` — ALB response time > 2 seconds
- `high-error-rate-500s` — more than 10 HTTP 500s per minute

**SNS Topics (6):** one per security event type + `Netflix-Alerts` for infrastructure. Each topic has email subscription to `adimkhyzar@gmail.com`.

> 📸 `docs/screenshots/cloudwatch-dashboard.png`
> 📸 `docs/screenshots/cloudwatch-alarms.png`
> 📸 `docs/screenshots/metric-filters.png`

---

## CloudTrail

**Trail:** `Netflix-Audit-Trail`
**Multi-region:** Yes — captures API calls across all regions
**S3 bucket:** `aws-cloudtrail-logs-441464446441-9b067ce7`
**KMS encryption:** `netflix-production-key` (CMK)
**CloudWatch Logs:** `/aws/cloudtrail/online-baqqala`
**Management events:** All — read and write
**Log file validation:** Disabled
**Insights:** Disabled

Encryption flow — CloudTrail calls KMS `GenerateDataKey`, encrypts log file with data key, stores encrypted log + encrypted data key in S3. To read logs you need `kms:Decrypt` on `netflix-production-key`. Bucket access alone is not enough.

CloudTrail → CloudWatch Logs pipeline enables the 5 security event alarms. Every API call lands in the log group within minutes, metric filters scan for patterns, alarms fire within one period (5 min).

> 📸 `docs/screenshots/cloudtrail-trail.png`
> 📸 `docs/screenshots/cloudtrail-s3-encrypted-logs.png`

---

## VPC Flow Logs

**Flow Log ID:** `fl-0b94bddd3d3e06fe5`
**Resource:** `NetflixProductionVPC` (entire VPC)
**Traffic type:** ALL — ACCEPT and REJECT records
**Destination:** CloudWatch Logs — `/aws/vpc/flowlogs`
**Aggregation:** 60 seconds
**IAM Role:** `Netflix-FlowLogs-Role`

Log format captures 14 fields per record:
```
version, account-id, interface-id, srcaddr, dstaddr, srcport,
dstport, protocol, packets, bytes, start, end, action, log-status
```

**Security use cases:**

Port scan detection — attacker scanning generates thousands of REJECT records from one `srcaddr` in a short window. GuardDuty uses flow logs internally to detect this automatically.

Data exfiltration detection — large `bytes` values on unexpected outbound connections indicate potential data theft.

NACL and SG troubleshooting — REJECT records show exactly which traffic is being blocked and at which layer. Spent hours debugging private EC2 to RDS connectivity — flow logs would have shown the REJECT on port 3306 at the DB subnet NACL immediately. Now the first thing I check.

**Useful CloudWatch Logs Insights query:**
```
fields srcAddr, dstAddr, dstPort, action
| filter action = "REJECT"
| stats count(*) as rejectCount by srcAddr, dstPort
| sort rejectCount desc
| limit 20
```

> 📸 `docs/screenshots/vpc-flow-logs.png`
> 📸 `docs/screenshots/flow-logs-insights-query.png`

---

## GuardDuty

**Detector ID:** `4cce78c7346ad8171f2be0b44899f562`
**Status:** Active
**Data sources:** CloudTrail, VPC Flow Logs, DNS logs, S3 logs, EBS malware scanning

Managed threat detection — no rules to configure. GuardDuty analyses traffic and API patterns using ML and AWS threat intelligence feeds.

Key finding types for this project:
- `Recon:EC2/PortProbeUnprotectedPort` — port scanning detection
- `UnauthorizedAccess:EC2/SSHBruteForce` — brute force attempts
- `Stealth:IAMUser/CloudTrailLoggingDisabled` — attacker covering tracks
- `CryptoCurrency:EC2/BitcoinTool.B` — crypto mining on EC2

Red team attack simulation planned — GuardDuty configured to catch nmap scans, nikto probes, and SSRF attempts against IMDSv2.

> 📸 `docs/screenshots/guardduty-active.png`

---

## Security Hub

**Status:** Enabled
**Auto-enable controls:** Yes

**Standards enabled:**
- CIS AWS Foundations Benchmark v1.2.0 — industry standard baseline
- AWS Foundational Security Best Practices v1.0.0 — AWS curated checks

Aggregates findings from GuardDuty and AWS Config into single view. Single pane of glass for security posture across all services.

> 📸 `docs/screenshots/security-hub-findings.png`

---

## AWS Config

**Recorder:** default — ALL supported resource types, continuous
**IAM resources:** daily recording frequency
**Delivery:** S3 bucket `aws-config-logs`

**7 Custom Config Rules:**

| Rule | What it checks |
|---|---|
| `ec2-imdsv2-check` | All EC2 instances require IMDSv2 |
| `encrypted-volumes` | All EBS volumes are encrypted |
| `iam-root-access-key-check` | Root account has no access keys |
| `iam-user-mfa-enabled` | All IAM users have MFA |
| `rds-instance-deletion-protection-enabled` | RDS has deletion protection |
| `restricted-ssh` | No security group allows SSH from `0.0.0.0/0` |
| `s3-bucket-public-read-prohibited` | No S3 bucket allows public read |

Config answers: what did my security group look like 2 weeks ago? Was my S3 bucket ever publicly accessible? Who changed this rule and when? Essential for compliance audits and incident investigations.

> 📸 `docs/screenshots/aws-config-rules.png`

---

## Lambda — Order Notification

**Function:** `order-notification`
**Runtime:** Node.js 22.x
**Memory:** 128MB
**Timeout:** 3 seconds
**Handler:** `index.handler`

Sends order confirmation email to customers via SES after a successful order. Tested manually — returned 200 with `MessageId`. Email delivered to `adimkhyzar@gmail.com` in test.

**Integration flow (once SES production access approved):**
Customer places order → `server.js` saves to RDS → invokes Lambda async (`InvocationType: Event`) → Lambda sends confirmation email. Async invocation means order response is not delayed by email sending.

**SES status:**
- `adimkhyzar@gmail.com` — verified
- `onlinebaqqala.store` domain — verified
- Production access — pending AWS approval
- Sandbox limitation: currently only sends to verified addresses

**IAM permissions:**
- `ses:SendEmail`, `ses:SendRawEmail` — send emails
- `logs:CreateLogStream`, `logs:PutLogEvents` — CloudWatch logging

> 📸 `docs/screenshots/lambda-function.png`
> 📸 `docs/screenshots/ses-test-email.png`

---

## ISS Tracker (Separate Project)

Separate AWS learning project — different account, own repository. Captures ISS coordinates via public API, stores in S3, cross-account bucket transfer using STS AssumeRole.

Demonstrates: EventBridge scheduled triggers, Lambda, cross-account IAM with STS, S3 cross-account access.

---

## Roadmap

Things that are understood and queued — not gaps, just not wired up yet.

- **CloudTrail log file validation** — CloudTrail generates a digest file with a SHA-256 hash of every log file. Running `aws cloudtrail validate-logs` proves logs were not tampered with after delivery — critical for forensic investigations.
- **Secrets Manager automatic rotation** — Secrets Manager generates a new password, updates RDS, updates the secret. Zero downtime credential rotation. Currently on manual rotation.
- **CloudFront distribution** — pending AWS approval. Will sit in front of both S3 and ALB, offloading static serving from EC2 entirely.
- **GuardDuty red team simulation** — nmap scan, nikto probe, SSRF attempt against IMDSv2 to verify findings fire correctly.
- **GitHub Actions OIDC trust policy** — tighten `StringLike` on `sub` claim from any branch in the repo to `refs/heads/main` only.
- **CloudTrail Insights** — currently disabled. Would automatically detect unusual API call volume patterns.
