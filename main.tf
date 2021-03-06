
#login

provider "aws" {
  region = "us-east-1"
  profile = "cloud_user"

}


#key_pair

resource "tls_private_key" "aws-terraform-keypair1" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "private_key" {
  content  = tls_private_key.aws-terraform-keypair1.private_key_pem
  filename = "aws-terraform-keypair1.pem"
}

resource "aws_key_pair" "aws-terraform-keypair1" {
  key_name   = "aws-terraform-keypair1"
  public_key = "${tls_private_key.aws-terraform-keypair1.public_key_openssh}"
}


#security_group
resource "aws_security_group" "allow_http_ssh_nfs" {
  name        = "allow_http_ssh_nfs"
  description = "Allow HTTP inbound traffic"
  vpc_id      = "vpc-0d9b517095ac1ff04"


  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
 ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
     description = "NFS"
     from_port   = 2049
     to_port     = 2049
     protocol    = "tcp"
     cidr_blocks = ["0.0.0.0/0"]
   }
   egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
tags = {
    Name = "allow_http_ssh_nfs"
  }
}

#sg_for_efs

resource "aws_security_group" "efs_sg" {
  name        = "efs_sg"
  description = "efs security group"
  vpc_id      = "vpc-0d9b517095ac1ff04"

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
   egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
tags = {
    Name = "efs_sg"
  }
}

#instance_launch

resource "aws_instance" "aws_terraform_os" {
ami= "ami-0b0af3577fe5e3532"
instance_type = "t2.micro"
key_name       =  "aws_key_pair.aws-terraform-keypair1.key_name"
vpc_security_group_ids = ["${aws_security_group.allow_http_ssh_nfs.id}" ]

connection {
type     = "ssh"
user     = "ec2-user"
private_key = tls_private_key.aws-terraform-keypair1.private_key_pem
host     = aws_instance.aws_terraform_os.public_ip
}

provisioner "remote-exec" {
inline = [
"sudo yum update -y",
"sudo yum install httpd  php git -y ",
"sudo systemctl restart httpd",
"sudo systemctl enable httpd",
]
}
tags = {
Name =  "aws_terraform_os"
}
}

#create_efs

resource "aws_efs_file_system" "efs" {
  depends_on = [
  aws_security_group.efs_sg
  ]
  creation_token = "efs"
  encrypted = "true"

  tags = {
    Name = "efs"
  }
}


#mount_target_efs

resource "aws_efs_mount_target" "mount_efs" {
  depends_on = [aws_efs_file_system.efs]
  file_system_id = aws_efs_file_system.efs.id
  subnet_id      =   aws_instance.aws_terraform_os.subnet_id
  security_groups = [ "efs_sg" ]
}

 resource "null_resource" "mounting" {

 depends_on = [aws_efs_mount_target.mount_efs]

 connection {
   type = "ssh"
   user = "ec2-user"
   private_key = tls_private_key.aws-terraform-keypair1.private_key_pem
   host = aws_instance.aws_terraform_os.public_ip
   }

 provisioner "remote-exec" {
    inline = [
      "sudo mount aws_efs_file_system.efs.id:/  /var/www/html",
      "sudo echo aws_efs_file_system.efs.id:/ /var/www/html efs defaults,_netdev 0 0' >> /etc/fstab",
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/aditya-xclusive/terraform-aws-efs-integration.git   /var/www/html/"
      ]
  }
 }

 #s3_bucket_creation

 resource "aws_s3_bucket" "terraformtaskbucket" {
   bucket = "terraformtaskbucket"
   acl    = "public-read"
   force_destroy = true

   tags = {
     Name        = "terraformtaskbucket"
   }
 }

 resource "aws_s3_bucket_object" "s3image" {
   depends_on = [
     aws_s3_bucket.terraformtaskbucket
   ]

   bucket = "terraformtaskbucket"
   key    = "taskimage.jpg"
   source = "C:/Btech pdf/Cloud Computing/CloudProj/taskimage.jpg"
   acl    = "public-read"
 }

 #cloudfront_creation

resource "aws_cloudfront_distribution" "s3distribution"  {
  depends_on = [
    aws_s3_bucket_object.s3image
  ]
  origin {
    domain_name = "${aws_s3_bucket.terraformtaskbucket.bucket_regional_domain_name}"
    origin_id   = "${aws_s3_bucket.terraformtaskbucket.id}"
 }
 enabled             = true
 is_ipv6_enabled     = true

 default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "${aws_s3_bucket.terraformtaskbucket.id}"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400

  }
    restrictions {
       geo_restriction {
         restriction_type = "none"
       }
    }
    viewer_certificate {
        cloudfront_default_certificate = true
      }
}


 resource "null_resource" "localexec"  {
    depends_on = [
        aws_cloudfront_distribution.s3distribution,
    ]
	provisioner "local-exec" {
	    command = "start chrome  ${aws_instance.aws_terraform_os.public_ip}"
  	}

}
