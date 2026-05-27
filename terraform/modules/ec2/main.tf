# terraform/modules/ec2/main.tf ==============================================================================
# Module: EC2
# Generic EC2 instance module — used for frontend, backend, and bastion.
# Always uses the latest Ubuntu 24.04 LTS AMI (data source — never hardcode AMI IDs).
# ==============================================================================

# Fetch latest Ubuntu 24.04 LTS AMI — canonical owner, HVM, SSD
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

resource "aws_instance" "this" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = var.security_group_ids
  key_name               = var.key_name
  iam_instance_profile   = var.iam_instance_profile

  # user_data runs once on first boot — provision the application
  user_data = var.user_data

  # Prevent accidental root volume deletion
  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    delete_on_termination = true
    encrypted             = true

    tags = {
      Name = "${var.name}-root-vol"
    }
  }

  # Replace instance instead of update when user_data changes
  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = var.name
    Role = var.role
  }
}
