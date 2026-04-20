# AWS Cloud Security Project — onlinebaqqala.store

Production AWS infrastructure built security-first, hands-on from the console up.
Every service was configured manually through the AWS console first to understand it deeply,
then written as Terraform IaC (now in a separate repo).

**Live site:** https://aws.onlinebaqqala.store  
**Terraform IaC:** https://github.com/uerruk/terraform-onlinebaqqala  
**Region:** eu-west-1 (Ireland)  
**Account:** 441464446441

> Built while preparing for **AWS SCS-C02 Security Specialty** and **SAA-C03 Solutions Architect**.
> Every design decision maps to a real exam domain — documented below.

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
- [CloudFront + WAF](#cloudfront--waf)
- [Launch Template + Auto Scaling Group](#launch-template--auto-scaling-group)
- [CloudWatch — Monitoring + Security Detection](#cloudwatch--monitoring--security-detection)
- [CloudTrail](#cloudtrail)
- [VPC Flow Logs](#vpc-flow-logs)
- [GuardDuty](#guardduty)
- [Security Hub](#security-hub)
- [AWS Config](#aws-config)
- [Lambda — Order Notification](#lambda--order-notification)
- [Terraform Backend](#terraform-backend)
- [Exam Readiness](#exam-readiness)
- [Gaps to Close — Next Phase](#gaps-to-close--next-phase)

---

## Architecture Overview

Three-tier VPC architecture across 3 Availability Zones in eu-west-1.
Defence in depth at every layer — network, compute, data, identity, and detection.

```
Internet
    │
    ▼
CloudFront (WAF attached) ──── S3 (static assets)
    │
    ▼
ALB (public subnets, TLS 1.3, ACM cert)
    │
    ▼
EC2 / ASG (private app subnets, no public IP, IMDSv2)
    │
    ▼
RDS MySQL (private DB subnets, encrypted, no internet)
```

Security services running across all layers:
CloudTrail → CloudWatch → SNS alerts | GuardDuty | Security Hub | AWS Config | KMS | Secrets Manager | VPC Flow Logs

---

## VPC + Networking

**VPC:** NetflixProductionVPC — `10.0.0.0/16`

Three subnet tiers enforce defence in depth:

| Tier | Subnets | CIDR Range | Purpose |
|---|---|---|---|
| Public | 1a, 1b, 1c | 10.0.1-3.0/24 | ALB, NAT Gateway |
| Private App | 1a, 1b, 1c | 10.0.10-12.0/24 | EC2, ASG |
| Private DB | 1a, 1b | 10.0.20-21.0/24 | RDS MySQL |

**Internet Gateway:** NetflixProductionIGW — attached to VPC, used by public subnets only.

**NAT Gateway:** Single NAT in public subnet 1a. Private EC2 instances reach the internet for Secrets Manager API calls and package updates — outbound only. Nothing from the internet reaches EC2 directly.

**Route tables:**
- Public RT → `0.0.0.0/0` → IGW
- Private RT → `0.0.0.0/0` → NAT Gateway
- DB RT → local only, no internet route at all

An attacker has to breach three network layers to reach the database.

![VPC Overview](docs/proofs/01-vpc-networking/vpc-overview.jpg)
![Subnets All Tiers](docs/proofs/01-vpc-networking/subnets-all-tiers.jpg)
![Route Tables](docs/proofs/01-vpc-networking/route-tables.jpg)
![Internet Gateway](docs/proofs/01-vpc-networking/igw.jpg)
![NAT Gateway](docs/proofs/01-vpc-networking/nat-gateway.jpg)

**Lesson learned:** Spent hours debugging why private EC2 could not reach RDS after NACL changes.
The DB subnets were still associated with the default VPC NACL, not the named one.
The fix shown below — after correcting the NACL association the site loaded immediately.

![NACL Fix — Site Loads](docs/proofs/01-vpc-networking/nacl-fix-site-loads.jpg)
![Private Subnet EC2 Access](docs/proofs/01-vpc-networking/private-subnet-ec2.jpg)

---

## Security Groups

Three security groups, chained by identity — not by IP address.

| Security Group | ID | Allows |
|---|---|---|
| Netflix-WebServer-SG | sg-09e600db03308b475 | HTTP/HTTPS from internet (0.0.0.0/0) |
| Netflix-Private-EC2-SG | sg-07e0e46e4f2fc9af9 | Port 80 from Netflix-WebServer-SG only |
| Netflix-DB-SG | sg-00c763275de9788b8 | Port 3306 from Netflix-Private-EC2-SG only |

**Security group chaining** means RDS does not allow a CIDR range — it allows traffic only from
instances carrying `Netflix-Private-EC2-SG`. An EC2 in the same VPC without that security group
cannot reach the database, even if it knows the RDS endpoint.

![All Security Groups](docs/proofs/02-security-groups/sg-all-three.jpg)
![ALB SG Inbound](docs/proofs/02-security-groups/sg-alb-inbound.jpg)
![EC2 SG Inbound — ALB only](docs/proofs/02-security-groups/sg-ec2-inbound.jpg)
![RDS SG Inbound — EC2 SG only](docs/proofs/02-security-groups/sg-rds-inbound.jpg)

---

## Network ACLs

Stateless subnet-level firewall — second layer of defence after security groups.
Three NACLs, one per tier. NACLs are evaluated before security groups reach the instance.

| NACL | Tier | Inbound | Outbound |
|---|---|---|---|
| Netflix-NACL-Public | 3 public subnets | HTTP, HTTPS, ephemeral | HTTP, HTTPS, MySQL to DB, ephemeral |
| Netflix-NACL-Private | 3 app subnets | HTTP/HTTPS from public subnets only, ephemeral | MySQL to DB, HTTPS to internet, ephemeral |
| Netflix-NACL-Database | 2 DB subnets | MySQL 3306 from private app subnets only | Ephemeral 1024-65535 back to app subnets only |

NACLs are stateless — every connection needs explicit inbound AND outbound rules including
return traffic on ephemeral ports 1024-65535. The DB NACL has zero internet access.
Inbound MySQL only, outbound ephemeral only. Nothing else enters or exits.

![Public NACL Inbound](docs/proofs/03-nacls/nacl-public-inbound.jpg)
![Public NACL Outbound](docs/proofs/03-nacls/nacl-public-outbound.jpg)
![Private NACL Inbound](docs/proofs/03-nacls/nacl-private-inbound.jpg)
![Private NACL Outbound](docs/proofs/03-nacls/nacl-private-outbound.jpg)
![DB NACL Inbound](docs/proofs/03-nacls/nacl-db-inbound.jpg)
![DB NACL Outbound](docs/proofs/03-nacls/nacl-db-outbound.jpg)

---

## KMS — Customer Managed Key

One CMK covers all encryption across the entire project.

| Property | Value |
|---|---|
| Key name | netflix-production-key |
| Key ID | 572926c2-6e1b-4ccf-ac3b-cf2cce95d588 |
| Type | Symmetric, AES-256 |
| Rotation | Enabled — auto-rotates annually |
| Used by | RDS, CloudTrail, Secrets Manager, S3 |

**Key policy** separates administration from usage:
- `ryzk-admin` — full key management and usage
- `cloudtrail.amazonaws.com` — `GenerateDataKey` only (envelope encryption for log files)
- `Netflix-EC2-Role` — `Encrypt` and `Decrypt` (for Secrets Manager access from EC2)

**Envelope encryption:** KMS generates a data key. The data key encrypts the actual data.
The CMK encrypts the data key. The CMK never touches raw data directly.
This is a core SCS-C02 exam concept.

![KMS Key and Rotation](docs/proofs/09-kms/kms-key-rotation.jpg)
![KMS Enabled](docs/proofs/09-kms/kms-enabled.jpg)

---

## Secrets Manager

| Property | Value |
|---|---|
| Secret name | prod/netflix-app/rds |
| ARN | arn:aws:secretsmanager:eu-west-1:441464446441:secret:prod/netflix-app/rds-87S0rA |
| Encryption | netflix-production-key (CMK) |
| Rotation | Manual — auto-rotation is a planned improvement (see Gaps section) |

Stores RDS credentials as JSON — username, password, host, port, dbname.
The application fetches credentials at runtime using `GetSecretValue`. Credentials
exist only in memory, never written to disk, environment variables, or config files.

**Two permission checks on every fetch:**
1. IAM — does `Netflix-EC2-Role` have `secretsmanager:GetSecretValue`?
2. KMS — does `Netflix-EC2-Role` have `kms:Decrypt` on `netflix-production-key`?

Both must allow or the fetch fails. This is the double-gate pattern for secrets access.

---

## IAM

**Admin user:** `ryzk-admin` — MFA enabled, used for console and CLI access only.
Root account locked down — MFA enabled, no access keys, never used after initial setup.

**Netflix-EC2-Role** — attached to all EC2 instances via instance profile.
Temporary credentials auto-rotated by AWS every few hours. Never stored on disk.

Inline policies follow strict least privilege:

| Policy | Allows |
|---|---|
| allow-ami-creation | EC2 image operations only |
| allow-app-buckets-only | Specific S3 buckets, specific actions |
| allow-cloudwatch-metrics | Put/get/list metrics only |
| netflix-db | GetSecretValue on prod/netflix-app/rds only |
| AmazonSSMManagedInstanceCore | SSM Session Manager — no SSH needed |
| CloudWatchAgentServerPolicy | CloudWatch agent metrics and logs |

**github-actions-oidc-role** — assumed by GitHub Actions via OIDC federation.
No stored credentials anywhere. GitHub generates a short-lived JWT per workflow run.
AWS verifies it against the OIDC provider and issues temporary credentials.
Only repo `uerruk/aws-onlinebaqqala` can assume this role.

**OIDC Provider:** `token.actions.githubusercontent.com` — eliminates long-lived AWS access keys
in GitHub secrets entirely. This is the industry standard for CI/CD to AWS.

![IAM Dashboard](docs/proofs/10-iam/iam-dashboard.jpg)
![IAM Roles](docs/proofs/10-iam/iam-roles.jpg)
![IAM Roles List](docs/proofs/10-iam/iam-roles-2.jpg)
![EC2 Role Policies](docs/proofs/10-iam/iam-ec2-role-policies.jpg)
![EC2 Role Trust](docs/proofs/10-iam/iam-ec2-role-trust.jpg)
![OIDC Role Permissions](docs/proofs/10-iam/iam-oidc-role-permissions.jpg)
![OIDC Role Trust Policy](docs/proofs/10-iam/iam-oidc-role-trust.jpg)
![Admin User ryzk](docs/proofs/10-iam/iam-admin-user.jpg)

---

## RDS MySQL

| Property | Value |
|---|---|
| Primary | netflix-production-db-v2 |
| Engine | MySQL 8.4.7 |
| Instance class | db.t4g.micro |
| Storage | 20GB gp2 |
| AZ | eu-west-1b |
| Multi-AZ | No — read replica used for read scaling |
| Encryption | Enabled — netflix-production-key (CMK) |
| Public access | Disabled — private DB subnets only |
| Backup retention | 7 days, daily automated snapshots |
| Deletion protection | Enabled on both primary and replica |

**Read Replica:** `netflix-production-db-replica` — asynchronous replication from primary.
Used to offload SELECT queries. Verified — site loaded products from replica endpoint
with 0 seconds replication lag.

**Subnet group:** `netflix-db-subnet-group` — covers only `10.0.20.0/24` and `10.0.21.0/24`.
No public or app subnets included. RDS cannot be placed outside the DB tier.

**SCS-C02 / SAA-C03 exam distinction:**
- Read Replica = async replication, readable standby, manual failover promotion
- Multi-AZ = sync replication, non-readable standby, automatic failover

![RDS Databases List](docs/proofs/06-rds/rds-databases-list.jpg)
![RDS Primary Configuration](docs/proofs/06-rds/rds-primary-config.jpg)
![RDS Connectivity and Security](docs/proofs/06-rds/rds-connectivity-security.jpg)
![RDS Connectivity and Security 2](docs/proofs/06-rds/rds-connectivity-security-2.jpg)
![RDS Backup and Maintenance](docs/proofs/06-rds/rds-backup-maintenance.jpg)
![RDS Subnet Group](docs/proofs/06-rds/rds-subnet-group.jpg)
![RDS Endpoint](docs/proofs/06-rds/rds-endpoint.jpg)
![RDS Replica Lag — 0 seconds](docs/proofs/06-rds/rds-replica-lag.jpg)
![RDS Working](docs/proofs/06-rds/rds-working.jpg)

---

## S3 Buckets

Two buckets, opposite security postures by design.

**netflix-frontend-ryzk-441464446441-eu-west-1-an**
- Purpose: static frontend assets (HTML, CSS, JS)
- Public read: enabled — required for static website hosting
- Encryption: SSE-KMS with netflix-production-key
- Versioning: enabled
- Bucket Key: enabled — reduces KMS API calls and cost

**netflix-videos-ryzk-441464446441-eu-west-1-an**
- Purpose: video and media content
- Block Public Access: all four settings ON
- Bucket policy: explicit deny to everyone except Netflix-EC2-Role, ryzk-admin, and root
- Encryption: SSE-KMS with netflix-production-key
- Versioning: enabled

Both buckets use SSE-KMS with the project CMK. Encryption protects data at the storage
layer regardless of bucket access policy. Even publicly readable objects are encrypted at rest.

---

## ALB — Application Load Balancer

| Property | Value |
|---|---|
| Name | aws-onlinebaqqala-store |
| Scheme | Internet-facing |
| Subnets | 3 public subnets — eu-west-1a, 1b, 1c |
| Security group | Netflix-WebServer-SG |

**Listeners:**
- `HTTPS:443` → forward to Netflix-WebServers-TG
  - Certificate: aws.onlinebaqqala.store (ACM managed, auto-renews)
  - TLS policy: `ELBSecurityPolicy-TLS13-1-2-2021-06` — TLS 1.3 minimum
- `HTTP:80` → redirect to HTTPS (301 permanent) — no plain HTTP ever reaches EC2

**Target Group:** `Netflix-WebServers-TG`
- Health check: `GET /health` → expects 200, 30s interval, 2/2 threshold
- ALB removes an instance from rotation after 2 consecutive failed checks

SSL terminates at the ALB. EC2 instances receive plain HTTP internally on port 80.
EC2 has no public IP — direct internet access to port 80 is impossible.

![ALB Overview](docs/proofs/04-alb-acm/alb-overview.jpg)
![ALB Details](docs/proofs/04-alb-acm/alb-details.jpg)
![ALB Listeners](docs/proofs/04-alb-acm/alb-listeners.jpg)
![ALB HTTPS Rules](docs/proofs/04-alb-acm/alb-https-rules.jpg)
![ALB Resource Map](docs/proofs/04-alb-acm/alb-resource-map.jpg)
![Target Group Health Check](docs/proofs/04-alb-acm/alb-targetgroup-healthy.jpg)

---

## CloudFront + WAF

CloudFront sits in front of the ALB as a global CDN layer, with WAF attached for
edge-level threat protection before traffic reaches the VPC.

**CloudFront distribution:**
- Origin 1: ALB — dynamic requests (Node.js app)
- Origin 2: S3 frontend bucket — static assets (HTML, CSS, JS, images)
- HTTPS only — HTTP to HTTPS redirect enforced at edge
- Custom domain: aws.onlinebaqqala.store via ACM certificate
- Static assets served from S3 directly — offloads EC2 entirely

**WAF WebACL — attached to CloudFront distribution:**

| Rule Group | Purpose |
|---|---|
| AWSManagedRulesCommonRuleSet | OWASP Top 10 — SQLi, XSS, path traversal |
| AWSManagedRulesKnownBadInputsRuleSet | Known malicious inputs and exploits |
| AWSManagedRulesAmazonIpReputationList | Blocks IPs on AWS threat intelligence feeds |

WAF operates at the edge — malicious requests are blocked before they consume
any EC2 or ALB capacity. This is the correct placement for DDoS and injection protection.

---

## Launch Template + Auto Scaling Group

| Property | Value |
|---|---|
| Launch Template | onlinebaqqala.store — lt-0d60a1503c2d77f71 |
| Current version | 11 — updated by CI/CD on every deployment |
| AMI | ami-05508268899a20e73 (onlinebaqqala-private-production-v1) |
| Instance type | t2.micro |
| Security group | Netflix-Private-EC2-SG |
| IAM profile | Netflix-EC2-Role |
| IMDSv2 | Required |

**IMDSv2 enforced:** IMDSv1 allowed any GET request to `169.254.169.254` to retrieve
IAM credentials — exploitable via SSRF. IMDSv2 requires a PUT request first to get a
session token. Most SSRF exploits use GET only, so credential theft is blocked.

**Auto Scaling Group:** `onlinebaqqala-asg`
- Capacity: min 1 / desired 1 / max 3
- Subnets: 3 private app subnets across all AZs
- Health checks: EC2 + ELB — both must pass
- Grace period: 120 seconds (allows app startup before health checks begin)
- Cooldown: 300 seconds (prevents scaling thrash)

**CI/CD flow:**
`git push` → GitHub Actions → SSM deploy to EC2 → bake new AMI →
create new Launch Template version → set as default → ASG uses new AMI on next refresh

![Launch Template](docs/proofs/05-ec2-asg/launch-template.jpg)
![ASG Overview](docs/proofs/05-ec2-asg/asg-overview.jpg)
![ASG Instance Management](docs/proofs/05-ec2-asg/asg-instance-management.jpg)

---

## CloudWatch — Monitoring + Security Detection

**Dashboard:** Netflix-Dashboard — 3 widgets showing NetworkIn/NetworkOut,
ALB RequestCount, and HealthyHostCount.

**Log Groups (7):**

| Log Group | Source |
|---|---|
| /aws/cloudtrail/online-baqqala | CloudTrail API calls — feeds 5 security alarms |
| /aws/vpc/flowlogs | VPC network flow records |
| /aws/rds/instance/netflix-production-db-v2/error | RDS error logs |
| /aws/lambda/order-notification | Lambda execution logs |
| /onlinebakala/app/errors | Node.js application errors |
| /onlinebakala/app/stdout | Node.js application output |

**5 Security Event Alarms (CloudTrail → Metric Filter → Alarm → SNS):**

| Alarm | Trigger | Why it matters |
|---|---|---|
| root-login-detected | Any root account console login | Root should never be used — any login is an incident |
| iam-policy-changes | IAM policy attach/detach/modify | Privilege escalation attempt indicator |
| security-group-changes | SG create/delete/modify | Network perimeter being changed |
| failed-console-logins | 3+ failed logins in 5 minutes | Brute force or credential stuffing in progress |
| cloudtrail-stopped | StopLogging API call | Attacker covering tracks — most critical alarm |

`cloudtrail-stopped` fires within 5 minutes. An attacker's first move after compromising
an account is often to disable CloudTrail to remove the audit trail.

**4 Infrastructure Alarms:**

| Alarm | Threshold |
|---|---|
| Netflix-CPU-High | EC2 CPU > 80% |
| rds-connections-spike | RDS connections > 80 |
| high-response-time | ALB response time > 2 seconds |
| high-error-rate-500s | More than 10 HTTP 500s per minute |

**SNS Topics:** 6 topics — one per security event type plus Netflix-Alerts for infrastructure.
All topics have email subscription to adimkhyzar@gmail.com.

![CloudWatch Dashboard](docs/proofs/16-cloudwatch/cloudwatch-dashboard.jpg)
![CloudWatch Alarms](docs/proofs/16-cloudwatch/cloudwatch-alarms.jpg)
![CloudWatch Log Groups](docs/proofs/16-cloudwatch/cloudwatch-log-groups.jpg)
![SNS Topics](docs/proofs/16-cloudwatch/sns-topics.jpg)

---

## CloudTrail

| Property | Value |
|---|---|
| Trail name | Netflix-Audit-Trail |
| Multi-region | Yes — captures API calls across all regions |
| S3 bucket | aws-cloudtrail-logs-441464446441-9b067ce7 |
| KMS encryption | netflix-production-key (CMK) |
| CloudWatch Logs | /aws/cloudtrail/online-baqqala |
| Management events | All — read and write |
| Log file validation | Enabled |

**Encryption flow:** CloudTrail calls KMS `GenerateDataKey`, encrypts the log file with
the data key, stores the encrypted log and encrypted data key in S3. To read logs you
need `kms:Decrypt` on `netflix-production-key`. Bucket access alone is not enough.

**Log file validation** generates a SHA-256 digest file for every log file delivered.
Running `aws cloudtrail validate-logs` proves logs were not tampered with after delivery —
critical evidence for forensic investigations and compliance audits.

**Pipeline:** CloudTrail → CloudWatch Logs → Metric Filters → Alarms → SNS → Email.
Every API call lands in the log group within minutes. Alarms fire within one 5-minute period.

![CloudTrail Dashboard](docs/proofs/15-cloudtrail/cloudtrail-dashboard.jpg)
![CloudTrail Details](docs/proofs/15-cloudtrail/cloudtrail-details.jpg)
![CloudTrail Details Updated](docs/proofs/15-cloudtrail/cloudtrail-details-updated.jpg)
![CloudTrail Management Events](docs/proofs/15-cloudtrail/cloudtrail-management-events.jpg)
![CloudTrail S3 Bucket](docs/proofs/15-cloudtrail/cloudtrail-s3-bucket.jpg)

---

## VPC Flow Logs

| Property | Value |
|---|---|
| Flow Log ID | fl-0b94bddd3d3e06fe5 |
| Resource | NetflixProductionVPC (entire VPC) |
| Traffic type | ALL — ACCEPT and REJECT records |
| Destination | CloudWatch Logs — /aws/vpc/flowlogs |
| Aggregation interval | 60 seconds |
| IAM Role | Netflix-FlowLogs-Role |

**14-field log format:** version, account-id, interface-id, srcaddr, dstaddr, srcport,
dstport, protocol, packets, bytes, start, end, action, log-status.

**Security use cases:**
- **Port scan detection** — thousands of REJECT records from one source IP in a short window
- **Data exfiltration detection** — unexpectedly large outbound byte counts
- **NACL/SG troubleshooting** — REJECT records show exactly which layer blocked the traffic

**Useful CloudWatch Logs Insights query for rejected traffic:**
```
fields srcAddr, dstAddr, dstPort, action
| filter action = "REJECT"
| stats count() as rejectCount by srcAddr
| sort rejectCount desc
| limit 20
```

![Flow Logs Overview](docs/proofs/01-vpc-networking/flow-logs-overview.jpg)
![Flow Logs Streams](docs/proofs/01-vpc-networking/flow-logs-streams.jpg)
![Flow Logs Actual Events](docs/proofs/01-vpc-networking/flow-logs-actual-events.jpg)

---

## GuardDuty

| Property | Value |
|---|---|
| Detector ID | 4cce78c7346ad8171f2be0b44899f562 |
| Status | Active |
| Data sources | CloudTrail, VPC Flow Logs, DNS logs, S3 logs, EBS malware scanning |

Managed threat detection — no rules to write. GuardDuty analyses traffic and API patterns
using ML models and AWS threat intelligence feeds continuously.

**Key finding types relevant to this project:**

| Finding | What it means |
|---|---|
| Recon:EC2/PortProbeUnprotectedPort | Port scanning detected against EC2 |
| UnauthorizedAccess:EC2/SSHBruteForce | SSH brute force attempts |
| Stealth:IAMUser/CloudTrailLoggingDisabled | Attacker trying to cover tracks |
| CryptoCurrency:EC2/BitcoinTool.B | Crypto mining malware on EC2 |
| UnauthorizedAccess:IAMUser/ConsoleLoginSuccess | Unexpected console login |

![GuardDuty Summary](docs/proofs/12-guardduty/guardduty-summary.jpg)
![GuardDuty Findings](docs/proofs/12-guardduty/guardduty-findings.jpg)

---

## Security Hub

| Property | Value |
|---|---|
| Status | Enabled |
| Auto-enable controls | Yes |

**Standards enabled:**
- CIS AWS Foundations Benchmark v1.2.0 — industry standard security baseline
- AWS Foundational Security Best Practices v1.0.0 — AWS curated checks

Aggregates findings from GuardDuty, AWS Config, and IAM Access Analyzer into a single
security posture view. Single pane of glass across all detection services.

![Security Hub Summary](docs/proofs/13-security-hub/securityhub-summary.jpg)
![Security Hub Summary 2](docs/proofs/13-security-hub/securityhub-summary-2.jpg)

---

## AWS Config

| Property | Value |
|---|---|
| Recorder | default — ALL supported resource types, continuous |
| IAM resources | Daily recording frequency |
| Delivery | S3 bucket aws-config-logs |

**7 Compliance Rules:**

| Rule | What it enforces |
|---|---|
| ec2-imdsv2-check | All EC2 instances must require IMDSv2 |
| encrypted-volumes | All EBS volumes must be encrypted |
| iam-root-access-key-check | Root account must have no access keys |
| iam-user-mfa-enabled | All IAM users must have MFA enabled |
| rds-instance-deletion-protection-enabled | RDS must have deletion protection on |
| restricted-ssh | No security group allows SSH from 0.0.0.0/0 |
| s3-bucket-public-read-prohibited | No S3 bucket allows public read (except frontend) |

Config answers the forensic questions: what did this security group look like 2 weeks ago?
Was this S3 bucket ever publicly accessible? Who changed this rule and when?

![Config Dashboard](docs/proofs/14-aws-config/config-dashboard.jpg)
![Config Dashboard 2](docs/proofs/14-aws-config/config-dashboard-2.jpg)
![Config Rules](docs/proofs/14-aws-config/config-rules.jpg)
![Config Restricted SSH Rule](docs/proofs/14-aws-config/config-restricted-ssh.jpg)

---

## Lambda — Order Notification

| Property | Value |
|---|---|
| Function name | order-notification |
| Runtime | Node.js 22.x |
| Memory | 128MB |
| Timeout | 3 seconds |
| Handler | index.handler |

Sends order confirmation email to customers via SES after a successful order.
Invoked asynchronously (`InvocationType: Event`) so the order API response
is not delayed by email sending.

**Integration flow:**
Customer places order → server.js saves to RDS → invokes Lambda async →
Lambda calls SES → confirmation email delivered to customer

**IAM permissions:** `ses:SendEmail`, `ses:SendRawEmail`,
`logs:CreateLogStream`, `logs:PutLogEvents` — nothing else.

---

## Terraform Backend

Remote state stored in S3 with DynamoDB locking — never committed to git.

| Resource | Name |
|---|---|
| S3 bucket | onlinebaqqala-terraform-state |
| DynamoDB table | onlinebaqqala-terraform-locks |
| Encryption | SSE enabled on bucket |
| Versioning | Enabled — full state history |

The DynamoDB lock table prevents two `terraform apply` runs from corrupting state
simultaneously. Lock is acquired at plan, released at apply completion.

![Terraform S3 Backend](docs/proofs/18-terraform-backend/terraform-s3-backend.jpg)
![Terraform Init Success](docs/proofs/18-terraform-backend/terraform-init-success.jpg)

---

## Exam Readiness

### SCS-C02 — Security Specialty Coverage

| Domain | Weight | What this project covers | Status |
|---|---|---|---|
| Threat Detection and Incident Response | 14% | GuardDuty, CloudTrail alarms, CloudWatch metric filters, SNS alerts, VPC Flow Logs | ✅ Strong |
| Security Logging and Monitoring | 18% | CloudTrail multi-region, CloudWatch log groups + alarms, VPC Flow Logs, Config recorder | ✅ Strong |
| Infrastructure Security | 20% | VPC 3-tier, NACLs, SG chaining, WAF, CloudFront, IMDSv2, ALB TLS 1.3, private subnets | ✅ Strong |
| Identity and Access Management | 16% | IAM least privilege, MFA, OIDC federation, instance roles, no root keys | ✅ Strong |
| Data Protection | 18% | KMS CMK, envelope encryption, SSE-KMS S3, RDS encryption, Secrets Manager, TLS in transit | ✅ Strong |
| Management and Security Governance | 14% | AWS Config rules, Security Hub + CIS benchmark, CloudTrail log validation | ⚠️ Partial |

**SCS-C02 gaps to close:**
- AWS Organizations + SCPs — governance domain, heavily tested
- Amazon Macie — data protection domain, S3 sensitive data discovery
- Amazon Inspector — infrastructure security domain, CVE scanning
- Secrets Manager auto-rotation — data protection, rotation Lambda
- AWS Config conformance packs — governance
- IAM Access Analyzer — external access findings

---

### SAA-C03 — Solutions Architect Coverage

| Domain | Weight | What this project covers | Status |
|---|---|---|---|
| Design Secure Architectures | 30% | VPC isolation, SG chaining, NACLs, KMS, Secrets Manager, IAM roles, OIDC | ✅ Strong |
| Design Resilient Architectures | 26% | ASG across 3 AZs, RDS read replica, ALB health checks, multi-AZ subnets | ✅ Good |
| Design High-Performing Architectures | 24% | CloudFront CDN, S3 static offload, ALB, ASG scaling, RDS read replica | ✅ Good |
| Design Cost-Optimized Architectures | 20% | S3 Bucket Key (reduces KMS calls), t2.micro + t4g.micro sizing, single NAT | ⚠️ Partial |

**SAA-C03 gaps to close:**
- Multi-AZ RDS — currently single AZ with read replica, exam heavily tests failover distinction
- ElastiCache — caching layer between EC2 and RDS (performance domain)
- S3 lifecycle policies — cost optimization domain
- Route 53 health checks + failover routing — resilience domain
- AWS Backup — centralised backup across RDS, EBS, S3

---

## Gaps to Close — Next Phase

These are the services not yet implemented. Each one integrates directly with what already exists.

---

### 1. Amazon Macie

**What it is:** Macie uses ML to automatically discover, classify, and protect sensitive data
stored in S3. It detects PII (names, emails, phone numbers, passport numbers, credit card
numbers), credentials (API keys, AWS keys), and custom data identifiers you define.

**How it integrates with this project:**
- Enable Macie on `netflix-videos-ryzk` bucket (the private one with customer data)
- Macie scans the bucket and generates findings if it detects sensitive data
- Findings appear in Security Hub automatically — already integrated
- GuardDuty and Macie feed into the same Security Hub dashboard

**Terraform to add:**
```hcl
resource "aws_macie2_account" "main" {
  status = "ENABLED"
}

resource "aws_macie2_classification_job" "videos_bucket" {
  job_type = "SCHEDULED"
  name     = "scan-netflix-videos-bucket"
  s3_job_definition {
    bucket_definitions {
      account_id = var.aws_account_id
      buckets    = [aws_s3_bucket.videos.id]
    }
  }
  schedule_frequency {
    weekly_schedule = "MONDAY"
  }
  depends_on = [aws_macie2_account.main]
}
```

**SCS-C02 exam relevance:** Data Protection domain (18%). Macie is directly tested —
know the difference between Macie findings (sensitive data) vs GuardDuty findings
(threat behaviour). They complement each other.

---

### 2. Amazon Inspector

**What it is:** Inspector automatically scans EC2 instances and container images for
software vulnerabilities (CVEs), unintended network exposure, and OS package vulnerabilities.
It is continuous — rescans automatically when new CVEs are published or new instances launch.

**How it integrates with this project:**
- Enable Inspector on the AWS account
- It automatically discovers EC2 instances (the ASG instances) and begins scanning
- Findings show the CVE ID, severity score (CVSS), affected package, and recommended fix
- Critical and High findings can trigger SNS alerts using EventBridge rules
- Findings appear in Security Hub — already integrated

**Terraform to add:**
```hcl
resource "aws_inspector2_enabler" "main" {
  account_ids    = [var.aws_account_id]
  resource_types = ["EC2", "ECR"]
}

resource "aws_cloudwatch_event_rule" "inspector_critical" {
  name        = "inspector-critical-findings"
  description = "Alert on Inspector critical findings"
  event_pattern = jsonencode({
    source      = ["aws.inspector2"]
    detail-type = ["Inspector2 Finding"]
    detail = {
      severity = ["CRITICAL", "HIGH"]
    }
  })
}

resource "aws_cloudwatch_event_target" "inspector_sns" {
  rule      = aws_cloudwatch_event_rule.inspector_critical.name
  target_id = "SendToSNS"
  arn       = aws_sns_topic.security_alerts.arn
}
```

**SCS-C02 exam relevance:** Infrastructure Security domain (20%). Inspector is tested
alongside Systems Manager Patch Manager. Know: Inspector finds vulnerabilities,
Patch Manager fixes them. They work together.

**SAA-C03 exam relevance:** Secure Architectures domain (30%). Know when to use
Inspector vs GuardDuty vs Macie — they answer different questions:
- Inspector → what vulnerabilities exist on my EC2?
- GuardDuty → is my EC2 behaving maliciously right now?
- Macie → does my S3 contain sensitive data I should not have?

---

### 3. AWS Organizations + Service Control Policies (SCPs)

**What it is:** AWS Organizations lets you manage multiple AWS accounts from a single
management account. SCPs are JSON policies attached to Organizational Units (OUs) or
individual accounts that act as a hard permission ceiling — they restrict what even
an account administrator can do. An SCP cannot grant permissions; it can only restrict them.

**How it integrates with this project:**
Even with a single account, you can document SCPs as the governance layer that would
be applied in a real enterprise deployment. The security controls already built
(CloudTrail, GuardDuty, Config) map directly to SCPs that enforce them organisation-wide.

**Example SCPs relevant to this project:**

Prevent disabling CloudTrail (maps to the `cloudtrail-stopped` alarm already built):
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "DenyCloudTrailDisable",
    "Effect": "Deny",
    "Action": [
      "cloudtrail:StopLogging",
      "cloudtrail:DeleteTrail",
      "cloudtrail:UpdateTrail"
    ],
    "Resource": "*"
  }]
}
```

Prevent disabling GuardDuty:
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "DenyGuardDutyDisable",
    "Effect": "Deny",
    "Action": [
      "guardduty:DeleteDetector",
      "guardduty:DisassociateFromMasterAccount",
      "guardduty:StopMonitoringMembers"
    ],
    "Resource": "*"
  }]
}
```

Require encryption on all new EBS volumes:
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "DenyUnencryptedVolumes",
    "Effect": "Deny",
    "Action": "ec2:RunInstances",
    "Resource": "arn:aws:ec2:*:*:volume/*",
    "Condition": {
      "Bool": {
        "ec2:Encrypted": "false"
      }
    }
  }]
}
```

**SCP vs IAM policy — the key distinction (heavily tested on SCS-C02):**
- IAM policy → controls what a principal CAN do
- SCP → controls what a principal CAN POSSIBLY do (the maximum boundary)
- Even if an IAM policy grants `s3:*`, an SCP denying `s3:DeleteBucket` wins
- SCPs do not affect the management account — only member accounts

**SCS-C02 exam relevance:** Management and Security Governance domain (14%).
SCPs, Organizations, and the distinction between SCPs and IAM are directly tested.
Also know: SCPs cannot grant access to services not already allowed by IAM.

---

### 4. Secrets Manager Auto-Rotation

**What it is:** Secrets Manager can automatically rotate the RDS password on a schedule
using a Lambda function. When rotation runs: Lambda generates a new password, updates
the RDS instance, updates the secret value — all without application downtime because
the app always fetches the secret at runtime, never caches it.

**How it integrates with this project:**
The secret `prod/netflix-app/rds` already exists. Enabling rotation adds a Lambda
function that Secrets Manager invokes automatically every N days.

**Terraform to add:**
```hcl
resource "aws_secretsmanager_secret_rotation" "rds" {
  secret_id           = aws_secretsmanager_secret.rds.id
  rotation_lambda_arn = aws_lambda_function.rotation.arn
  rotation_rules {
    automatically_after_days = 30
  }
}
```

**SCS-C02 exam relevance:** Data Protection domain (18%). Know the four rotation steps:
`createSecret` → `setSecret` → `testSecret` → `finishSecret`. The Lambda executes
these four steps. If rotation fails, the old secret remains valid.

---

### 5. CloudTrail Insights

**What it is:** CloudTrail Insights analyses your management event history to detect
unusual API activity — for example, an abnormal spike in `TerminateInstances` calls,
or an unusual number of failed `AssumeRole` attempts. It establishes a baseline
of normal behaviour and alerts when activity deviates significantly.

**How it integrates with this project:**
Enable on the existing `Netflix-Audit-Trail`. Findings appear in CloudTrail console
and can be sent to CloudWatch and SNS using the existing pipeline.

```hcl
resource "aws_cloudtrail" "main" {
  # existing config...
  insight_selector {
    insight_type = "ApiCallRateInsight"
  }
  insight_selector {
    insight_type = "ApiErrorRateInsight"
  }
}
```

---

## Project Structure

```
aws-cloud-security-project/
│
├── README.md                          ← this file
│
└── docs/
    ├── architecture/
    │   └── architecture-diagram.png   ← full 3-tier diagram
    │
    └── proofs/
        ├── 01-vpc-networking/         ← VPC, subnets, route tables, IGW, NAT, flow logs
        ├── 02-security-groups/        ← ALB SG, EC2 SG, RDS SG chaining
        ├── 03-nacls/                  ← public, private, database NACLs
        ├── 04-alb-acm/               ← ALB, listeners, TLS, target group
        ├── 05-ec2-asg/               ← launch template, IMDSv2, ASG
        ├── 06-rds/                   ← primary, replica, backup, encryption
        ├── 08-cloudfront-waf/        ← CloudFront distribution, WAF rules
        ├── 09-kms/                   ← CMK, key policy, rotation
        ├── 10-iam/                   ← roles, policies, OIDC, admin user
        ├── 12-guardduty/             ← detector, findings
        ├── 13-security-hub/          ← standards, findings summary
        ├── 14-aws-config/            ← recorder, 7 compliance rules
        ├── 15-cloudtrail/            ← trail config, S3, CloudWatch integration
        ├── 16-cloudwatch/            ← dashboard, alarms, log groups, SNS
        └── 18-terraform-backend/     ← S3 state bucket, DynamoDB lock table
```

---

*Built by [@uerruk](https://github.com/uerruk) — hands-on AWS security project, SCS-C02 and SAA-C03 preparation.*
