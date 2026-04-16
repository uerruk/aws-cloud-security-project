# ─── LAUNCH TEMPLATE ─────────────────────────────────────────────────────────
# Blueprint for every EC2 instance ASG launches
# CI/CD pipeline creates a new version after every deployment
# ASG always uses $Latest — picks up new AMI automatically after CI/CD runs
# IMDSv2 set to Required — blocks SSRF attacks on metadata endpoint

resource "aws_launch_template" "main" {
  name        = "onlinebaqqala.store"
  description = "Launch template for onlinebaqqala.store private EC2 instances"

  image_id      = var.ami_id
  instance_type = "t2.micro"
  key_name      = "netflix-keypair"

  vpc_security_group_ids = [aws_security_group.private_ec2.id]

  iam_instance_profile {
    arn = aws_iam_instance_profile.ec2.arn
  }

  # EBS root volume — encrypted with CMK
  # Fixes: encrypted-volumes Config rule
  # Fixes: securityhub-ec2-launch-template-imdsv2-check
  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = 8
      volume_type           = "gp3"
      encrypted             = true
      kms_key_id            = aws_kms_key.main.arn
      delete_on_termination = true
    }
  }

  # IMDSv2 — token required for all metadata requests
  # Blocks SSRF attacks — attacker needs PUT request for token
  # Most SSRF only allows GET — IMDSv2 stops credential theft
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  monitoring {
    enabled = false
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "onlinebaqqala-asg-instance"
    }
  }

  tags = {
    Name = "onlinebaqqala.store"
  }
}

# ─── AUTO SCALING GROUP ───────────────────────────────────────────────────────
# Manages fleet of EC2 instances in private subnets
# Min 1 — always at least one instance running
# Max 3 — cost control, scale up to 3 under load
# Desired 1 — normal operation runs 1 instance
#
# Health checks — both EC2 and ELB
# EC2 health check — is the instance running?
# ELB health check — is the app responding on /health?
# If either fails — ASG terminates and replaces the instance

resource "aws_autoscaling_group" "main" {
  name = "onlinebaqqala-asg"

  min_size         = 1
  max_size         = 3
  desired_capacity = 1

  # Private app subnets — no public IPs, traffic only through ALB
  vpc_zone_identifier = [
    aws_subnet.private_app_1a.id,
    aws_subnet.private_app_1b.id,
    aws_subnet.private_app_1c.id,
  ]

  # Always use latest launch template version
  # CI/CD updates default version after AMI bake
  launch_template {
    id      = aws_launch_template.main.id
    version = "$Latest"
  }

  # Attach to ALB target group
  target_group_arns = [aws_lb_target_group.main.arn]

  # Both EC2 and ELB health checks
  health_check_type         = "ELB"
  health_check_grace_period = 120

  # Default cooldown — wait 300s before another scaling action
  default_cooldown = 300

  # Termination policy — default AWS behaviour
  termination_policies = ["Default"]

  tag {
    key                 = "Name"
    value               = "onlinebaqqala-asg-instance"
    propagate_at_launch = true
  }

  tag {
    key                 = "Project"
    value               = "onlinebaqqala"
    propagate_at_launch = true
  }

  lifecycle {
    ignore_changes = [desired_capacity]
  }
}
