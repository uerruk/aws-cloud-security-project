# ─── ORIGINAL PUBLIC EC2 — LEGACY ────────────────────────────────────────────
# Netflix-WebServer-01 — original EC2 in public subnet
# Now stopped — replaced by private EC2 managed by ASG
# Kept as backup — do not terminate until ASG proven stable
# Was the working instance throughout the project build
# All debugging, fixes, and AMI baking done from this instance

# This instance is NOT managed by Terraform apply
# Documented here for project completeness and architecture record
# To import: terraform import aws_instance.original i-0ca2a91da46bddb60

# resource "aws_instance" "original" {
#   ami                    = "ami-<original>"
#   instance_type          = "t2.micro"
#   subnet_id              = aws_subnet.public_1a.id
#   vpc_security_group_ids = [aws_security_group.alb.id]
#   iam_instance_profile   = aws_iam_instance_profile.ec2.name
#   key_name               = "netflix-keypair"
#
#   tags = {
#     Name = "Netflix-WebServer-01"
#   }
# }
