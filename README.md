# Automate EC2 Deployment Assignment
## Table of Contents

# Automate EC2 Deployment Assignment


---

## Project Overview

This assignment demonstrates:

4. Running the app on port 8080 or 80.
5. Testing if the app is reachable via browser or curl.
6. Using Terraform to automate EC2 creation (AMI, instance type, key pair, etc.).

The app is a simple Spring Boot MVC application.

---

## Prerequisites

- AWS account with Free Tier enabled
- Terraform installed (for automation)
- Java 21 installed (manual deployment)
- Maven and Git installed on EC2
- SSH key pair for EC2 access

---

## Manual Deployment Steps

### 1. Launch EC2

- Choose Free Tier eligible AMI (Ubuntu 22.04 LTS)
- Instance type: `t2.micro` or `t3.micro`
- Attach your key pair (e.g., `wisecow`)

```
### 4. Clone Repo & Build App
```bash
git clone https://github.com/Trainings-TechEazy/test-repo-for-devops app
cd app
mvn clean package
```bash
ps aux | grep java
```
### 6. Run the Application
- via port 80:
```bash
sudo nohup java -jar target/hellomvc-0.0.1-SNAPSHOT.jar --server.port=80 > ~/techeazy.log 2>&1 &
tail -f ~/techeazy.log
```
- via port 8080:
```bash
nohup java -jar target/hellomvc-0.0.1-SNAPSHOT.jar --server.port=8080 > ~/techeazy.log 2>&1 &
tail -f ~/techeazy.log
```
### 7. Test the Application
- Browser: http://<EC2_PUBLIC_IP>:8080/<endpoint>
      (replace <endpoint> with the path defined in the controller, e.g., /hello)
```bash
http://<EC2_PUBLIC_IP>:8080/<endpoint>
http://<EC2_PUBLIC_IP>:8080/hello
```

## Terraform Deployment
### 1. Variables
    - ami_id → AMI ID of Ubuntu
    - instance_type → t2.micro or t3.micro
    - key_name → Name of your EC2 key pair
    - stage → Dev or Prod for picking configuration
### 2. Commands
```bash
terraform init
terraform plan -var "ami_id=<AMI_ID>" -var "key_name=<KEY_NAME>" -var "stage=Dev"
terraform apply -var "ami_id=<AMI_ID>" -var "key_name=<KEY_NAME>" -var "stage=Dev" -auto-approve
```
- Outputs will include public_ip to access the app.

### 3. Notes & Best Practices
- Avoid running the app with sudo in the project directory to prevent Maven permission issues.
- Use a non-root port (8080) and write logs to the home directory.
- Stop the app before rebuilding:
```bash
pkill -f hellomvc-0.0.1-SNAPSHOT.jar
```
- Edit terraform file as according to your ec2 region.
- You can pass different stages (Dev, Prod) to Terraform to pick different configs.


