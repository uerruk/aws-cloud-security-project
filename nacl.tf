# ─── PUBLIC NACL ─────────────────────────────────────────────────────────────
# Attached to 3 public subnets — ALB lives here
# Allows HTTP, HTTPS from internet + ephemeral return traffic
# SSH restricted to admin IP only

resource "aws_network_acl" "public" {
  vpc_id = aws_vpc.main.id

  subnet_ids = [
    aws_subnet.public_1a.id,
    aws_subnet.public_1b.id,
    aws_subnet.public_1c.id,
  ]

  # INBOUND
  ingress {
    rule_no    = 100
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }

  ingress {
    rule_no    = 110
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 80
    to_port    = 80
  }

  ingress {
    rule_no    = 120
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  ingress {
    rule_no    = 130
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "123.108.92.194/32"
    from_port  = 22
    to_port    = 22
  }

  # OUTBOUND
  egress {
    rule_no    = 100
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }

  egress {
    rule_no    = 110
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 80
    to_port    = 80
  }

  egress {
    rule_no    = 120
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "10.0.20.0/24"
    from_port  = 3306
    to_port    = 3306
  }

  egress {
    rule_no    = 130
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "10.0.21.0/24"
    from_port  = 3306
    to_port    = 3306
  }

  egress {
    rule_no    = 140
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  tags = {
    Name = "Netflix-NACL-Public"
  }
}

# ─── PRIVATE APP NACL ────────────────────────────────────────────────────────
# Attached to 3 private app subnets — EC2 and ASG live here
# Only accepts HTTP from public subnets (ALB forwards here)
# Outbound allows MySQL to DB subnets and internet via NAT

resource "aws_network_acl" "private" {
  vpc_id = aws_vpc.main.id

  subnet_ids = [
    aws_subnet.private_app_1a.id,
    aws_subnet.private_app_1b.id,
    aws_subnet.private_app_1c.id,
  ]

  # INBOUND
  ingress {
    rule_no    = 100
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "10.0.1.0/24"
    from_port  = 80
    to_port    = 80
  }

  ingress {
    rule_no    = 110
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "10.0.2.0/24"
    from_port  = 80
    to_port    = 80
  }

  ingress {
    rule_no    = 120
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "10.0.3.0/24"
    from_port  = 80
    to_port    = 80
  }

  ingress {
    rule_no    = 130
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "10.0.1.0/24"
    from_port  = 443
    to_port    = 443
  }

  ingress {
    rule_no    = 140
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "10.0.2.0/24"
    from_port  = 443
    to_port    = 443
  }

  ingress {
    rule_no    = 150
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "10.0.3.0/24"
    from_port  = 443
    to_port    = 443
  }

  ingress {
    rule_no    = 160
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  # OUTBOUND
  egress {
    rule_no    = 100
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "10.0.20.0/24"
    from_port  = 3306
    to_port    = 3306
  }

  egress {
    rule_no    = 110
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "10.0.21.0/24"
    from_port  = 3306
    to_port    = 3306
  }

  egress {
    rule_no    = 120
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }

  egress {
    rule_no    = 130
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 80
    to_port    = 80
  }

  egress {
    rule_no    = 140
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "10.0.1.0/24"
    from_port  = 1024
    to_port    = 65535
  }

  egress {
    rule_no    = 150
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "10.0.2.0/24"
    from_port  = 1024
    to_port    = 65535
  }

  egress {
    rule_no    = 160
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "10.0.3.0/24"
    from_port  = 1024
    to_port    = 65535
  }

  tags = {
    Name = "Netflix-NACL-Private"
  }
}

# ─── DATABASE NACL ───────────────────────────────────────────────────────────
# Attached to 2 DB subnets — RDS lives here
# Only accepts MySQL 3306 from private app subnets
# Return traffic goes back on ephemeral ports to private app subnets only
# No internet access at all — most restricted tier

resource "aws_network_acl" "database" {
  vpc_id = aws_vpc.main.id

  subnet_ids = [
    aws_subnet.private_db_1a.id,
    aws_subnet.private_db_1b.id,
  ]

  # INBOUND — only MySQL from private app subnets
  ingress {
    rule_no    = 100
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "10.0.10.0/24"
    from_port  = 3306
    to_port    = 3306
  }

  ingress {
    rule_no    = 110
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "10.0.11.0/24"
    from_port  = 3306
    to_port    = 3306
  }

  ingress {
    rule_no    = 120
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "10.0.12.0/24"
    from_port  = 3306
    to_port    = 3306
  }

  # OUTBOUND — ephemeral return traffic back to private app subnets only
  egress {
    rule_no    = 100
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "10.0.10.0/24"
    from_port  = 1024
    to_port    = 65535
  }

  egress {
    rule_no    = 110
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "10.0.11.0/24"
    from_port  = 1024
    to_port    = 65535
  }

  egress {
    rule_no    = 120
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "10.0.12.0/24"
    from_port  = 1024
    to_port    = 65535
  }

  tags = {
    Name = "Netflix-NACL-Database"
  }
}
