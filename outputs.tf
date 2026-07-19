###############################################################################
# Primary outputs (id + arn)
###############################################################################

output "id" {
 description = "The ID of the security group (e.g. sg-0123456789abcdef0)."
 value = aws_security_group.this.id
}

output "arn" {
 description = <<EOT
The ARN of the security group (cross-resource reference type:
arn:aws:ec2:<region>:<account>:security-group/<id>). Used in IAM/SCP policy
resource references that scope actions to this SG.
EOT
 value = aws_security_group.this.arn
}

output "security_group_id" {
 description = "Alias of id, for explicit cross-module wiring and audit documentation."
 value = aws_security_group.this.id
}

###############################################################################
# Resource attributes
###############################################################################

output "name" {
 description = "The name of the security group (the generated name when name_prefix was used)."
 value = aws_security_group.this.name
}

output "vpc_id" {
 description = "The ID of the VPC the security group belongs to."
 value = aws_security_group.this.vpc_id
}

output "owner_id" {
 description = "The ID of the AWS account that owns the security group."
 value = aws_security_group.this.owner_id
}

###############################################################################
# Rules
#
# Keyed by the caller's stable rule label so a specific managed rule can be
# resolved for drift inspection. The value is the per-rule security_group_rule_id.
###############################################################################

output "ingress_rule_ids" {
 description = "Map of ingress rule label => aws_vpc_security_group_ingress_rule id (security_group_rule_id)."
 value = { for k, r in aws_vpc_security_group_ingress_rule.this: k => r.id }
}

output "egress_rule_ids" {
 description = "Map of egress rule label => aws_vpc_security_group_egress_rule id (security_group_rule_id)."
 value = { for k, r in aws_vpc_security_group_egress_rule.this: k => r.id }
}

output "ingress_rule_arns" {
 description = "Map of ingress rule label => security group rule ARN."
 value = { for k, r in aws_vpc_security_group_ingress_rule.this: k => r.arn }
}

output "egress_rule_arns" {
 description = "Map of egress rule label => security group rule ARN."
 value = { for k, r in aws_vpc_security_group_egress_rule.this: k => r.arn }
}

###############################################################################
# Tags
###############################################################################

output "tags_all" {
 description = "All tags on the security group, including those inherited from provider default_tags (resource tags win on key conflict)."
 value = aws_security_group.this.tags_all
}
