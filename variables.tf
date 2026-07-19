###############################################################################
# Identity
#
# A security group has a real `name` argument (unlike a network ACL). Both name
# and name_prefix are FORCE-NEW; supply at most one. The gold-standard pattern in
# a regulated estate is name_prefix + create_before_destroy (see main.tf), so a
# rename or rule-shape change can stand up a replacement SG before the old one is
# revoked — avoiding the DependencyViolation "Security Group Deletion Problem".
###############################################################################

variable "name" {
 description = <<EOT
Static name for the security group. FORCE-NEW — changing it destroys and
recreates the SG (and every rule). Mutually exclusive with name_prefix; supply at
most one. Leave null to let AWS generate a unique name (use name_prefix to give
that generated name a readable stem). When set, it is also surfaced as the Name
tag and wins over any Name key in var.tags.

Prefer name_prefix in shared/regulated environments: a fixed name collides with
create_before_destroy because the replacement SG would need the same unique name
as the one still being revoked.
EOT
 type = string
 default = null
}

variable "name_prefix" {
 description = <<EOT
Creates a unique name beginning with this prefix (AWS appends a random suffix).
FORCE-NEW and mutually exclusive with name; supply at most one. This is the
RECOMMENDED identity option because it is compatible with the
create_before_destroy lifecycle this module sets on the SG.
EOT
 type = string
 default = null

 validation {
 condition = !(var.name != null && var.name_prefix != null)
 error_message = "Supply at most one of name or name_prefix, not both (they are mutually exclusive identity arguments)."
 }
}

variable "vpc_id" {
 description = <<EOT
ID of the VPC the security group is created in. REQUIRED and FORCE-NEW — an SG
cannot move between VPCs, so changing this destroys and recreates the SG (and its
rules). Wire from tf_mod_aws_vpc (vpc_id). Default-VPC use is discouraged in a
regulated environment.
EOT
 type = string

 validation {
 condition = can(regex("^vpc-[0-9a-f]{8,}$", var.vpc_id))
 error_message = "vpc_id must be a valid VPC id (e.g. vpc-0123456789abcdef0)."
 }
}

variable "description" {
 description = <<EOT
Human-readable description of the security group, shown in the console and in
audits. FORCE-NEW — the AWS API does not allow editing an SG description in place,
so changing it recreates the SG. Defaults to a generic managed-by note.
EOT
 type = string
 default = "Managed by Terraform (tf_mod_aws_security_group)"
}

variable "revoke_rules_on_delete" {
 description = <<EOT
When true, Terraform revokes all ingress and egress rules on the SG before
deleting it. Leave false unless you hit a circular-dependency delete failure
between two SGs that reference each other — in that case set true on one of them
to break the cycle so both can be destroyed.
EOT
 type = bool
 default = false
}

###############################################################################
# Ingress rules (child collection — for_each over map(object))
#
# SECURE DEFAULT: no inbound rule is added implicitly. An SG with an empty
# ingress map denies ALL inbound traffic — the secure baseline. Each entry is
# rendered as one aws_vpc_security_group_ingress_rule (the modern one-rule-per-
# resource API), NOT an inline ingress block and NOT the legacy
# aws_security_group_rule. 0.0.0.0/0 is NEVER defaulted; it appears only when a
# caller sets cidr_ipv4 = "0.0.0.0/0" explicitly (flag such rules in review).
###############################################################################

variable "ingress_rules" {
 description = <<EOT
Map of inbound (ingress) rules keyed by a stable caller-chosen label (e.g.
"https-from-alb"). The key is used in the ingress_rule_ids output and keeps
for_each stable so adding/removing one rule never churns the others. Each entry
becomes one aws_vpc_security_group_ingress_rule.

Exactly ONE source must be supplied per rule (cidr_ipv4, cidr_ipv6,
prefix_list_id, or referenced_security_group_id). A description is REQUIRED on
every rule for auditability. from_port/to_port are required for tcp/udp and are
the ICMP type/code for icmp; omit them only when ip_protocol is "-1" (all) or
"icmpv6".

 - description: audit note for the rule. (required)
 - ip_protocol: "tcp", "udp", "icmp", "icmpv6", "-1" (all),
 or an IANA protocol number as a string. (required)
 - from_port: start of port range (or ICMP type).
 - to_port: end of port range (or ICMP code).
 - cidr_ipv4: source IPv4 CIDR (e.g. "10.0.0.0/16").
 - cidr_ipv6: source IPv6 CIDR.
 - prefix_list_id: source managed/AWS prefix list id.
 - referenced_security_group_id: source SG id (set to this SG's own id for a
 self-reference once known).
 - tags: per-rule tags, merged over var.tags.

 ingress_rules = {
 https-from-alb = { description = "HTTPS from ALB SG", ip_protocol = "tcp", from_port = 443, to_port = 443, referenced_security_group_id = module.alb_sg.id }
 pg-from-app = { description = "Postgres from app subnets", ip_protocol = "tcp", from_port = 5432, to_port = 5432, cidr_ipv4 = "10.0.0.0/16" }
 }
EOT
 type = map(object({
 description = string
 ip_protocol = string
 from_port = optional(number)
 to_port = optional(number)
 cidr_ipv4 = optional(string)
 cidr_ipv6 = optional(string)
 prefix_list_id = optional(string)
 referenced_security_group_id = optional(string)
 tags = optional(map(string), {})
 }))
 default = {}

 validation {
 condition = alltrue([for k, v in var.ingress_rules: trimspace(v.description) != ""])
 error_message = "Each ingress_rules[*].description is required and must be non-empty (rule auditability)."
 }

 validation {
 condition = alltrue([for k, v in var.ingress_rules: can(regex("^(-1|tcp|udp|icmp|icmpv6|[0-9]{1,3})$", v.ip_protocol))])
 error_message = "Each ingress_rules[*].ip_protocol must be \"-1\", \"tcp\", \"udp\", \"icmp\", \"icmpv6\", or an IANA protocol number string."
 }

 validation {
 condition = alltrue([
 for k, v in var.ingress_rules:
 length([for src in [v.cidr_ipv4, v.cidr_ipv6, v.prefix_list_id, v.referenced_security_group_id]: src if src != null]) == 1
 ])
 error_message = "Each ingress_rules[*] must set exactly one source: cidr_ipv4, cidr_ipv6, prefix_list_id, or referenced_security_group_id."
 }
}

###############################################################################
# Egress rules (child collection — for_each over map(object))
#
# SECURE DEFAULT: when an SG is created in a VPC, AWS adds a default
# allow-all-egress rule; Terraform REMOVES it. With an empty egress map this
# module therefore leaves NO outbound rule (deny-all egress). Add an explicit
# rule to permit outbound traffic — including an explicit 0.0.0.0/0 egress if
# (and only if) the workload genuinely needs open egress.
###############################################################################

variable "egress_rules" {
 description = <<EOT
Map of outbound (egress) rules keyed by a stable caller-chosen label, each
rendered as one aws_vpc_security_group_egress_rule. Same object schema and
validations as ingress_rules (description required, exactly one destination,
ip_protocol enum). Because Terraform strips the AWS default allow-all-egress rule,
this is where outbound access is granted explicitly.

 egress_rules = {
 https-out = { description = "HTTPS to internet", ip_protocol = "tcp", from_port = 443, to_port = 443, cidr_ipv4 = "0.0.0.0/0" }
 }

See ingress_rules for the full field reference.
EOT
 type = map(object({
 description = string
 ip_protocol = string
 from_port = optional(number)
 to_port = optional(number)
 cidr_ipv4 = optional(string)
 cidr_ipv6 = optional(string)
 prefix_list_id = optional(string)
 referenced_security_group_id = optional(string)
 tags = optional(map(string), {})
 }))
 default = {}

 validation {
 condition = alltrue([for k, v in var.egress_rules: trimspace(v.description) != ""])
 error_message = "Each egress_rules[*].description is required and must be non-empty (rule auditability)."
 }

 validation {
 condition = alltrue([for k, v in var.egress_rules: can(regex("^(-1|tcp|udp|icmp|icmpv6|[0-9]{1,3})$", v.ip_protocol))])
 error_message = "Each egress_rules[*].ip_protocol must be \"-1\", \"tcp\", \"udp\", \"icmp\", \"icmpv6\", or an IANA protocol number string."
 }

 validation {
 condition = alltrue([
 for k, v in var.egress_rules:
 length([for src in [v.cidr_ipv4, v.cidr_ipv6, v.prefix_list_id, v.referenced_security_group_id]: src if src != null]) == 1
 ])
 error_message = "Each egress_rules[*] must set exactly one destination: cidr_ipv4, cidr_ipv6, prefix_list_id, or referenced_security_group_id."
 }
}

###############################################################################
# Universal tail
###############################################################################

variable "tags" {
 description = <<EOT
Map of tags to assign to the security group and to every ingress/egress rule
resource (all three resource types in this module are taggable). Per-rule tags
supplied in ingress_rules/egress_rules merge over these (per-rule wins). These in
turn merge with provider-level default_tags; resource tags win on key conflict.
When var.name is set it is applied as the Name tag on the SG and overrides any
Name key supplied here. The computed tags_all output reflects the fully merged set.
EOT
 type = map(string)
 default = {}
}
