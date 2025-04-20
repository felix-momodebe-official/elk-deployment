# main.tf - Main Terraform configuration for ELK Stack deployment

provider "aws" {
  region = "us-east-1"
}

# Retrieve existing security group
data "aws_security_group" "existing_sg" {
  id = "sg-06759564b372b17fb"
}

# Create ELK server EC2 instance
resource "aws_instance" "elk_server" {
  ami                    = "ami-084568db4383264d4"
  instance_type          = "t3.large"
  key_name               = "my_default_keypair"
  vpc_security_group_ids = [data.aws_security_group.existing_sg.id]

  tags = {
    Name = "elk-server"
  }

  root_block_device {
    volume_size = 20
  }

  user_data = <<-EOF
    #!/bin/bash
    hostnamectl set-hostname elk-server
    apt-get update
    EOF
}

# Create client machine for log generation
resource "aws_instance" "client_server" {
  ami                    = "ami-084568db4383264d4"
  instance_type          = "t2.micro"
  key_name               = "my_default_keypair"
  vpc_security_group_ids = [data.aws_security_group.existing_sg.id]

  tags = {
    Name = "client-log-generator"
  }

  user_data = <<-EOF
    #!/bin/bash
    hostnamectl set-hostname client-log-generator
    apt-get update
    EOF
}

# Generate inventory file for Ansible dynamically
resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/inventory.tmpl", {
    elk_ip    = aws_instance.elk_server.public_ip
    client_ip = aws_instance.client_server.public_ip
  })
  filename = "${path.module}/../ansible/inventory"
}

# Generate variables file for Ansible dynamically
resource "local_file" "ansible_vars" {
  content = templatefile("${path.module}/vars.tmpl", {
    elk_public_ip  = aws_instance.elk_server.public_ip
    elk_private_ip = aws_instance.elk_server.private_ip
  })
  filename = "${path.module}/../ansible/group_vars/all.yml"
}

# Output important Terraform-generated values
output "elk_server_public_ip" {
  value = aws_instance.elk_server.public_ip
}

output "elk_server_private_ip" {
  value = aws_instance.elk_server.private_ip
}

output "client_server_public_ip" {
  value = aws_instance.client_server.public_ip
}

output "kibana_url" {
  value = "http://${aws_instance.elk_server.public_ip}:5601"
}
