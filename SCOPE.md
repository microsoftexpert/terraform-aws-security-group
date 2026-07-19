# tf-mod-aws-security-group — SCOPE

Composite module for a secure-by-default EC2 security group. It owns the
security group plus its ingress and egress rules, modeled as **one rule per
resource** (`aws_vpc_security_group_ingress_rule` / `..._egress_rule`) keyed via
`for_each` over `map(object(...))`. No default-open ingress; no `0.0.0.0/0`
unless the caller explicitly asks for it.

- **Module type:** Composite
- **Primary resource (keystone):** `aws_security_group.this`

## In-scope resources

The module manages **all** of the following (allow-list):

- `aws_security_group` — keystone (with `create_before_destroy`)
- `aws_vpc_security_group_ingress_rule` — ingress rules (`for_each` over a map)
- `aws_vpc_security_group_egress_rule` — egress rules (`for_each` over a map)

> The module uses the modern one-rule-per-resource API, **not** inline
> `ingress`/`egress` blocks and **not** the legacy `aws_security_group_rule`.

## Out-of-scope resources (consumed by reference)

Referenced by `id`/`arn`, never created here:

- VPC — `vpc_id` (from `tf-mod-aws-vpc`)
- Peer/referenced security groups — `referenced_security_group_id` per rule
- Prefix lists — `prefix_list_id` per rule
- Resources the SG is attached to (instances, ALBs, RDS, ENIs) — owned elsewhere

## Consumes

| Input | Type | Source module |
|---|---|---|
| `vpc_id` | `string` (VPC id) | `tf-mod-aws-vpc` |
| `ingress_rules[*].referenced_security_group_id` | `string` (SG id) | `tf-mod-aws-security-group` (peer SG) |
| `egress_rules[*].referenced_security_group_id` | `string` (SG id) | `tf-mod-aws-security-group` (peer SG) |
| `*.prefix_list_id` | `string` (PL id) | `tf-mod-aws-vpc-endpoint` (gateway endpoint PL) / managed prefix lists |

## Required IAM permissions

| Action | Required for |
|---|---|
| `ec2:CreateSecurityGroup`, `ec2:DeleteSecurityGroup`, `ec2:DescribeSecurityGroups` | Security group lifecycle |
| `ec2:AuthorizeSecurityGroupIngress`, `ec2:RevokeSecurityGroupIngress` | Ingress rules |
| `ec2:AuthorizeSecurityGroupEgress`, `ec2:RevokeSecurityGroupEgress` | Egress rules |
| `ec2:DescribeSecurityGroupRules` | Read individual rule resources |
| `ec2:ModifySecurityGroupRules`, `ec2:UpdateSecurityGroupRuleDescriptionsIngress`, `ec2:UpdateSecurityGroupRuleDescriptionsEgress` | Rule description updates |
| `ec2:CreateTags`, `ec2:DeleteTags` | Tagging the SG and rules |

No `iam:PassRole` and no service-linked role required.

## AWS Prerequisites

- **No service-linked role** required. No account opt-in. No `us-east-1`
  global-resource constraint (SGs are regional, VPC-scoped).
- **VPC must exist** — wire `vpc_id` from `tf-mod-aws-vpc`. Default-VPC use is
  discouraged in a regulated environment.
- **Referenced sources must exist in scope** — a `referenced_security_group_id`
  must be a peer SG in the same VPC (or reachable via accepted VPC peering /
  Transit Gateway); a `prefix_list_id` must be a managed/AWS-managed prefix list
  reachable from the VPC.
- **Quotas** (adjustable via Service Quotas): 2,500 SGs per VPC; 60 inbound + 60
  outbound rules per SG by default (a CIDR per protocol counts as one rule); 5
  SGs per ENI (raisable to 16); the product *rules-per-SG × SGs-per-ENI* must stay
  within 1,000.
- Each `aws_vpc_security_group_ingress_rule`/`egress_rule` represents exactly one
  rule and gets its own `security_group_rule_id` (`sgr-…`).

## Emits

| Output | Description | Consumed by |
|---|---|---|
| `id` / `security_group_id` | Security group id | EC2/ALB/RDS/ECS/EKS/endpoint modules |
| `arn` | Security group ARN (`arn:aws:ec2:<region>:<account>:security-group/<id>`) | IAM/policy references |
| `security_group_id` | Alias of `id` for explicit cross-module wiring | EC2/ALB/RDS/ECS/EKS/endpoint modules |
| `name` | Security group name (or name prefix result) | reference / tagging / monitoring |
| `vpc_id` | The VPC the SG belongs to | inventory / audit |
| `owner_id` | AWS account id that owns the SG | audit |
| `ingress_rule_ids` / `egress_rule_ids` | Maps of per-rule ids (`sgr-…`) | drift inspection |
| `ingress_rule_arns` / `egress_rule_arns` | Maps of per-rule ARNs (`…:security-group-rule/<id>`) | audit |
| `tags_all` | All tags incl. provider `default_tags` | governance/audit |

## Provider gotchas

- **`vpc_id` and `name` are FORCE-NEW.** Changing either recreates the SG. Prefer
  `name_prefix` + `create_before_destroy` to avoid downtime and name collisions.
- **`create_before_destroy = true`** on the SG so dependents (ENIs/ALBs) can
  re-point before the old SG is removed — avoids `DependencyViolation`.
- **One-rule-per-resource semantics:** changing a rule's protocol/port/CIDR is a
  replace of that rule resource, not an in-place edit of an inline block.
- **Destroy ordering:** an SG cannot be deleted while still attached to an ENI
  (instance, ALB, RDS, NAT). Detach consumers first; eventual consistency may
  briefly report the SG as in use after a consumer is deleted.
- **`tags` vs `tags_all`.** `var.tags` flows to the SG and each rule resource;
  `tags_all` merges resource tags over provider `default_tags` (resource tags
  win). `default_tags` is the caller's concern.
- **`arn` is the cross-resource reference type.**

## Secure-by-default decisions

| Posture | Default | Opt-out |
|---|---|---|
| Ingress | **none** (empty map → deny all inbound) | add `ingress_rules` entries explicitly |
| Egress | caller-defined; no implicit all-open added | add an explicit `0.0.0.0/0` egress rule if needed |
| `0.0.0.0/0` ingress | **never defaulted** | only when a rule's `cidr_ipv4 = "0.0.0.0/0"` is set explicitly (flag in review) |
| Rule descriptions | required per rule (auditability) | n/a |
| Replacement safety | `create_before_destroy` | n/a |

## Design decisions

- One composite owns the SG and its rules as discrete resources so each rule has
  a stable id, clean drift detection, and granular plan diffs — the modern
  community pattern over monolithic inline blocks.
- Rules are `map(object(...))` keyed by a caller-supplied stable string (e.g.
  `"https-from-alb"`), never `count`, so insertion/removal never reshuffles other
  rules.
- The SG is intentionally **not** opinionated about what it protects — it is a
  reusable primitive consumed by compute, load-balancing, and database modules.
