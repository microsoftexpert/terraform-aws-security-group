terraform {
 required_version = ">= 1.12.0"

 required_providers {
 aws = {
 source = "hashicorp/aws"
 version = ">= 6.0, < 7.0"
 }
 }
}

###############################################################################
# Region / provider wiring (read before use)
#
# This module does NOT declare a `region` variable (region model) and does
# NOT hard-code a provider. The security group and its per-rule
# aws_vpc_security_group_ingress_rule / aws_vpc_security_group_egress_rule
# resources are all created with the single inherited `aws` provider, so the
# *caller* decides the Region by choosing which provider configuration to pass
# into the `aws` slot.
#
# A security group is a REGIONAL, VPC-scoped resource: it must be created in the
# same Region as the VPC it belongs to. Wire `vpc_id` from a tf_mod_aws_vpc call
# made against the same provider/Region as this module.
#
# module "sg" {
# source = "git::https://github.com/microsoftexpert/tf_mod_aws_security_group?ref=v1.0.0"
# # inherits the default `aws` provider (whatever Region it points at)
# name_prefix = "app-"
# vpc_id = module.vpc.vpc_id
# ingress_rules = {... }
# }
#
# Provider credentials, default_tags and assume_role all live in the caller's
# provider block — never in this module.
###############################################################################
