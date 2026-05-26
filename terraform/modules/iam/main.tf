# ==============================================================================
# Module: IAM
# Creates an IAM Role + Instance Profile for EC2 instances.
# The backend EC2 uses this to call Secrets Manager at boot (least-privilege).
# ==============================================================================

# Trust policy — allows EC2 to assume this role
data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# IAM Role
resource "aws_iam_role" "ec2" {
  name               = "${var.project_name}-${var.environment}-${var.role_suffix}-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
  description        = "EC2 role for ${var.project_name} ${var.environment} - Secrets Manager access"

  tags = {
    Name = "${var.project_name}-${var.environment}-${var.role_suffix}-role"
  }
}

# Inline policy — GetSecretValue on only the project's secrets (least privilege)
data "aws_iam_policy_document" "secrets_access" {
  statement {
    sid    = "ReadProjectSecrets"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret"
    ]
    # Restrict to secrets under /{env}/{project}/* only
    resources = [
      "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:/${var.environment}/${var.project_name}/*"
    ]
  }
}

data "aws_caller_identity" "current" {}

resource "aws_iam_role_policy" "secrets_access" {
  name   = "${var.project_name}-${var.environment}-secrets-policy"
  role   = aws_iam_role.ec2.id
  policy = data.aws_iam_policy_document.secrets_access.json
}

# CloudWatch agent policy — for log shipping (optional, attach when needed)
resource "aws_iam_role_policy_attachment" "cloudwatch" {
  count      = var.attach_cloudwatch_policy ? 1 : 0
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# SSM Session Manager — allows terminal access without opening SSH port
resource "aws_iam_role_policy_attachment" "ssm" {
  count      = var.attach_ssm_policy ? 1 : 0
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Instance Profile — bridges the IAM role to an EC2 instance
resource "aws_iam_instance_profile" "ec2" {
  name = "${var.project_name}-${var.environment}-${var.role_suffix}-profile"
  role = aws_iam_role.ec2.name

  tags = {
    Name = "${var.project_name}-${var.environment}-${var.role_suffix}-profile"
  }
}
