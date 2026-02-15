#!/bin/bash
# ============================================================
# EC2 Setup Script
# Run on a fresh Ubuntu 24.04 EC2 instance (Graviton arm64)
#
# Works for both:
#   - App Server (m8g.xlarge) - runs Go API
#   - Load Generator (m8g.medium) - runs K6 tests
#
# Usage: chmod +x setup_ec2.sh && ./setup_ec2.sh
# ============================================================

set -euo pipefail

echo "============================================================"
echo "Setting up benchmark environment..."
echo "============================================================"

# Detect architecture
ARCH=$(uname -m)
if [ "$ARCH" = "aarch64" ]; then
    GO_ARCH="arm64"
else
    GO_ARCH="amd64"
fi
echo "Detected architecture: $ARCH (Go: $GO_ARCH)"

# Update system
sudo apt-get update -y
sudo apt-get upgrade -y

# ============================================================
# Install Go
# ============================================================
echo "Installing Go..."
GO_VERSION="1.22.5"
wget -q "https://go.dev/dl/go${GO_VERSION}.linux-${GO_ARCH}.tar.gz"
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf "go${GO_VERSION}.linux-${GO_ARCH}.tar.gz"
rm "go${GO_VERSION}.linux-${GO_ARCH}.tar.gz"

echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
echo 'export GOPATH=$HOME/go' >> ~/.bashrc
echo 'export PATH=$PATH:$GOPATH/bin' >> ~/.bashrc
export PATH=$PATH:/usr/local/go/bin
export GOPATH=$HOME/go
export PATH=$PATH:$GOPATH/bin

go version

# ============================================================
# Install K6
# ============================================================
echo "Installing K6..."
if [ "$ARCH" = "aarch64" ]; then
    # arm64: Download binary directly (apt repo is amd64 only)
    K6_VERSION="v0.54.0"
    wget -q "https://github.com/grafana/k6/releases/download/${K6_VERSION}/k6-${K6_VERSION}-linux-arm64.tar.gz"
    tar -xzf "k6-${K6_VERSION}-linux-arm64.tar.gz"
    sudo mv "k6-${K6_VERSION}-linux-arm64/k6" /usr/local/bin/
    rm -rf "k6-${K6_VERSION}-linux-arm64" "k6-${K6_VERSION}-linux-arm64.tar.gz"
else
    # amd64: Use apt repository
    sudo gpg -k
    sudo gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg \
        --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69
    echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" | \
        sudo tee /etc/apt/sources.list.d/k6.list
    sudo apt-get update -y
    sudo apt-get install -y k6
fi

k6 version

# ============================================================
# Install PostgreSQL client (for psql, pgbench)
# ============================================================
echo "Installing PostgreSQL client tools..."
sudo apt-get install -y postgresql-client postgresql-contrib

# ============================================================
# Install PgBouncer
# ============================================================
echo "Installing PgBouncer..."
sudo apt-get install -y pgbouncer

# Stop default pgbouncer service (we'll configure it manually)
sudo systemctl stop pgbouncer
sudo systemctl disable pgbouncer

echo "============================================================"
echo "Creating PgBouncer config template..."
echo "============================================================"

sudo tee /etc/pgbouncer/pgbouncer.ini > /dev/null << 'PGBOUNCER_CONF'
[databases]
# Update with your actual database endpoint
# benchdb = host=YOUR_RDS_ENDPOINT port=5432 dbname=benchdb

[pgbouncer]
listen_addr = 127.0.0.1
listen_port = 6432
auth_type = md5
auth_file = /etc/pgbouncer/userlist.txt

# Connection pooling
pool_mode = transaction
default_pool_size = 100
min_pool_size = 10
max_client_conn = 5000
reserve_pool_size = 5
reserve_pool_timeout = 3

# Timeouts
server_connect_timeout = 3
server_idle_timeout = 600
client_idle_timeout = 0
query_timeout = 0

# Logging
log_connections = 0
log_disconnections = 0
log_pooler_errors = 1
stats_period = 60

# Admin
admin_users = postgres
PGBOUNCER_CONF

echo "============================================================"
echo "PgBouncer config template created at /etc/pgbouncer/pgbouncer.ini"
echo ""
echo "TO CONFIGURE:"
echo "  1. Edit /etc/pgbouncer/pgbouncer.ini"
echo "     - Uncomment and set: benchdb = host=YOUR_RDS_ENDPOINT port=5432 dbname=benchdb"
echo ""
echo "  2. Set auth file:"
echo '     echo "\"postgres\" \"YOUR_PASSWORD\"" | sudo tee /etc/pgbouncer/userlist.txt'
echo ""
echo "  3. Start PgBouncer:"
echo "     sudo systemctl start pgbouncer"
echo "     sudo systemctl enable pgbouncer"
echo ""
echo "  4. Test connection:"
echo "     psql -h 127.0.0.1 -p 6432 -U postgres benchdb"
echo "============================================================"

# ============================================================
# Build Go App
# ============================================================
echo "Building Go benchmark API..."

cd ~/pg-benchmark/app

# Download dependencies
go mod tidy

# Build for current architecture
go build -o benchmark-api .

echo "============================================================"
echo "Go API built: ~/pg-benchmark/app/benchmark-api"
echo ""
echo "TO RUN (on App Server only):"
echo "  # Direct connection (concurrency < 100)"
echo "  DATABASE_URL='postgresql://postgres:PASSWORD@RDS_ENDPOINT:5432/benchdb?sslmode=require' ./benchmark-api"
echo ""
echo "  # Via PgBouncer (concurrency >= 100)"
echo "  DATABASE_URL='postgresql://postgres:PASSWORD@127.0.0.1:6432/benchdb?sslmode=disable' ./benchmark-api"
echo "============================================================"

# ============================================================
# Install htop for monitoring
# ============================================================
sudo apt-get install -y htop sysstat

echo ""
echo "============================================================"
echo "SETUP COMPLETE"
echo "============================================================"
echo ""
echo "Installed:"
echo "  - Go $(go version | awk '{print $3}')"
echo "  - K6 $(k6 version 2>&1 | head -1)"
echo "  - psql $(psql --version | awk '{print $3}')"
echo "  - pgbench $(pgbench --version | awk '{print $3}')"
echo "  - PgBouncer (configured but not started)"
echo "  - htop, sysstat (monitoring)"
echo ""
echo "============================================================"
echo "NEXT STEPS"
echo "============================================================"
echo ""
echo "FOR APP SERVER (m8g.xlarge):"
echo "  1. Configure PgBouncer (see instructions above)"
echo "  2. Run schema + seed:"
echo "     psql -h RDS_ENDPOINT -U postgres -d benchdb -f ../01_schema.sql"
echo "     psql -h RDS_ENDPOINT -U postgres -d benchdb -v scale=10 -f ../02_seed_data.sql"
echo "  3. Start API:"
echo "     DATABASE_URL='postgresql://postgres:PASSWORD@RDS_ENDPOINT:5432/benchdb?sslmode=require' ./benchmark-api"
echo ""
echo "FOR LOAD GENERATOR (m8g.medium):"
echo "  1. Run K6 tests (targeting app server private IP):"
echo "     ./run_k6_suite.sh http://<ec2-app-private-ip>:8080 1m aurora_17.7"
echo "============================================================"
