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

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Generate local install.sh file
resource "local_file" "install_sh" {
  content  = <<-SCRIPT
#!/bin/bash
exec > >(tee -a ~/install.log) 2>&1
set -e

# System updates and base tools
sudo apt-get update -y
sudo apt-get install -y curl gnupg

# Node.js and Yarn
curl -fsSL https://deb.nodesource.com/setup_16.x | sudo -E bash -
sudo apt-get install -y nodejs
curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | sudo apt-key add -
echo "deb https://dl.yarnpkg.com/debian/ stable main" | sudo tee /etc/apt/sources.list.d/yarn.list
sudo apt-get update -y
sudo apt-get install -y yarn

# System updates and base tools
sudo apt-get update -y
sudo apt-get install -y inotify-tools make g++ libudev-dev zip unzip build-essential cmake git automake libtool libgmp-dev libgmp10 jq

sudo apt-get install -y \
  ca-certificates curl gnupg lsb-release
sudo mkdir -m 0755 -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor \
  -o /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update -y
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo usermod -aG docker ${var.user}

# Install ASDF and plugins
git clone https://github.com/asdf-vm/asdf.git ~/.asdf
echo '. ~/.asdf/asdf.sh' >> ~/.profile
source ~/.profile
echo '. $HOME/.asdf/asdf.sh' >> ~/.bashrc
asdf plugin add erlang
asdf plugin add elixir
asdf plugin add nodejs

asdf install nodejs 22.11.0
asdf global nodejs 22.11.0

# PostgreSQL setup
curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg
echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" | sudo tee /etc/apt/sources.list.d/pgdg.list
sudo apt-get update -y
sudo apt-get install -y postgresql-14
sudo apt-get update -y
sudo -u postgres psql -c "CREATE USER ${var.user} WITH SUPERUSER PASSWORD '${var.database_password}';"
sudo -u postgres createdb blockscout
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE blockscout TO ${var.user};"
sudo sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" /etc/postgresql/14/main/postgresql.conf
echo 'host all all all md5' | sudo tee -a /etc/postgresql/14/main/pg_hba.conf
sudo systemctl restart postgresql

# Additional dependencies
sudo apt-get install -y autoconf m4 libncurses5-dev libwxgtk3.0-gtk3-dev libgl1-mesa-dev libglu1-mesa-dev libpng-dev libssh-dev unixodbc-dev xsltproc fop libxml2-utils libncurses-dev openjdk-11-jdk

# Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> ~/.bashrc

# Blockscout clone and build
git clone https://github.com/blockscout/blockscout ~/blockscout-backend
cd ~/blockscout-backend && source ~/.profile && asdf install
cd ~/blockscout-backend && mix local.hex --force && mix local.rebar --force && mix deps.get && mix deps.compile

# Secrets & env
export SECRET_KEY_BASE=$(mix phx.gen.secret)
export DATABASE_URL="postgresql://${var.user}:${var.database_password}@localhost:5432/blockscout"
export ETHEREUM_JSONRPC_HTTP_URL="${var.ethereum_rpc_url}"

# Optionally append to .bashrc for future sessions
echo "export SECRET_KEY_BASE=$SECRET_KEY_BASE" >> ~/.bashrc
echo "export DATABASE_URL='$DATABASE_URL'" >> ~/.bashrc
echo "export ETHEREUM_JSONRPC_HTTP_URL='$ETHEREUM_JSONRPC_HTTP_URL'" >> ~/.bashrc

# Assets & compile
mix phx.digest
mix compile

# Migrate & start
mix ecto.create
mix ecto.migrate

cd ~/blockscout-backend/apps/block_scout_web/assets && npm install && node_modules/webpack/bin/webpack.js --mode production
cd ~/blockscout-backend/apps/explorer && npm install
cd ~/blockscout-backend/apps/block_scout_web; mix phx.gen.cert blockscout blockscout.local

# Blockscout frontend setup
git clone https://github.com/blockscout/frontend ~/blockscout-frontend
cd ~/blockscout-frontend
cat > .env << 'EOF'
NEXT_PUBLIC_API_HOST=localhost
NEXT_PUBLIC_API_PORT=3001
NEXT_PUBLIC_API_PROTOCOL=http
NEXT_PUBLIC_STATS_API_HOST=http://localhost:8080
NEXT_PUBLIC_VISUALIZE_API_HOST=http://localhost:8081
NEXT_PUBLIC_APP_HOST=localhost
NEXT_PUBLIC_APP_PORT=3000
NEXT_PUBLIC_APP_INSTANCE=localhost
NEXT_PUBLIC_APP_ENV=development
NEXT_PUBLIC_API_WEBSOCKET_PROTOCOL=ws
NEXT_PUBLIC_WALLET_CONNECT_PROJECT_ID=1234
EOF
yarn install

# tmux new-session -d -s blockscout_backend 'cd ~/blockscout-backend; mix phx.server > ~/blockscout-backend.log 2>&1'
# tmux new-session -d -s blockscout_frontend 'cd ~/blockscout-frontend && yarn dev > ~/blockscout-frontend.log 2>&1'

tmux new-session -d -s blockscout_backend "while true; do cd ~/blockscout-backend && mix phx.server >> ~/blockscout-backend.log 2>&1 || sleep 5; done"
tmux new-session -d -s blockscout_frontend "while true; do cd ~/blockscout-frontend && yarn dev >> ~/blockscout-frontend.log 2>&1 || sleep 5; done"
SCRIPT
  filename = "${path.module}/install.sh"
}

resource "aws_instance" "blockscout_vm" {
  ami                    = "ami-0718b4ac01274c8cb" # Ubuntu 22.04 LTS
  # instance_type          = "t2.medium"
  instance_type          = "c5.xlarge"
  key_name               = aws_key_pair.blockscout_key.key_name
  vpc_security_group_ids = [aws_security_group.blockscout_sg.id]

  # SSH setup in user_data
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

  connection {
    type        = "ssh"
    host        = self.public_ip
    user        = var.user
    private_key = tls_private_key.ssh.private_key_pem
    timeout     = "10m"
  }

  provisioner "file" {
    source      = local_file.install_sh.filename
    destination = "/home/${var.user}/install.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "while [ ! -f /tmp/ssh_ready ]; do sleep 5; done",
      "chmod +x /home/${var.user}/install.sh",
      "bash /home/${var.user}/install.sh"
    ]
  }

  root_block_device {
    volume_size = 120
    volume_type = "gp3"
  }

  tags = {
    Name = "blockscout-vm"
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
