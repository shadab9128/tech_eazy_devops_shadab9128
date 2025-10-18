# Assignment-3: Automated EC2 Deployment with ALB & Self-Updating

This project demonstrates deploying multiple EC2 instances with a **Java Spring Boot app**, using **Terraform**, **ALB**, **S3**, and automated **self-updating deployment** via scripts.

---

## 🔹 Features

- Deploy EC2 instances via Terraform.
- Application Load Balancer (ALB) with HTTP routing.
- Poll S3 for new JAR files and auto-restart the app.
- Upload logs to S3 on shutdown.
- Fully automated with **GitHub Actions**.


---

## ⚙ Prerequisites

- AWS account with sufficient permissions.
- Terraform installed locally or via GitHub Actions.
- Java JDK 17+ installed on EC2 (user-data handles installation).
- AWS CLI installed (optional for manual testing).
- GitHub repository with secrets:

| Secret Name                  | Purpose                                  |
|-------------------------------|-----------------------------------------|
| `AWS_ACCESS_KEY_ID`           | AWS API Access Key                       |
| `AWS_SECRET_ACCESS_KEY`       | AWS API Secret Key                       |
| `AWS_REGION`                  | AWS Region (e.g., eu-north-1)          |
| `AMI_ID`                      | AMI ID to use for EC2 instances         |
| `EC2_KEY_NAME`                | SSH key pair name                        |
| `S3_BUCKET_NAME`              | S3 bucket to upload logs & JAR           |
| `INSTANCE_COUNT`              | Number of EC2 instances to launch       |

---

## 🛠 Step-by-Step Deployment (Manual)

> **Note:** Replace placeholders like `<your-key>` and `<EC2_PUBLIC_IP>`.

### 1. Initialize Terraform
```bash
terraform init
```
### 2. Plan Terraform
```bash
terraform plan \
  -var="ami_id=<AMI_ID>" \
  -var="key_name=<KEY_NAME>" \
  -var="s3_bucket_name=<S3_BUCKET_NAME>" \
  -var="instance_count=2"
```
### 3. Apply Terraform
```bash
terraform apply \
  -auto-approve \
  -var="ami_id=<AMI_ID>" \
  -var="key_name=<KEY_NAME>" \
  -var="s3_bucket_name=<S3_BUCKET_NAME>" \
  -var="instance_count=2"
```
### 4. Verify EC2 Instances
```bash
aws ec2 describe-instances \
  --filters "Name=tag:Stage,Values=dev" \
  --query "Reservations[].Instances[].{ID:InstanceId,State:State.Name,PrivateIP:PrivateIpAddress}" \
  --region eu-north-1
```
### 5. Upload Application JAR to S3
```bash
aws s3 cp ~/target/hellomvc-0.0.1-SNAPSHOT.jar s3://<S3_BUCKET_NAME>/app/hellomvc-0.0.1-SNAPSHOT.jar
```
### 6. Prepare EC2 App Directory
```bash
mkdir -p ~/app
```
### 7. Run Application (Local Test)
```bash
nohup java -jar ~/target/hellomvc-0.0.1-SNAPSHOT.jar --server.port=8080 > ~/app/techeazy.log 2>&1 &
ps aux | grep java
tail -f ~/app/techeazy.log
```
### 8. Access Application
```bash
curl http://localhost:8080/hello
# OR from browser
http://<EC2_PUBLIC_IP>:8080/hello
```
### 9. Connect to Another EC2 Instance
```bash
ssh -i <your-key>.pem ubuntu@<EC2-Public-IP>
sudo snap install aws-cli
```
### 10. Download and Run JAR on Other EC2
```bash
aws s3 cp s3://<S3_BUCKET_NAME>/app/hellomvc-0.0.1-SNAPSHOT.jar ~/app/hellomvc-0.0.1-SNAPSHOT.jar
sudo apt install openjdk-17-jdk
nohup java -jar ~/app/hellomvc-0.0.1-SNAPSHOT.jar --server.port=8080 > ~/app/techeazy.log 2>&1
tail -n 50 ~/app/techeazy.log
curl http://localhost:8080/hello
```
### 11. Access via ALB
```bash
curl http://<ALB_DNS>/hello
# Browser: http://<ALB_DNS>/hello
```

## Scripts Usage
### Polls S3 for new JARs and restarts the app automatically.
```bash
chmod +x poll_s3.sh
nohup ./poll_s3.sh <S3_BUCKET> <S3_KEY> <LOCAL_JAR_PATH> <LOG_FILE> &
tail -f ~/techeazy.log
cat nohup.out
```

### Secrets required
- AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_REGION, AMI_ID, EC2_KEY_NAME, S3_BUCKET_NAME, INSTANCE_COUNT.

-------------------------------------------------------------
# For AutoScaling Extend Version of Assignment-3

## 1. Clone Repository
```bash
git clone <your-repo-url>
cd Assignment-3/terraform
```
## 2. Initialize Terraform
```bash
terraform init
```
## 3. Deploy Infrastructure
```bash
terraform apply -auto-approve \
  -var="region=" \
  -var="stage=" \
  -var="" \
  -var="instance_type=t3.micro" \
  -var="key_name=your-key-pair" \
  -var="existing_bucket_name=your-bucket" \
  -var="existing_jar_key=app.jar"
```
## 4. Check Infrastructure Status
```bash
terraform output alb_dns_name
# Test application
curl http://$(terraform output -raw alb_dns_name)/hello
```
## 5. Verify Auto Scaling
```bash
# Check Auto Scaling Group
aws autoscaling describe-auto-scaling-groups

# Check EC2 instances
aws ec2 describe-instances --filters "Name=instance-state-name,Values=running"
```
## 6. Cleanup
```bash
terraform destroy -auto-approve
```
## 7. Debug Commands
```bash
# SSH into instance and check logs
tail -f /var/log/cloud-init-output.log
journalctl -u application-service

# Check application status
curl http://localhost:8080/hello
ps aux | grep java
```
