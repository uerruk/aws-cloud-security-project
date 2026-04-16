# ─── APPLICATION LOAD BALANCER ───────────────────────────────────────────────
# Internet-facing — sits in public subnets
# Single entry point to the application
# EC2 instances are in private subnets — only reachable through ALB
# SSL termination happens here — EC2 never handles certificates

resource "aws_lb" "main" {
  name               = "aws-onlinebaqqala-store"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]

  subnets = [
    aws_subnet.public_1a.id,
    aws_subnet.public_1b.id,
    aws_subnet.public_1c.id,
  ]

  ip_address_type = "ipv4"

  # Drops requests with malformed HTTP headers
  # Fixes: securityhub-alb-http-drop-invalid-header-enabled
  drop_invalid_header_fields = true

  # Prevents accidental deletion from console
  # Fixes: securityhub-elb-deletion-protection-enabled
  enable_deletion_protection = true

  # ALB access logs — every request logged to S3
  # Critical for incident response — who accessed what and when
  # Fixes: securityhub-elb-logging-enabled
  access_logs {
    bucket  = aws_s3_bucket.cloudtrail.bucket
    prefix  = "alb-access-logs"
    enabled = true
  }

  tags = {
    Name = "aws-onlinebaqqala-store"
  }
}

# ─── TARGET GROUP ────────────────────────────────────────────────────────────
# Group of EC2 instances that receive traffic from ALB
# Health check on /health endpoint — Node.js returns 200 when healthy
# ALB removes unhealthy instances from rotation automatically

resource "aws_lb_target_group" "main" {
  name     = "Netflix-WebServers-TG"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    enabled             = true
    path                = "/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  tags = {
    Name = "Netflix-WebServers-TG"
  }
}

# ─── HTTPS LISTENER (port 443) ───────────────────────────────────────────────
# Terminates SSL using ACM certificate for aws.onlinebaqqala.store
# Forwards all traffic to target group
# Security policy TLS 1.3 — rejects older insecure TLS versions

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = "arn:aws:acm:eu-west-1:441464446441:certificate/e00bb5ee-dcd9-4ff2-a16a-8a7c2ed56eee"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }

  tags = {
    Name = "aws-onlinebaqqala-store-https"
  }
}

# ─── HTTP LISTENER (port 80) ─────────────────────────────────────────────────
# Redirects all HTTP to HTTPS — enforces encryption in transit
# 301 permanent redirect — browsers remember and go directly to HTTPS
# No plain HTTP traffic ever reaches EC2

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  tags = {
    Name = "aws-onlinebaqqala-store-http-redirect"
  }
}
