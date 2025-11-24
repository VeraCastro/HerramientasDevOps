variable "aws_access_key" {
  type      = string
  sensitive = true
}

variable "aws_secret_key" {
  type      = string
  sensitive = true
}

packer {
  required_plugins {
    amazon = {
      version = ">= 1.2.8"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

source "amazon-ebs" "ubuntu" {
  ami_name      = "Practica3-{{timestamp}}"
  source_ami    = "ami-0ecb62995f68bb549"
  region        = "us-east-1"
  instance_type = "t2.micro" 
  ssh_username  = "ubuntu"
  # Credenciales conectadas a las variables
  access_key    = var.aws_access_key
  secret_key    = var.aws_secret_key
  # Firewall
  security_group_ids = ["sg-02c63ae0105ebb36a"]
}

build {
  # Le decimos que use la fuente que definimos antes
  sources = ["source.amazon-ebs.ubuntu"]

  provisioner "shell" {
    script = "./install.sh"
  }
  post-processor "manifest" {
    output     = "manifest.json"
    strip_path = true
  }
}
