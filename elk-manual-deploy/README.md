# Manual ELK Stack Deployment Guide

This guide provides step-by-step instructions for setting up the ELK Stack (Elasticsearch, Logstash, Kibana) with Filebeat to monitor logs from a Java application running on AWS EC2 Ubuntu instances.

## 1. Overview of ELK Stack

The ELK Stack consists of:
- **Elasticsearch** → Stores and indexes logs.
- **Logstash** → Processes and transforms logs before storing them in Elasticsearch.
- **Kibana** → Provides visualization and analysis of logs.
- **Filebeat** → Forwards logs from the application to Logstash.

## 2. Infrastructure Setup

This setup uses two EC2 Ubuntu machines:
1. **ELK Server** → Hosts Elasticsearch, Logstash, Kibana.
2. **Client Machine** → Hosts Java application and Filebeat.

## 3. Step-by-Step Installation

### Step 1: Install & Configure Elasticsearch (ELK Server)

#### 1.1 Install Java (Required for Elasticsearch & Logstash)
```bash
sudo apt update && sudo apt install openjdk-17-jre-headless -y
```

#### 1.2 Install Elasticsearch
```bash
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo apt-key add -
echo "deb https://artifacts.elastic.co/packages/7.x/apt stable main" | sudo tee /etc/apt/sources.list.d/elastic-7.x.list
sudo apt update
sudo apt install elasticsearch -y
```

#### 1.3 Configure Elasticsearch
```bash
sudo vi /etc/elasticsearch/elasticsearch.yml
```

Modify the following parameters:
```yaml
network.host: 0.0.0.0
cluster.name: my-cluster
node.name: node-1
discovery.type: single-node
```

#### 1.4 Start & Enable Elasticsearch
```bash
sudo systemctl start elasticsearch
sudo systemctl enable elasticsearch
sudo systemctl status elasticsearch
```

#### 1.5 Verify Elasticsearch
```bash
curl -X GET "http://localhost:9200"
```

### Step 2: Install & Configure Logstash (ELK Server)

#### 2.1 Install Logstash
```bash
sudo apt install logstash -y
```

#### 2.2 Configure Logstash to Accept Logs
```bash
sudo vi /etc/logstash/conf.d/logstash.conf
```

Add the following configuration:
```
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
```

#### 2.3 Start & Enable Logstash
```bash
sudo systemctl start logstash
sudo systemctl enable logstash
sudo systemctl status logstash
```

#### 2.4 Allow Traffic on Port 5044
```bash
sudo ufw allow 5044/tcp
```

### Step 3: Install & Configure Kibana (ELK Server)

#### 3.1 Install Kibana
```bash
sudo apt install kibana -y
```

#### 3.2 Configure Kibana
```bash
sudo vi /etc/kibana/kibana.yml
```

Modify the following parameters:
```yaml
server.host: "0.0.0.0"
elasticsearch.hosts: ["http://localhost:9200"]
```

#### 3.3 Start & Enable Kibana
```bash
sudo systemctl start kibana
sudo systemctl enable kibana
sudo systemctl status kibana
```

#### 3.4 Allow Traffic on Port 5601
```bash
sudo ufw allow 5601/tcp
```

#### 3.5 Access Kibana Dashboard
Open a browser and go to:
```
http://<ELK_Server_Public_IP>:5601
```

### Step 4: Install & Configure Filebeat (Client Machine)

#### 4.1 Install Filebeat
```bash
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo apt-key add -
echo "deb https://artifacts.elastic.co/packages/7.x/apt stable main" | sudo tee /etc/apt/sources.list.d/elastic-7.x.list
sudo apt update
sudo apt install filebeat -y
```

#### 4.2 Configure Filebeat to Send Logs to Logstash
```bash
sudo vi /etc/filebeat/filebeat.yml
```

Modify the following parameters:
```yaml
filebeat.inputs:
- type: log
  enabled: true
  paths:
    - /home/ubuntu/maven-web-app/target/app.log

output.logstash:
  hosts: ["<ELK_Server_Private_IP>:5044"]
```

#### 4.3 Start & Enable Filebeat
```bash
sudo systemctl start filebeat
sudo systemctl enable filebeat
sudo systemctl status filebeat
```

#### 4.4 Verify Filebeat is Sending Logs
```bash
sudo filebeat test output
```

### Step 5: Deploy Java Application & Generate Logs

#### 5.1 Install Java (If Not Installed)
```bash
sudo apt install openjdk-17-jre-headless -y
```

#### 5.2 Clone the repo, build & Run Sample Java App
```bash
git clone https://github.com/felix-momodebe-official/maven-web-app.git
nohup mvn jetty:run > /home/ubuntu/maven-web-app/target/app.log 2>&1 &
```

#### 5.3 Verify Java Application is Running
```bash
ps aux | grep jetty
```

#### 5.4 Generate Logs for Testing
```bash
echo "Test log entry $(date)" >> /home/ubuntu/maven-web-app/target/app.log
```

### Step 6: View & Analyze Logs in Kibana

#### 6.1 Open Kibana Discover
1. Go to Kibana → Discover.
2. Select log* index.
3. Search for:
   ```
   log.file.path: "/home/ubuntu/maven-web-app/target/app.log"
   ```
4. View structured fields (log_timestamp, log_level, log_message).

#### 6.2 Create Kibana Visualizations
1. Pie Chart → Log level distribution.
2. Line Chart → Logs over time.
3. Data Table → Structured log table.

#### 6.3 Create a Kibana Dashboard
1. Go to Kibana → Dashboard → Create Dashboard.
2. Add Pie Chart, Line Chart, Data Table.
3. Save as "Java Application Log Monitoring".

## Conclusion

You have successfully:
- Installed Elasticsearch, Logstash, Kibana, and Filebeat
- Set up a Java application to generate logs
- Parsed logs into structured fields using Grok
- Created a real-time Kibana dashboard for log monitoring

## Troubleshooting Tips

- **Elasticsearch not starting**: Check Java version and memory allocation
- **Logstash not receiving logs**: Verify firewall settings and Filebeat configuration
- **Kibana not connecting to Elasticsearch**: Check network settings and Elasticsearch status
- **Filebeat not sending logs**: Verify file paths and Logstash connectivity
