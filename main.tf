###############################################################################
# Local derivations
#
# var.name, when set, is surfaced as the Name tag on the SG and wins over any
# Name key the caller passed in var.tags (so the console "Name" column matches
# the group name). Rules carry the module tags merged with their own per-rule
# tags; per-rule tags win on key conflict.
###############################################################################

locals {
 sg_tags = var.name != null ? merge(var.tags, { Name = var.name }): var.tags
}

###############################################################################
# Security group (keystone)
#
# name / name_prefix / description / vpc_id are all FORCE-NEW. create_before_destroy
# lets a replacement SG be created and re-pointed by dependents (ENIs, ALBs, RDS,
# instances) BEFORE the old one is revoked, sidestepping the DependencyViolation
# "Security Group Deletion Problem". This is also why name_prefix is preferred
# over a fixed name (two SGs with the same unique name cannot coexist).
#
# No inline ingress/egress blocks: rules are managed as standalone
# aws_vpc_security_group_(in|e)gress_rule resources below. Mixing the inline form
# with the standalone resources makes the provider fight over rule ownership.
###############################################################################

resource "aws_security_group" "this" {
 name = var.name
 name_prefix = var.name_prefix
 description = var.description
 vpc_id = var.vpc_id

 revoke_rules_on_delete = var.revoke_rules_on_delete

 tags = local.sg_tags

 lifecycle {
 create_before_destroy = true
 }
}

###############################################################################
# Ingress rules
#
# SECURE BASELINE: nothing is injected implicitly — an empty ingress map denies
# all inbound. One resource per rule means each rule has its own
# security_group_rule_id, clean drift detection, and granular plan diffs; changing
# a rule's port/protocol/source replaces only that one rule resource.
###############################################################################

resource "aws_vpc_security_group_ingress_rule" "this" {
 for_each = var.ingress_rules

 security_group_id = aws_security_group.this.id
 description = each.value.description
 ip_protocol = each.value.ip_protocol

 from_port = try(each.value.from_port, null)
 to_port = try(each.value.to_port, null)

 cidr_ipv4 = try(each.value.cidr_ipv4, null)
 cidr_ipv6 = try(each.value.cidr_ipv6, null)
 prefix_list_id = try(each.value.prefix_list_id, null)
 referenced_security_group_id = try(each.value.referenced_security_group_id, null)

 tags = merge(var.tags, each.value.tags)
}

###############################################################################
# Egress rules
#
# Terraform strips the AWS default allow-all-egress rule, so an empty egress map
# leaves NO outbound rule (deny-all egress). Outbound access is therefore always
# explicit and reviewable.
###############################################################################

resource "aws_vpc_security_group_egress_rule" "this" {
 for_each = var.egress_rules

 security_group_id = aws_security_group.this.id
 description = each.value.description
 ip_protocol = each.value.ip_protocol

 from_port = try(each.value.from_port, null)
 to_port = try(each.value.to_port, null)

 cidr_ipv4 = try(each.value.cidr_ipv4, null)
 cidr_ipv6 = try(each.value.cidr_ipv6, null)
 prefix_list_id = try(each.value.prefix_list_id, null)
 referenced_security_group_id = try(each.value.referenced_security_group_id, null)

 tags = merge(var.tags, each.value.tags)
}
