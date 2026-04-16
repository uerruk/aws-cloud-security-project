variable "aws_region" {
  description = "AWS region where all resources are deployed"
  type        = string
  default     = "eu-west-1"
}

variable "environment" {
  description = "Environment name — used in tags and resource names"
  type        = string
  default     = "production"
}

variable "project_name" {
  description = "Project name — used as prefix for all resource names"
  type        = string
  default     = "onlinebaqqala"
}
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}
variable "db_password" {
  description = "RDS MySQL master password"
  type        = string
  sensitive   = true
}
variable "ami_id" {
  description = "AMI ID for EC2 instances — updated by CI/CD after each deployment"
  type        = string
  default     = "ami-05508268899a20e73"
}
