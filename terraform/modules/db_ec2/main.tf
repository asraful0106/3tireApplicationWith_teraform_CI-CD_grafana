# ==============================================================================
# Module: db_ec2 (FIXED & ROBUST)
# PostgreSQL 15 on EC2 replacement for RDS
# ==============================================================================

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "db" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = var.db_subnet_id
  vpc_security_group_ids = [var.db_security_group_id]
  key_name               = var.key_name

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size_gb
    delete_on_termination = true
    encrypted             = true
  }

  user_data = templatefile("${path.module}/scripts/db.sh", {
    db_username             = var.db_username
    db_password             = var.db_password
    db_name                 = var.db_name
    vpc_cidr                = var.vpc_cidr
    aws_region              = var.aws_region
    db_password_secret_arn  = var.db_password_secret_arn
  })
  
  user_data_replace_on_change = true

  tags = {
    Name = "${var.project_name}-${var.environment}-db-ec2"
    Role = "database"
  }
}