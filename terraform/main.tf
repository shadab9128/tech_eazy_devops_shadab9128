provider "aws" {
  region = var.region
}

resource "aws_security_group" "sg" {
  name        = "${var.stage}-sg"
  description = "Allow SSH and HTTP"
  
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "app" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.sg.id]
  tags = {
    Name = "${var.stage}-ec2"
  }

  user_data = <<-EOF
              #!/bin/bash
              sudo apt update -y
              sudo apt install -y openjdk-21-jdk git maven
              cd /home/ubuntu
              git clone ${var.github_repo} app
              cd app
              mvn clean package
              sudo nohup java -jar target/hellomvc-0.0.1-SNAPSHOT.jar --server.port=80 > /var/log/techeazy.log 2>&1 &
              EOF
}

