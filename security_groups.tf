# ─── ALB SECURITY GROUP ─────────────────────────────────────────────────────
# Faces the internet. Only accepts HTTP and HTTPS from anywhere.
# SSH rule exists for legacy access — not needed in new architecture.

resource "aws_security_group" "alb" {
  name        = "Netflix-WebServer-SG"
  description = "Allow HTTP HTTPS from internet SSH"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH from admin IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["123.108.92.194/32"]
  }

  ingress {
    description = "Node.js direct access from VPC"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Netflix-WebServer-SG"
  }
}

# ─── PRIVATE EC2 SECURITY GROUP ─────────────────────────────────────────────
# No public access. Only accepts traffic from ALB security group.
# This is security group chaining — identity-based not IP-based.

resource "aws_security_group" "private_ec2" {
  name        = "Netflix-Private-EC2-SG"
  description = "Private EC2 security group"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTP from ALB only"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Netflix-Private-EC2-SG"
  }
}

# ─── DATABASE SECURITY GROUP ─────────────────────────────────────────────────
# Most restricted. Only accepts MySQL from private EC2 security group.
# RDS cannot be reached from internet or any other resource.

resource "aws_security_group" "rds" {
  name        = "Netflix-DB-SG"
  description = "Created by RDS management console"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "MySQL from private EC2 only"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.private_ec2.id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Netflix-DB-SG"
  }
}
