#!/bin/bash
# deploy.sh - Automates deployment of ELK stack with Terraform and Ansible

set -e

# Check if the directory structure is correct
if [ ! -d "terraform" ] || [ ! -d "ansible" ] || [ ! -d "ansible/templates" ]; then
    echo "Error: Directory structure is incorrect. Please ensure you have:"
    echo "  - terraform/ directory with main.tf, inventory.tmpl, vars.tmpl"
    echo "  - ansible/ directory with site.yml"
    echo "  - ansible/templates/ directory with template files"
    exit 1
fi

# Step 1: Initialize and apply Terraform
echo "Initializing Terraform..."
cd terraform
terraform init

echo "Applying Terraform configuration..."
terraform apply -auto-approve

# Step 2: Wait for servers to be ready
echo "Waiting for servers to be ready (90 seconds)..."
sleep 90

# Step 3: Run Ansible playbook
echo "Running Ansible playbook..."
cd ../ansible
ansible-playbook -i inventory site.yml

echo "Deployment completed successfully!"
echo "Kibana dashboard is available at: http://$(cd ../terraform && terraform output -raw elk_server_public_ip):5601"
