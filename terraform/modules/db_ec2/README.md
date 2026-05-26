# db_ec2 Module — PostgreSQL on EC2 (RDS Drop-in Replacement)

## Why this exists

Your IAM user lacks `rds:*` permissions, so this module runs **PostgreSQL 15
on a plain EC2 instance** inside the exact same private subnet and security
group that RDS was using. Nothing else in your infrastructure changes.

---

## What stays 100 % unchanged

| Resource | Status |
|---|---|
| VPC | ✅ unchanged |
| Private / public subnets | ✅ unchanged |
| NAT Gateway | ✅ unchanged |
| DB Security Group | ✅ unchanged (same SG passed in) |
| Secrets Manager secrets | ✅ unchanged (same `secrets` module) |
| `DATABASE_URL` format | ✅ unchanged (`postgresql://user:pass@host:5432/db`) |

---

## How to wire it in your root `main.tf`

Replace your existing `module "rds"` block with `module "db_ec2"`:

```hcl
# BEFORE (remove/comment out)
# module "rds" {
#   source            = "./modules/rds"
#   ...
#   db_subnet_group   = module.vpc.db_subnet_group_name
#   db_security_group = module.vpc.db_security_group_id
#   db_password       = module.secrets.db_password
# }

# AFTER
module "db_ec2" {
  source = "./modules/db_ec2"

  project_name  = var.project_name
  environment   = var.environment
  aws_region    = var.aws_region

  # ── Networking (same values you passed to RDS) ──────────────────────────────
  db_subnet_id         = module.vpc.db_subnet_ids[0]   # one private DB subnet
  db_security_group_id = module.vpc.db_security_group_id
  vpc_cidr             = module.vpc.vpc_cidr

  # ── Database credentials ─────────────────────────────────────────────────────
  db_password_secret_arn = module.secrets.db_password_secret_arn
  db_username            = "bmi_user"
  db_name                = "bmidb"

  # ── EC2 sizing ───────────────────────────────────────────────────────────────
  instance_type       = "t3.micro"   # same footprint as db.t3.micro RDS
  root_volume_size_gb = 20
  key_name            = var.key_name
}

# The secrets module call is IDENTICAL — only db_host changes source
module "secrets" {
  source      = "./modules/secrets"
  project_name = var.project_name
  environment  = var.environment

  db_host     = module.db_ec2.db_host   # was: module.rds.db_host
  db_username = "bmi_user"
  db_name     = "bmidb"
}
```

### Output references — find & replace in your root outputs / other modules

| Old reference | New reference |
|---|---|
| `module.rds.db_host` | `module.db_ec2.db_host` |
| `module.rds.db_port` | `module.db_ec2.db_port` |
| `module.rds.db_name` | `module.db_ec2.db_name` |

---

## How the bootstrap works (user_data)

The script runs **once at first boot** and stays well under AWS's 16 KB limit
(actual size ≈ 1.2 KB):

1. Installs `postgresql15` and `postgresql15-server` via `dnf`
2. Runs `postgresql-setup --initdb` to initialise the data cluster
3. Calls **Secrets Manager** (`aws secretsmanager get-secret-value`) to fetch
   the password — no credentials are baked into the AMI or user_data
4. Creates the role `bmi_user` and database `bmidb`
5. Rewrites `pg_hba.conf` to allow `scram-sha-256` auth **only from the VPC
   CIDR** — everything else is denied
6. Sets `listen_addresses = '*'` in `postgresql.conf` (the security group
   restricts who can actually reach port 5432)
7. Reloads PostgreSQL

Boot log is available at `/var/log/db-init.log` on the instance.

---

## Connecting / debugging

```bash
# SSH into backend EC2, then:
psql "postgresql://bmi_user:<pass>@<db_private_ip>:5432/bmidb"

# Or from the DB EC2 itself via SSM Session Manager (no SSH needed):
aws ssm start-session --target <instance_id>
sudo -u postgres psql
```

---

## terraform.tfvars — remove the RDS-only variable

```hcl
# Remove or comment out — no longer needed:
# db_instance_class = "db.t3.micro"
```

---

## IAM permissions required (much smaller than RDS)

Your IAM user only needs these to run `terraform apply`:

```
ec2:RunInstances, ec2:DescribeInstances, ec2:TerminateInstances,
ec2:CreateTags, ec2:DescribeImages,
iam:CreateRole, iam:AttachRolePolicy, iam:CreateInstanceProfile,
iam:PassRole, iam:PutRolePolicy,
secretsmanager:GetSecretValue (already granted)
```

No `rds:*` permissions needed at all.
