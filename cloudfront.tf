# =============================================================
# cloudfront.tf — CloudFront Distribution
# STATUS: COMMENTED OUT — AWS account not yet approved for CF
# Uncomment everything when approval comes through
# Associates with WAF scope = CLOUDFRONT (not REGIONAL)
# =============================================================

# IMPORTANT: When you uncomment this file you must also:
# 1. Change aws_wafv2_web_acl.main scope from REGIONAL to CLOUDFRONT
#    in waf.tf — CloudFront WAF must be in us-east-1
# 2. Deploy the WAF separately in us-east-1 (CloudFront is global,
#    WAF for CF must be in us-east-1 regardless of your region)
# 3. Run terraform apply after uncommenting

# ----------------------------------------------------------
# # Origin Access Control — allows CF to access S3 privately
# ----------------------------------------------------------
# resource "aws_cloudfront_origin_access_control" "frontend" {
#   name                              = "Netflix-S3-OAC"
#   description                       = "OAC for frontend S3 bucket"
#   origin_access_control_origin_type = "s3"
#   signing_behavior                  = "always"
#   signing_protocol                  = "sigv4"
# }

# ----------------------------------------------------------
# # CloudFront Distribution
# # Origin 1: S3 frontend bucket (static assets)
# # Origin 2: ALB (dynamic API requests)
# ----------------------------------------------------------
# resource "aws_cloudfront_distribution" "main" {
#   enabled             = true
#   is_ipv6_enabled     = true
#   comment             = "Netflix onlinebaqqala CDN"
#   default_root_object = "index.html"
#   price_class         = "PriceClass_100" # US + Europe only — cheapest
#
#   aliases = ["aws.onlinebaqqala.store"] # Your domain
#
#   # --------------------------------------------------------
#   # Origin 1 — S3 Frontend Bucket
#   # --------------------------------------------------------
#   origin {
#     domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
#     origin_id                = "S3-frontend"
#     origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
#   }
#
#   # --------------------------------------------------------
#   # Origin 2 — ALB (API / backend)
#   # --------------------------------------------------------
#   origin {
#     domain_name = aws_lb.main.dns_name
#     origin_id   = "ALB-backend"
#
#     custom_origin_config {
#       http_port              = 80
#       https_port             = 443
#       origin_protocol_policy = "https-only"
#       origin_ssl_protocols   = ["TLSv1.2"]
#     }
#   }
#
#   # --------------------------------------------------------
#   # Default Cache Behaviour — serves S3 static frontend
#   # --------------------------------------------------------
#   default_cache_behavior {
#     allowed_methods        = ["GET", "HEAD"]
#     cached_methods         = ["GET", "HEAD"]
#     target_origin_id       = "S3-frontend"
#     viewer_protocol_policy = "redirect-to-https"
#     compress               = true
#
#     forwarded_values {
#       query_string = false
#       cookies {
#         forward = "none"
#       }
#     }
#
#     min_ttl     = 0
#     default_ttl = 86400   # 1 day
#     max_ttl     = 31536000 # 1 year
#   }
#
#   # --------------------------------------------------------
#   # /api/* Cache Behaviour — forwards to ALB
#   # --------------------------------------------------------
#   ordered_cache_behavior {
#     path_pattern           = "/api/*"
#     allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
#     cached_methods         = ["GET", "HEAD"]
#     target_origin_id       = "ALB-backend"
#     viewer_protocol_policy = "redirect-to-https"
#     compress               = true
#
#     forwarded_values {
#       query_string = true
#       headers      = ["Authorization", "Origin", "Accept"]
#       cookies {
#         forward = "all"
#       }
#     }
#
#     min_ttl     = 0
#     default_ttl = 0   # Don't cache API responses
#     max_ttl     = 0
#   }
#
#   # --------------------------------------------------------
#   # SSL Certificate — ACM cert for your domain
#   # --------------------------------------------------------
#   viewer_certificate {
#     acm_certificate_arn      = "arn:aws:acm:us-east-1:441464446441:certificate/e00bb5ee-dcd9-4ff2-a16a-8a7c2ed56eee"
#     ssl_support_method       = "sni-only"
#     minimum_protocol_version = "TLSv1.2_2021"
#   }
#
#   # --------------------------------------------------------
#   # WAF Association
#   # Note: WAF for CloudFront must be deployed in us-east-1
#   # --------------------------------------------------------
#   # web_acl_id = aws_wafv2_web_acl.cloudfront.arn
#
#   restrictions {
#     geo_restriction {
#       restriction_type = "none" # No geo blocking — open globally
#     }
#   }
#
#   tags = {
#     Name        = "Netflix-CloudFront"
#     Environment = "production"
#   }
# }

# ----------------------------------------------------------
# # Output — CloudFront domain when live
# ----------------------------------------------------------
# output "cloudfront_domain" {
#   description = "CloudFront distribution domain name"
#   value       = aws_cloudfront_distribution.main.domain_name
# }
