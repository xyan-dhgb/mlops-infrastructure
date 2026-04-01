# Create Hosted Zone on AWS, AWS will manage DNS instead of Namecheap 
resource "aws_route53_zone" "main" {
  name = var.domain_name
}
