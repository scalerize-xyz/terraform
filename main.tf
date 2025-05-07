provider "aws" {
  region = "us-east-1"
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
}

resource "tls_private_key" "ssh" {
  algorithm = "RSA"
}

resource "aws_key_pair" "ssh_key" {
  key_name = "scalerize"
  public_key = tls_private_key.ssh.public_key_openssh
}

resource "aws_security_group" "allow_required_ports" {
  name = "allow-required-ports"
  description = "Allow required ports"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = 26656
    to_port = 26657
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8545
    to_port     = 8545
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 30303
    to_port     = 30303
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # Allow all protocols
    cidr_blocks = var.elastic_ip_allocation_ids_cidr # Dynamically generated CIDR blocks for Elastic IPs
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "vm_instance" {
  count         = var.no_of_nodes
  ami           = "ami-0b0ea68c435eb488d" # Replace with your desired AMI ID
  instance_type = "t2.medium"
  key_name      = aws_key_pair.ssh_key.key_name
  security_groups = [aws_security_group.allow_required_ports.name]

  # user_data = <<-EOF
  #   #!/bin/bash
  #   # Create user 'nikhil'
  #   useradd -m -s /bin/bash nikhil
  #   # Allow passwordless sudo
  #   echo 'nikhil ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers.d/nikhil
  #   # Set up SSH key
  #   mkdir -p /home/nikhil/.ssh
  #   echo "${tls_private_key.ssh.public_key_openssh}" > /home/nikhil/.ssh/authorized_keys
  #   chown -R nikhil:nikhil /home/nikhil/.ssh
  #   chmod 700 /home/nikhil/.ssh
  #   chmod 600 /home/nikhil/.ssh/authorized_keys
  # EOF

  user_data = <<-EOF
    #!/bin/bash
    useradd -m -s /bin/bash ${var.user}
    echo '${var.user} ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers.d/${var.user}
    mkdir -p /home/${var.user}/.ssh
    echo "${tls_private_key.ssh.public_key_openssh}" > /home/${var.user}/.ssh/authorized_keys
    chown -R ${var.user}:${var.user} /home/${var.user}/.ssh
    chmod 700 /home/${var.user}/.ssh
    chmod 600 /home/${var.user}/.ssh/authorized_keys
  EOF

  tags = {
    Name = format("my-vm-%03d", count.index + 1)
  }
}

resource "aws_eip_association" "eip_association" {
  for_each = zipmap(tolist(range(length(aws_instance.vm_instance))), aws_instance.vm_instance)

  instance_id   = aws_instance.vm_instance[each.key].id
  allocation_id = var.elastic_ip_allocation_ids[tonumber(each.key)]
}

resource "local_file" "local_ssh_key" {
  content  = tls_private_key.ssh.private_key_pem
  filename = "${path.root}/ssh-keys/ssh_key"
}

resource "local_file" "local_ssh_key_pub" {
  content  = tls_private_key.ssh.public_key_openssh
  filename = "${path.root}/ssh-keys/ssh_key.pub"
}

output "instance_ssh_key" {
  value      = "${abspath(path.root)}/ssh_key"
  depends_on = [tls_private_key.ssh]
}

output "ips" {
  value = aws_instance.vm_instance[*].public_ip
}

resource "null_resource" "setup" {
  for_each = { for idx, _ in aws_instance.vm_instance : idx => aws_eip_association.eip_association[tostring(idx)].public_ip }
  provisioner "file" {
    source      = "${abspath(path.root)}/scalerize_setup"
    destination = "/home/${var.user}/scalerize_setup"
  }

  provisioner "file" {
    source      = "${abspath(path.root)}/reth_setup"
    destination = "/home/${var.user}/reth_setup"
  }

  provisioner "remote-exec" {
    # inline = [
    #   "sudo apt-get update",
    #   "sudo systemctl enable --now docker",
    #   "curl -fsSL https://get.docker.com | sudo sh",
    #   "sudo apt-get install -y tmux",
    #   # "sudo systemctl start docker",
    #   "sudo usermod -aG docker nikhil",
    # ]

    inline = [
      "sudo apt-get update",
      "sudo apt-get install -y docker.io tmux",
      "sudo systemctl start docker",
      "sudo usermod -aG docker ${var.user}",
    ]
  }

  connection {
    type        = "ssh"
    user        = var.user
    private_key = tls_private_key.ssh.private_key_pem
    host        = each.value
  }

  depends_on = [aws_instance.vm_instance, tls_private_key.ssh]
}

resource "null_resource" "scalerize" {
  for_each = { for idx, _ in aws_instance.vm_instance : idx => aws_eip_association.eip_association[tostring(idx)].public_ip }

  provisioner "remote-exec" {
    inline = [
      "chmod +x ~/scalerize_setup",
      "chmod 777 /tmp",
      "ID=${each.key} ENGINE_API=http://reth_node_${each.key}:8551 RPC_API=http://reth_node_${each.key}:8545 ~/scalerize_setup",
    ]
  }

  connection {
    type        = "ssh"
    user        = var.user
    private_key = tls_private_key.ssh.private_key_pem
    host        = each.value
  }

  depends_on = [null_resource.setup]
}

resource "null_resource" "reth" {
  for_each = { for idx, _ in aws_instance.vm_instance : idx => aws_eip_association.eip_association[tostring(idx)].public_ip }

  provisioner "remote-exec" {
    inline = [
      "chmod +x ~/reth_setup",
      "ID=${each.key} BOOTNODE_IP=${aws_eip_association.eip_association[abs(0)].public_ip} BOOTNODE_RPC_PORT=8545 ~/reth_setup",
    ]
  }

  connection {
    type        = "ssh"
    user        = var.user
    private_key = tls_private_key.ssh.private_key_pem
    host        = each.value
  }

  depends_on = [null_resource.setup, null_resource.scalerize]
}
