provider "aws" {
  region = "ap-south-1"
  profile = "mayank"
}

#VPC
resource "aws_vpc" "myvpc" {
  cidr_block       = "192.168.0.0/16"
  instance_tenancy = "default"
  enable_dns_hostnames = "true"

  tags = {
    Name = "myvpc"
  }
}

#Public_Subnet
resource "aws_subnet" "mysubnet-1a" {
  vpc_id     = aws_vpc.myvpc.id
  cidr_block = "192.168.0.0/24"
  availability_zone = "ap-south-1a"
  map_public_ip_on_launch = "true"
  depends_on = [
    aws_vpc.myvpc,
  ]

  tags = {
    Name = "mysubnet-1a"
  }
}

#Private_Subnet
resource "aws_subnet" "mysubnet-1b" {
  vpc_id     = aws_vpc.myvpc.id
  cidr_block = "192.168.1.0/24"
  availability_zone = "ap-south-1b"
  depends_on = [
    aws_vpc.myvpc,
  ]

  tags = {
    Name = "mysubnet-1b"
  }
}


#Internet_Gateway
resource "aws_internet_gateway" "myigw" {
  vpc_id = aws_vpc.myvpc.id
  depends_on = [
    aws_vpc.myvpc,
  ]

  tags = {
    Name = "myigw"
  }
}

#Route_Table
resource "aws_route_table" "rt-1a" {
  vpc_id = aws_vpc.myvpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.myigw.id
  }
  
  depends_on = [
    aws_vpc.myvpc,
  ]

  tags = {
    Name = "rt-1a"
  }
}

#Subnet_Association
resource "aws_route_table_association" "assoc-1a" {
  subnet_id      = aws_subnet.mysubnet-1a.id
  route_table_id = aws_route_table.rt-1a.id

  depends_on = [
    aws_subnet.mysubnet-1a,
  ]
}

#Wordpress_SG
resource "aws_security_group" "wordpress-sg" {
  name        = "wordpress-sg"
  description = "allows ssh and http"
  vpc_id      = aws_vpc.myvpc.id

  ingress {
    description = "To allow ssh"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "for port 80"
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

  depends_on = [
    aws_vpc.myvpc,
  ]

  tags = {
    Name = "wordpress-sg"
  }
}



#SQL_SG
resource "aws_security_group" "sql-sg" {
  name        = "sql-sg"
  description = "allows wordpress SG"
  vpc_id      = aws_vpc.myvpc.id

  ingress {
    description = "connection to sql"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    security_groups = [aws_security_group.wordpress-sg.id]
  }


  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }  

  depends_on = [
    aws_vpc.myvpc,
    aws_security_group.wordpress-sg,
  ]

  tags = {
    Name = "sql-sg"
  }
}


#Wordpress_Instance

resource "aws_instance" "wordpress" {
  ami = "ami-000cbce3e1b899ebd"
  instance_type = "t2.micro"
  subnet_id = aws_subnet.mysubnet-1a.id
  key_name = "mykey1"
  vpc_security_group_ids = [aws_security_group.wordpress-sg.id]

  depends_on = [
    aws_subnet.mysubnet-1a,
    aws_security_group.wordpress-sg,
  ]

  tags = {
    Name = "wordpress"
  }
}


#SQL_Instance

resource "aws_instance" "sql" {
  ami = "ami-08706cb5f68222d09"
  instance_type = "t2.micro"
  subnet_id = aws_subnet.mysubnet-1b.id
  key_name = "mykey1"
  vpc_security_group_ids = [aws_security_group.sql-sg.id]

  depends_on = [
    aws_subnet.mysubnet-1b,
    aws_security_group.sql-sg,
  ]

  tags = {
    Name = "sql"
  }
}

resource "null_resource" "wordpress_setup" {
    depends_on = [ aws_instance.wordpress_instance, aws_instance.mysql_instance ]

	connection {
		type = "ssh"
		user = "ec2-user"
		private_key =  file("path/to/private/key/in/your/pc")
		host = aws_instance.wordpress_instance.public_ip
	}

	provisioner "remote-exec" {
		inline = [
            "sudo dnf -y install git",
            "git clone https://github.com/mayank-aly/cloud-task-1.git",
			"sudo tee -a /etc/yum.repos.d/docker.repo <<EOF",
            "[docker]",
            "baseurl=https://download.docker.com/linux/centos/7/x86_64/stable",
            "gpgcheck=0",
            "EOF",
            "sudo dnf -y install docker-ce --nobest",
            "sudo systemctl start docker",
            "sudo systemctl enable docker",
            "sudo docker pull wordpress:5.1.1-php7.3-apache",
            "sudo docker run -dit -p 80:80 --name webserver wordpress:5.1.1-php7.3-apache",
			"tee -a /home/ec2-user/script.sh <<EOF",
			"sudo tee -a /etc/yum.repos.d/docker.repo <<EOH",
			"[docker]",
            "baseurl=https://download.docker.com/linux/centos/7/x86_64/stable",
            "gpgcheck=0",
            "EOH",
            "sudo dnf -y install docker-ce --nobest",
            "sudo systemctl start docker",
            "sudo systemctl enable docker",
            "sudo docker pull mysql:5.7",
            "sudo docker run -dit -e MYSQL_ROOT_PASSWORD=redhat -e MYSQL_USER=mayank -e MYSQL_PASSWORD=redhat -e MYSQL_DATABASE=myWordpressDB -p 3306:3306 --name database mysql:5.7",
            "EOF",
            "sudo chmod 400 multicloud/mykey1.pem",
            "sudo chmod +x script.sh",
            "ssh  -o StrictHostKeyChecking=no  ec2-user@${aws_instance.mysql_instance.private_ip} -i multicloud/mykey1.pem 'bash -s' < ./script.sh"
		]
	}
}

resource "null_resource" "wordress_access" {
    depends_on = [ null_resource.wordpress_setup ]
	
	provisioner "local-exec" {
		command = "msedge ${aws_instance.wordpress_instance.public_ip}"
	}
}

output "sql_host_addr" {
    depends_on = [ null_resource.wordress_access ]
    value = "Use this IP as the MYSQL HOST  ---------> ${aws_instance.mysql_instance.private_ip} <---------"
}
