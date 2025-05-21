provider "aws" {
  region     = "us-east-1"
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
}

resource "tls_private_key" "ssh" {
  algorithm = "RSA"
}

resource "aws_key_pair" "blockscout_key" {
  key_name   = "blockscout-key"
  public_key = tls_private_key.ssh.public_key_openssh
}

resource "aws_security_group" "blockscout_sg" {
  name        = "blockscout-sg"
  description = "Allow SSH, HTTP, and Blockscout ports"

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

  ingress {
    from_port   = 4000
    to_port     = 4000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 3000
    to_port     = 3000
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

resource "aws_instance" "blockscout_vm" {
  ami                    = "ami-0718b4ac01274c8cb"
  instance_type          = "t2.medium"
  key_name               = aws_key_pair.blockscout_key.key_name
  vpc_security_group_ids = [aws_security_group.blockscout_sg.id]

  user_data = <<-EOF
    #!/bin/bash
    exec > >(tee -a /var/log/user_data.log) 2>&1
    set -e

    # Create user and SSH access
    useradd -m -s /bin/bash ${var.user}
    echo '${var.user} ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/${var.user}
    chmod 440 /etc/sudoers.d/${var.user}

    mkdir -p /home/${var.user}/.ssh
    echo "${tls_private_key.ssh.public_key_openssh}" > /home/${var.user}/.ssh/authorized_keys
    chown -R ${var.user}:${var.user} /home/${var.user}/.ssh
    chmod 700 /home/${var.user}/.ssh
    chmod 600 /home/${var.user}/.ssh/authorized_keys

    # Signal SSH ready
    touch /tmp/ssh_ready
  EOF

  tags = {
    Name = "blockscout-vm"
  }
}

# ---- Setup null_resource ----
resource "null_resource" "setup" {
  depends_on = [aws_instance.blockscout_vm]  # fixed dependency :contentReference[oaicite:4]{index=4}

  # Connection block at resource level
  connection {
    type        = "ssh"
    host        = aws_instance.blockscout_vm.public_ip  # refer to the instance’s public IP :contentReference[oaicite:5]{index=5}
    user        = var.user
    private_key = tls_private_key.ssh.private_key_pem
  }

  provisioner "file" {
    source      = "${abspath(path.root)}/faucet"
    destination = "/home/${var.user}/faucet"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo apt-get update",
      "sudo apt-get install -y docker.io tmux",
      "sudo systemctl start docker",
      "sudo usermod -aG docker ${var.user}",
    ]
  }
}

# ---- Faucet null_resource ----
resource "null_resource" "faucet" {
  depends_on = [aws_instance.blockscout_vm]  # fixed dependency :contentReference[oaicite:6]{index=6}

  connection {
    type        = "ssh"
    host        = aws_instance.blockscout_vm.public_ip  # refer to the instance’s public IP :contentReference[oaicite:7]{index=7}
    user        = var.user
    private_key = tls_private_key.ssh.private_key_pem
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x ~/faucet",
      "RPC_URL=${var.rpc_url} PRIVATE_KEY=${var.private_key} FAUCET_AMOUNT=${var.faucet_amount} ~/faucet",  # corrected var interpolation :contentReference[oaicite:8]{index=8}
    ]
  }
}

resource "local_file" "local_ssh_key" {
  content  = tls_private_key.ssh.private_key_pem
  filename = "${path.root}/ssh-keys/ssh_key"
}

resource "local_file" "local_ssh_key_pub" {
  content  = tls_private_key.ssh.public_key_openssh
  filename = "${path.root}/ssh-keys/ssh_key.pub"
}

output "blockscout_ip" {
  value = aws_instance.blockscout_vm.public_ip
}
