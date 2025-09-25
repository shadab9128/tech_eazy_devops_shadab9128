This assignment demonstrates:

4. Running the app on port 8080 or 80.
5. Testing if the app is reachable via browser or curl.
6. Using Terraform to automate EC2 creation (AMI, instance type, key pair, etc.).

The app is a simple Spring Boot MVC application.

---

## Prerequisites

- AWS account with Free Tier enabled
- Terraform installed
- Java 21 installed
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

-------------------------------------------------------------------------------------

# Assignment 2

## 📋 Assignment Overview
This project automates the creation of AWS infrastructure including IAM roles, S3 buckets, EC2 instances, and log management systems as per the assignment requirements.

## 🎯 Assignment Requirements Completed

### ✅ 1. IAM Roles Creation
- **S3 Read-Only Role** (`dev-s3-read-role`): Allows listing and reading objects from S3
- **S3 Write-Only Role** (`dev-s3-uploader-role`): Allows creating buckets and uploading files (no read/download permissions)

### ✅ 2. EC2 Instance Profile
- **Instance Profile**: `Dev-uploader-profile` attached to EC2 instance
- **IAM Role Attachment**: Write-only role attached via IAM instance profile

### ✅ 3. Private S3 Bucket
- **Bucket Name**: `techeazy-logs-devops` (configurable)
- **Privacy**: Private bucket with blocked public access
- **Validation**: Terminates with error if bucket name not provided

### ✅ 4. EC2 Logs Upload
- **Logs Archived**: `/var/log/cloud-init.log` uploaded to S3 on shutdown
- **Destination**: `s3://techeazy-logs-devops/ec2/logs/`

### ✅ 5. Application Logs Upload
- **Application**: Spring Boot app deployed on EC2
- **Logs Uploaded**: Application logs to `s3://techeazy-logs-devops/app/logs/`
- **Automation**: Systemd service for shutdown upload

### ✅ 6. S3 Lifecycle Rules
- **Retention**: Logs automatically deleted after 7 days
- **Configuration**: Lifecycle rules for both EC2 and app logs

### ✅ 7. Read-Only Access Verification
- **Verification**: Files can be listed using read-only role
- **Testing**: Successful listing of S3 bucket contents

## Deployment Steps
### 1. Plan Deployment
```bash
terraform plan   -var="ami_id=<Your_EC2_AMI_ID>"   -var="key_name=<Your_Key_Pair_Name>"   -var="s3_bucket_name
=<Bucket_Name>"
```
### 2. Apply configuration
```bash
terraform apply   -var="ami_id=<Your_EC2_AMI_ID>"   -var="key_name=<Your_Key_Pair_Name>"   -var="s3_bucket_name
=<Bucket_Name>" -auto-approve
```

## Verification
```bash
# Check created resources
terraform output

# SSH into EC2 instance
ssh -i your-key.pem ec2-user@<instance-ip>

# Test log upload manually
sudo /usr/local/bin/upload-logs.sh

# Verify S3 contents
aws s3 ls s3://Bucket-Name/ --recursive
```
## S3 Bucket Structure
Bucket-Name/
├── ec2/logs/
│   ├── cloud-init-123XYZxxxxxxx.log
│   └── test-upload.log
└── app/logs/
    └── XXXXXXXXX.log

## Testing
```bash
# Manual upload test
sudo /usr/local/bin/upload-logs.sh

# Verify upload
aws s3 ls s3://Your-Bucket-Nmae/ --recursive
```
## Read Access Test(Private)
```bash
aws s3 ls s3://techeazy-logs-devops/ --recursive --human-readable
```

## Application Test
```bash
curl http://localhost:8080
```

## Cleanup
```bash
# Destroy all resources
terraform destroy -auto-approve

# Manual cleanup if needed
aws s3 rb s3://Your-Bucket-name --force
aws iam delete-role --role-name Your-role-name
```
## Outputs
After successful deployment:

S3 Bucket:

EC2 Instance ID:

Public DNS:

Public IP:

