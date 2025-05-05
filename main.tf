provider "google" {
  credentials = file(var.credential_path)
  project     = "scalerize"
  region      = "us-central1"
}

resource "tls_private_key" "ssh" {
  algorithm = "RSA"
}

resource "google_compute_instance" "vm_instance" {
  count        = var.no_of_nodes # Number of VM instances to create
  name         = format("my-vm-%03d", count.index + 1)
  machine_type = "e2-medium"
  zone         = "us-central1-a"

  tags = ["allow-required-ports"]

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2004-lts"
    }
  }

  network_interface {
    network = "default"
    access_config {
      nat_ip = var.external_ips[count.index]
    }
  }

  metadata = {
    sshKeys = "${var.user}:${tls_private_key.ssh.public_key_openssh}"
  }
}

resource "google_compute_firewall" "allow_required_ports" {
  name    = "allow-required-ports"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["26656","26657","8545","30303"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["allow-required-ports"]
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
  value = google_compute_instance.vm_instance[*].network_interface[0].access_config[0].nat_ip
}

resource "null_resource" "setup" {
  for_each = { for idx, ip in google_compute_instance.vm_instance[*].network_interface[0].access_config[0].nat_ip : idx => ip }

  provisioner "file" {
    source      = "${abspath(path.root)}/scalerize_setup"
    destination = "/home/${var.user}/scalerize_setup"
  }

  provisioner "file" {
    source      = "${abspath(path.root)}/reth_setup"
    destination = "/home/${var.user}/reth_setup"
  }

  provisioner "remote-exec" {
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

  depends_on = [google_compute_instance.vm_instance, tls_private_key.ssh]
}

resource "null_resource" "scalerize" {
  for_each = { for idx, ip in google_compute_instance.vm_instance[*].network_interface[0].access_config[0].nat_ip : idx => ip }

  provisioner "remote-exec" {
    inline = [
      "chmod +x ~/scalerize_setup",
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
  for_each = { for idx, ip in google_compute_instance.vm_instance[*].network_interface[0].access_config[0].nat_ip : idx => ip }

  provisioner "remote-exec" {
    inline = [
      "chmod +x ~/reth_setup",
      "ID=${each.key} BOOTNODE_IP=${google_compute_instance.vm_instance[0].network_interface[0].access_config[0].nat_ip} BOOTNODE_RPC_PORT=8545 ~/reth_setup",
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
