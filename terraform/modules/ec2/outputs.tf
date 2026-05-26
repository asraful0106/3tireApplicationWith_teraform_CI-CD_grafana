output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.this.id
}

output "private_ip" {
  description = "Private IP address of the instance"
  value       = aws_instance.this.private_ip
}

output "public_ip" {
  description = "Public IP (only for instances in public subnets)"
  value       = aws_instance.this.public_ip
}

output "availability_zone" {
  description = "Availability zone where the instance is deployed"
  value       = aws_instance.this.availability_zone
}

output "ami_id" {
  description = "AMI ID used (Ubuntu 22.04 LTS)"
  value       = data.aws_ami.ubuntu.id
}
