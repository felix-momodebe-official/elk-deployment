#!/bin/bash
# setup.sh - Sets up the directory structure for the ELK stack automation

set -e

# Create directory structure
echo "Creating directory structure..."
mkdir -p terraform ansible/templates ansible/group_vars

# Create Terraform files
echo "Creating Terraform files..."
cat > terraform/main.tf << 'EOF'
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
EOF

cat > terraform/inventory.tmpl << 'EOF'
[elk]
${elk_ip} ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/my_default_keypair.pem

[client]
${client_ip} ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/my_default_keypair.pem

[all:vars]
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
EOF

cat > terraform/vars.tmpl << 'EOF'
---
elk_server_public_ip: "${elk_public_ip}"
elk_server_private_ip: "${elk_private_ip}"
EOF

# **Ensure Updated Ansible Playbook is Used Instead of Old Copy**
echo "Creating Ansible files..."
cat > ansible/site.yml << 'EOF'
# site.yml - Updated Ansible playbook for ELK deployment

---
- name: Configure ELK Server
  hosts: elk
  become: yes
  tasks:
    - name: Update apt cache
      apt:
        update_cache: yes

    - name: Install Java
      apt:
        name: openjdk-17-jre-headless
        state: present

    - name: Add Elastic GPG key
      apt_key:
        url: https://artifacts.elastic.co/GPG-KEY-elasticsearch
        state: present

    - name: Add Elastic repository
      apt_repository:
        repo: "deb https://artifacts.elastic.co/packages/7.x/apt stable main"
        state: present
        filename: elastic-7.x

    - name: Install specific version of Elasticsearch with downgrade support
      apt:
        name: elasticsearch=7.17.0
        state: present
        update_cache: yes
        allow_downgrade: yes

    - name: Stop Elasticsearch service after installation to prevent port conflict
      systemd:
        name: elasticsearch
        state: stopped
        enabled: no
      ignore_errors: yes

    - name: Verify Elasticsearch service is stopped
      systemd:
        name: elasticsearch
        state: stopped
      register: es_stopped
      until: es_stopped.status.ActiveState == "inactive"
      retries: 5
      delay: 5

    - name: Debug Elasticsearch service status
      debug:
        var: es_stopped
      when: es_stopped is defined

    - name: Configure system settings for Elasticsearch
      sysctl:
        name: "{{ item.name }}"
        value: "{{ item.value }}"
        state: present
      loop:
        - { name: "vm.max_map_count", value: "262144" }
        - { name: "vm.swappiness", value: "1" }

    - name: Set file descriptor limit for Elasticsearch
      lineinfile:
        path: /etc/security/limits.conf
        line: "{{ item }}"
      loop:
        - "elasticsearch soft nofile 65536"
        - "elasticsearch hard nofile 65536"

    - name: Set Elasticsearch JVM options
      lineinfile:
        path: /etc/elasticsearch/jvm.options.d/override.options
        line: "{{ item }}"
        create: yes
        owner: elasticsearch
        group: elasticsearch
        mode: '0644'
      loop:
        - "-Xms2g"
        - "-Xmx2g"

    - name: Set Elasticsearch file permissions for data directory
      file:
        path: /var/lib/elasticsearch
        state: directory
        owner: elasticsearch
        group: elasticsearch
        mode: '0755'

    - name: Set Elasticsearch file permissions for log directory
      file:
        path: /var/log/elasticsearch
        state: directory
        owner: elasticsearch
        group: elasticsearch
        mode: '0755'

    - name: Set Elasticsearch file permissions for alternate log directory
      file:
        path: /usr/share/elasticsearch/logs
        state: directory
        owner: elasticsearch
        group: elasticsearch
        mode: '0755'

    - name: Set Elasticsearch file permissions for config directory
      file:
        path: /etc/elasticsearch
        state: directory
        owner: elasticsearch
        group: elasticsearch
        mode: '0755'
        recurse: yes

    - name: Check if port 9200 is in use
      shell: lsof -i :9200 || true
      register: port_9200_check
      changed_when: false

    - name: Kill process using port 9200 if exists
      shell: kill -9 $(lsof -t -i :9200) || true
      when: port_9200_check.stdout != ""
      retries: 3
      delay: 5

    - name: Verify port 9200 is free
      wait_for:
        port: 9200
        state: stopped
        timeout: 30
      ignore_errors: yes

    - name: Check if port 9300 is in use
      shell: lsof -i :9300 || true
      register: port_9300_check
      changed_when: false

    - name: Kill process using port 9300 if exists
      shell: kill -9 $(lsof -t -i :9300) || true
      when: port_9300_check.stdout != ""
      retries: 3
      delay: 5

    - name: Verify port 9300 is free
      wait_for:
        port: 9300
        state: stopped
        timeout: 30
      ignore_errors: yes

    - name: Configure Elasticsearch
      template:
        src: templates/elasticsearch.yml.j2
        dest: /etc/elasticsearch/elasticsearch.yml
        owner: elasticsearch
        group: elasticsearch
        mode: '0644'
      notify: restart elasticsearch

    - name: Debug Elasticsearch configuration
      command: cat /etc/elasticsearch/elasticsearch.yml
      register: es_config
      changed_when: false

    - name: Display Elasticsearch configuration
      debug:
        msg: "{{ es_config.stdout_lines }}"

    - name: Ensure Elasticsearch is stopped before starting
      systemd:
        name: elasticsearch
        state: stopped
      ignore_errors: yes

    - name: Wait for configuration to settle
      pause:
        seconds: 10

    - name: Start and enable Elasticsearch with retries
      systemd:
        name: elasticsearch
        state: started
        enabled: yes
      register: es_start
      until: es_start.state == "started"
      retries: 5
      delay: 10

    - name: Debug Elasticsearch status on failure
      command: systemctl status elasticsearch.service
      register: es_status
      failed_when: false
      when: ansible_failed_task is defined

    - name: Display Elasticsearch status if failed
      debug:
        msg: "{{ es_status.stdout_lines }}"
      when: es_status.stdout is defined

    - name: Debug Elasticsearch logs on failure
      command: journalctl -u elasticsearch.service --no-pager -n 50
      register: es_logs
      failed_when: false
      when: ansible_failed_task is defined

    - name: Display Elasticsearch logs if failed
      debug:
        msg: "{{ es_logs.stdout_lines }}"
      when: es_logs.stdout is defined

    - name: Verify Elasticsearch is running
      uri:
        url: "http://{{ elk_server_private_ip }}:9200"
        method: GET
        status_code: 200
      register: es_check
      retries: 5
      delay: 10
      until: es_check.status == 200

    - name: Install Logstash
      apt:
        name: logstash=1:7.17.0-1
        state: present
        allow_downgrade: yes

    - name: Configure Logstash
      template:
        src: templates/logstash.conf.j2
        dest: /etc/logstash/conf.d/logstash.conf
        owner: logstash
        group: logstash
        mode: '0644'
      notify: restart logstash

    - name: Start and enable Logstash
      systemd:
        name: logstash
        state: started
        enabled: yes

    - name: Install Kibana
      apt:
        name: kibana=7.17.0
        state: present
        allow_downgrade: yes

    - name: Configure Kibana
      template:
        src: templates/kibana.yml.j2
        dest: /etc/kibana/kibana.yml
        owner: kibana
        group: kibana
        mode: '0644'
      notify: restart kibana

    - name: Start and enable Kibana
      systemd:
        name: kibana
        state: started
        enabled: yes

  handlers:
    - name: restart elasticsearch
      systemd:
        name: elasticsearch
        state: restarted
        enabled: yes

    - name: restart logstash
      systemd:
        name: logstash
        state: restarted
        enabled: yes

    - name: restart kibana
      systemd:
        name: kibana
        state: restarted
        enabled: yes

- name: Configure Client Machine
  hosts: client
  become: yes
  tasks:
    - name: Update apt cache
      apt:
        update_cache: yes

    - name: Install Java
      apt:
        name: openjdk-17-jre-headless
        state: present

    - name: Install Maven
      apt:
        name: maven
        state: present

    - name: Remove existing Java application directory if it exists
      file:
        path: /home/ubuntu/maven-web-app
        state: absent
      become_user: ubuntu

    - name: Clone Java application repository
      git:
        repo: "https://github.com/felix-momodebe-official/maven-web-app.git"
        dest: /home/ubuntu/maven-web-app
        version: main
        force: yes
      become_user: ubuntu

    - name: Create app directory structure
      file:
        path: /home/ubuntu/maven-web-app/target
        state: directory
        owner: ubuntu
        group: ubuntu
        mode: '0755'

    - name: Build Java application (Maven)
      shell: cd /home/ubuntu/maven-web-app && mvn clean package
      become_user: ubuntu

    - name: Create log file
      file:
        path: /home/ubuntu/maven-web-app/target/app.log
        state: touch
        owner: ubuntu
        group: ubuntu
        mode: '0644'

    - name: Start Java application with Maven Jetty
      shell: cd /home/ubuntu/maven-web-app && nohup mvn jetty:run > /home/ubuntu/maven-web-app/target/app.log 2>&1 &
      become_user: ubuntu
      ignore_errors: yes

    - name: Wait for logs to be generated
      pause:
        seconds: 30

    - name: Debug log file contents
      command: cat /home/ubuntu/maven-web-app/target/app.log
      register: app_logs
      changed_when: false

    - name: Display log file contents
      debug:
        msg: "{{ app_logs.stdout_lines }}"

    - name: Add Elastic GPG key
      apt_key:
        url: https://artifacts.elastic.co/GPG-KEY-elasticsearch
        state: present

    - name: Add Elastic repository
      apt_repository:
        repo: "deb https://artifacts.elastic.co/packages/7.x/apt stable main"
        state: present
        filename: elastic-7.x

    - name: Install Filebeat
      apt:
        name: filebeat=7.17.0
        state: present
        update_cache: yes
        allow_downgrade: yes

    - name: Configure Filebeat
      template:
        src: templates/filebeat.yml.j2
        dest: /etc/filebeat/filebeat.yml
      notify: restart filebeat

    - name: Start and enable Filebeat
      systemd:
        name: filebeat
        state: started
        enabled: yes

  handlers:
    - name: restart filebeat
      systemd:
        name: filebeat
        state: restarted
EOF

# Create template files
echo "Creating template files..."
cat > ansible/templates/elasticsearch.yml.j2 << 'EOF'
network.host: 0.0.0.0
cluster.name: my-cluster
node.name: node-1
discovery.type: single-node
http.port: 9200
transport.port: 9300
path.logs: /var/log/elasticsearch
path.data: /var/lib/elasticsearch
EOF

cat > ansible/templates/logstash.conf.j2 << 'EOF'
input {
  beats {
    port => 5044
  }
}

filter {
  grok {
    match => { "message" => "%{TIMESTAMP_ISO8601:log_timestamp} %{LOGLEVEL:log_level} %{GREEDYDATA:log_message}" }
  }
}

output {
  elasticsearch {
    hosts => ["http://localhost:9200"]
    index => "logs-%{+YYYY.MM.dd}"
  }
  stdout { codec => rubydebug }
}
EOF

cat > ansible/templates/kibana.yml.j2 << 'EOF'
server.host: "0.0.0.0"
server.port: 5601
elasticsearch.hosts: ["http://localhost:9200"]
EOF

cat > ansible/templates/filebeat.yml.j2 << 'EOF'
filebeat.inputs:
- type: log
  enabled: true
  paths:
    - /home/ubuntu/maven-web-app/target/app.log

output.logstash:
  hosts: ["{{ elk_server_private_ip }}:5044"]
EOF

# Create deploy script
echo "Creating deployment script..."
cat > deploy.sh << 'EOF'
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
EOF

# Make scripts executable
chmod +x deploy.sh

echo "Setup completed! Directory structure and files have been created."
echo "You can now run './deploy.sh' to start the deployment."
