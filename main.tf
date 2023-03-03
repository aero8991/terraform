terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "4.45.0"
    }
  }
}

provider "aws" {
  region = "us-west-2"

}

# resource "aws_instance" "my-first-server" {
#     ami = "ami-0ecc74eca1d66d8a6"
#     instance_type = "t2.micro"

#     tags = {
#       Name = "MyFirstTerraInstance"
#     }
# }

resource "aws_vpc" "prod-vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "production"
  }
}


# we dont want the resource itself we want the ID of it
resource "aws_internet_gateway" "gw" {

  vpc_id = aws_vpc.prod-vpc.id

}

#route table (custom) make it so the traffic can get out to the internet
#not egress gateway id, just regualr gateway for ipv6
resource "aws_route_table" "prod-route-table" {
  vpc_id = aws_vpc.prod-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  route {
    ipv6_cidr_block = "::/0"
    gateway_id      = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "Prod"
  }
}

#create a subnet
#subnet
resource "aws_subnet" "subnet-1" {
  vpc_id            = aws_vpc.prod-vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-west-2a"


  tags = {
    Name = "prod-subnet"
  }
}

#route table association. We need to connect the subnet to the route table

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.subnet-1.id
  route_table_id = aws_route_table.prod-route-table.id
}

#create a security group 

resource "aws_security_group" "allow_web" {
  name        = "allow_web_traffic"
  description = "Allow web traffic"
  vpc_id      = aws_vpc.prod-vpc.id

  ingress {
    description = "Https"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]

  }

  ingress {
    description = "Http"
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

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "allow_web"
  }
}

#network interface with an ip in the subnet that was created in step 4
#pick an ip to reserve
#This assigns a private ip ****************************

resource "aws_network_interface" "web-server-nic" {
  subnet_id       = aws_subnet.subnet-1.id
  private_ips     = ["10.0.1.50"]
  security_groups = [aws_security_group.allow_web.id]


}

#elsatic ip assigned to a network interface 
#needs a dependancy on internet gateway and we need to reference the entire resource not just ID ! 
#Depends_on must be passed via a list :) 
resource "aws_eip" "one" {
  vpc                       = true
  network_interface         = aws_network_interface.web-server-nic.id
  associate_with_private_ip = "10.0.1.50"
  depends_on = [
    aws_internet_gateway.gw
  ]
}

#print out handy details
output "server_public_ip" {
  value = aws_eip.one.public_ip

}
#must generate a private key first! 
# resource "aws_key_pair" "TF_Key" {
#     key_name = "TF_Key"
#     public_key = tls_private_key.rsa_key.public_key_openssh

# }

# resource "tls_private_key" "rsa_key" {
#     algorithm = "RSA"
#     rsa_bits = 4096

# }

# # #store the pem file on my machine
# resource "local_file" "TF-key" {
#     content = tls_private_key.rsa_key.private_key_pem
#     filename = "tfkey.ppk"

# }


#instance
#did not set in an availability zone 
#tell it what interface to use, in this case the first number
#then reference the network interface id or NIC 
resource "aws_instance" "web_server_instance" {

  ami               = "ami-0ecc74eca1d66d8a6"
  instance_type     = "t2.micro"
  key_name          = "use-this-key-ubuntu-terraform"
  availability_zone = "us-west-2a"

  network_interface {
    device_index         = 0
    network_interface_id = aws_network_interface.web-server-nic.id
  }
  ##attach a file that has the script
  user_data = file("ec2script.sh")
  tags = {
    Name = "web-server"
  }

}



resource "aws_iam_role" "lambda-role" {
  name               = "terraform_aws_lambda_role"
  assume_role_policy = <<EOF
    {
        "Version": "2012-10-17",
        "Statement" : [
            {
                 "Action" : "sts:AssumeRole",
                 "Principal": {
                    "Service" : "lambda.amazonaws.com"
            },
            "Effect": "Allow",
            "Sid": ""
            }
        ]
    }
  EOF
}


resource "aws_iam_policy" "iam-policy-for-lambda" {

  name        = "aws_iam_terraform_aws_lambda_role"
  path        = "/"
  description = "AWS IAM Policy for managing aws lambda role"
  policy      = data.aws_iam_policy_document.s3-lambda.json
  
#   <<EOF
# {
#     "Version": "2012-10-17",
#     "Statement": [
#         {
#             "Action": [
#                 "logs:CreateLogGroup",
#                 "logs:CreateLogStream",
#                 "logs:PutLogEvents",
#                 "s3:*"
#             ],
#             "Resource":"arn:aws:logs:*:*:*",
#             "Effect":"Allow"
#         },
#          {
#          "Effect":"Allow",
#          "Action":[
#             "s3:PutObject",
#             "s3:GetObject",
#             "s3:GetObjectVersion",
#             "s3:DeleteObject",
#             "s3:DeleteObjectVersion"
#          ],
#          "Resource":"${aws_s3_bucket.aws_bucket-1.arn}"
#       }
#     ]
# }    
# EOF
}

data "aws_iam_policy_document" "s3-lambda" {
    statement {
        effect = "Allow"
        actions  = ["logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
        ]
        resources =  [
            "arn:aws:logs:*:*:*"
        ]

    }
    statement {
        effect = "Allow"
        actions = [
            "s3:ListBucket"
        ]
        resources = [
            aws_s3_bucket.aws_bucket-1.arn
        ]
    }
    statement {
        effect = "Allow"
        actions = [
            "s3:PutObject",
            "s3:GetObject",
            "s3:DeleteObject"
        ]
        resources = [
            "${aws_s3_bucket.aws_bucket-1.arn}/*"
        ]

    }
}


data aws_iam_policy_document lambda_s3 {
  statement {
    actions = [
      "s3:PutObject",
      "s3:PutObjectAcl"
    ]

    resources = [
      "${aws_s3_bucket.aws_bucket-1.arn}*"
    ]
  }
}

resource "aws_iam_role_policy_attachment" "attach-iam-policy-to-role" {
  role       = aws_iam_role.lambda-role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSLambdaExecute"
  #aws_iam_policy.iam-policy-for-lambda.arn

}

data "archive_file" "zip-python-code" {
  type        = "zip"
  source_dir  = "${path.module}/python/"
  output_path = "${path.module}/python/glue-job.zip"

}

resource "aws_lambda_function" "terraform-lambda-func" {
  filename      = "${path.module}/python/glue-job.zip"
  function_name = "trigger_glue_job"
  role          = aws_iam_role.lambda-role.arn
  handler       = "glue-job.lambda_handler"
  runtime       = "python3.9"
  depends_on = [
    aws_iam_role_policy_attachment.attach-iam-policy-to-role

  ]

}

resource "aws_lambda_permission" "allow-bucket" {
    statement_id = "AllowExecutionFromS3Bucket"
    action = "lambda:InvokeFunction"
    function_name = aws_lambda_function.terraform-lambda-func.arn
    principal = "s3.amazonaws.com"
    source_arn = aws_s3_bucket.aws_bucket-1.arn

}
resource "aws_s3_bucket_notification" "bucket-notification" {
    bucket = aws_s3_bucket.aws_bucket-1.id

    lambda_function {
        lambda_function_arn = aws_lambda_function.terraform-lambda-func.arn
        events              = ["s3:ObjectCreated:*"]
        filter_prefix       = "sftp/"
    }

  depends_on = [ aws_lambda_permission.allow-bucket

  ]
}


#=========================================================

variable "glue-arn"{
    default = "arn:aws:iam::276289019514:role/AWSGlue"
}

variable "job-name" {
    default = "medispan-crawl-terraform"
}

variable "bucket-name" {
    default = "medispan-poc-terraform"
}   

variable "file-name" {
    default = "etl-with-glue-trigger.py"
}
#==========================================================

resource "aws_s3_bucket" "aws_bucket-1" {
  bucket = "medispan-poc-genoa"

  tags = {
    Name = "medispan-poc-genoa"

  }
}


resource "aws_s3_bucket" "aws_bucket-2" {
  bucket = "${var.bucket-name}"

  tags = {
    Name = "${var.bucket-name}"

  }
}

resource "aws_s3_bucket_object" "sftp" {
  bucket = aws_s3_bucket.aws_bucket-1.id
  key    = "sftp/"

}

resource "aws_s3_bucket_object" "athena" {
  bucket = aws_s3_bucket.aws_bucket-1.id
  key    = "athena/"

}

resource "aws_s3_bucket_object" "output" {
  bucket = aws_s3_bucket.aws_bucket-1.id
  key    = "output/"

}

resource "aws_s3_bucket_object" "glue" {
  bucket = aws_s3_bucket.aws_bucket-1.id
  key    = "glue/"

}


resource "aws_s3_bucket_object" "upload-glue-script" {
    bucket = "${var.bucket-name}"
    key = "glue/${var.file-name}"
    source = "${var.file-name}"
  
}

resource "aws_glue_job" "glue-job" {
    name = "${var.job-name}"
    role_arn = "${var.glue-arn}"
    description = "ETL with glue trigger"
    max_retries = "1"
    timeout = 2880
    max_capacity = 1
    

    command {
        name = "pythonshell"
        script_location = "s3://${var.bucket-name}/glue/${var.file-name}"
        python_version = "3.9"
        
      
    }
    execution_property {
        max_concurrent_runs = 1
    }
    default_arguments  = {
        library-set = "analytics"
        "--enable-continuous-cloudwatch-log" = "true"
        "--enable-continuous-log-filter"     = "true"
        
    }
    glue_version = "3.0"
    
}
