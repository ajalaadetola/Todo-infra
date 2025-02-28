provider "aws" {
  region = "us-east-1"  # Change to your preferred AWS region
}

# Create a VPC
resource "aws_vpc" "devops_vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "devops-vpc"
  }
}

# Create a Subnet
resource "aws_subnet" "devops_subnet" {
  vpc_id                  = aws_vpc.devops_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true  # Ensures instances get a public IP
}

# Create an Internet Gateway
resource "aws_internet_gateway" "devops_igw" {
  vpc_id = aws_vpc.devops_vpc.id
}

# Create a Route Table
resource "aws_route_table" "devops_route_table" {
  vpc_id = aws_vpc.devops_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.devops_igw.id
  }
}

# Associate the Route Table with the Subnet
resource "aws_route_table_association" "devops_rta" {
  subnet_id      = aws_subnet.devops_subnet.id
  route_table_id = aws_route_table.devops_route_table.id
}

# Create a Security Group
resource "aws_security_group" "devops_sg" {
  vpc_id = aws_vpc.devops_vpc.id

  # Allow SSH (Port 22)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow HTTP (Port 80)
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow HTTPS (Port 443)
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create an SSH Key Pair
resource "aws_key_pair" "deployer" {
  key_name   = "deployer-key"
  public_key = file("~/.ssh/id_rsa.pub")  # Ensure this key exists
}

# Create an Elastic IP
resource "aws_eip" "devops_eip" {
  domain = "vpc"
}

# Create an EC2 Instance
resource "aws_instance" "devops_vm" {
  ami             = "ami-04b4f1a9cf54c11d0"  # Ubuntu 22.04 AMI (Update as needed)
  instance_type   = "t2.micro"
  key_name        = aws_key_pair.deployer.key_name
  subnet_id       = aws_subnet.devops_subnet.id
  security_groups = [aws_security_group.devops_sg.name]

  tags = {
    Name = "devops-vm"
  }

  # Attach the Elastic IP
  associate_public_ip_address = true

  # Provisioner to copy Ansible playbook to the EC2 instance
  provisioner "file" {
    source      = "/Users/user/Downloads/Todo-Infra/ansible-playbook.yml"
    destination = "/home/ubuntu/ansible-playbook.yml"

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file("~/.ssh/id_rsa")
      host        = self.public_ip
    }
  }

  # Provisioner to create the inventory file on the instance
  provisioner "remote-exec" {
    inline = [
      "echo '[all]' > /home/ubuntu/inventory",
      "echo 'localhost ansible_connection=local' >> /home/ubuntu/inventory",
    ]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file("~/.ssh/id_rsa")
      host        = self.public_ip
    }
  }

  # Provisioner to install Ansible and run the playbook
  provisioner "remote-exec" {
    inline = [
      "sudo apt update -y",
      "sudo apt install -y ansible",
      "ansible-playbook -i /home/ubuntu/inventory /home/ubuntu/ansible-playbook.yml",
    ]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file("~/.ssh/id_rsa")
      host        = self.public_ip
    }
  }
}

# Output the public IP of the instance
output "public_ip" {
  value = aws_instance.devops_vm.public_ip
}
