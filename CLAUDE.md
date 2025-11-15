# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a **Terraform-only** infrastructure setup for deploying frps (Fast Reverse Proxy Server) with automatic TLS (via Caddy) on Sakura VPS. The entire deployment is handled by Terraform using provisioners - no Ansible required.

**Key Components:**
- **Terraform** - Single source of truth for VPS configuration and deployment
- **Docker Compose** - Container orchestration (deployed via Terraform)
- **Caddy** - Automatic HTTPS/TLS certificate management (Let's Encrypt)
- **frps** - HTTP reverse proxy with subdomain routing

## Architecture

### Deployment Flow
1. Terraform connects to VPS via SSH
2. Installs Docker, Docker Compose, and UFW
3. Configures firewall (ports 22, 80, 443, 7000, 8080)
4. Renders configuration templates (Caddyfile, frps.toml, docker-compose.yml)
5. Deploys files to `/opt/proxy/` on VPS
6. Starts frps and Caddy containers

### Configuration Flow
```
Terraform Variables (terraform.tfvars)
    ↓
Template Rendering (templates/*.tmpl)
    ↓
File Provisioning to VPS (/opt/proxy/)
    ↓
Docker Compose Up (frps + Caddy)
```

### Directory Structure
```
terraform/
├── main.tf                    # Main provisioning logic
├── variables.tf               # Input variables
├── outputs.tf                 # Deployment outputs
├── terraform.tfvars.example   # Example configuration
├── templates/
│   ├── Caddyfile.tmpl        # Caddy config template
│   ├── frps.toml.tmpl        # frps config template
│   └── docker-compose.yml.tmpl
└── CLAUDE.md                  # This file
```

### VPS Directory Structure (after deployment)
```
/opt/proxy/
├── compose/
│   └── docker-compose.yml
└── config/
    ├── Caddyfile
    └── frps.toml
```

## Common Commands

### Initial Setup

1. **Copy and configure variables:**
```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your actual values
```

Required variables:
- `vps_ip`: VPS IP address
- `ssh_user`: SSH username (ubuntu/debian/root)
- `private_key_path`: Path to SSH private key
- `domain`: Your domain (e.g., proxy.example.com)
- `acme_email`: Email for Let's Encrypt notifications
- `frp_token`: Long random string for authentication

2. **Initialize Terraform:**
```bash
terraform init
```

### Deployment

**Deploy everything:**
```bash
terraform apply
```

**Preview changes:**
```bash
terraform plan
```

**Deploy with auto-approve:**
```bash
terraform apply -auto-approve
```

### Verification

**SSH to VPS and check containers:**
```bash
ssh ubuntu@<VPS_IP>
docker ps  # Should show frps and caddy
docker logs frps
docker logs caddy
```

**Test HTTPS:**
```bash
curl https://proxy.example.com
```

### Updates

When you modify templates or variables, run:
```bash
terraform apply
```

Terraform will detect changes via SHA256 hashes and re-provision as needed.

### Cleanup

**Destroy all resources:**
```bash
terraform destroy
```

Note: This only removes Terraform state. To fully clean VPS:
```bash
ssh ubuntu@<VPS_IP>
cd /opt/proxy/compose
sudo docker compose down -v
sudo rm -rf /opt/proxy
```

## Configuration Details

### templates/Caddyfile.tmpl
- Accepts all traffic to `*.${domain}` and `${domain}`
- Automatically obtains Let's Encrypt certificates
- Proxies to frps internal HTTP port (8080)
- Maintains Host header for subdomain routing

### templates/frps.toml.tmpl
- bindPort: 7000 (client connections with TLS)
- vhostHTTPPort: 8080 (internal HTTP, proxied by Caddy)
- subdomainHost: Uses `${domain}` variable
- auth: Token-based authentication
- webServer: Dashboard on port 7500 (not exposed externally)

### templates/docker-compose.yml.tmpl
- frps container: Ports 7000, 8080
- caddy container: Ports 80, 443
- Persistent volumes: caddy_data, caddy_config

## Client Configuration

Create `frpc.toml` on client machines:

```toml
serverAddr = "proxy.example.com"
serverPort = 7000
protocol   = "wss"

[auth]
method = "token"
token  = "YOUR_FRP_TOKEN"  # Match server token

[[proxies]]
name      = "myservice"
type      = "http"
localPort = 8080
subdomain = "myservice"  # Access via https://myservice.proxy.example.com
```

Run: `frpc -c frpc.toml`

## Prerequisites

### DNS Configuration
Set A records pointing to VPS IP:
```
proxy.example.com    A    <VPS_IP>
*.proxy.example.com  A    <VPS_IP>
```

### Local Requirements
- Terraform >= 1.6.0
- SSH access to VPS
- SSH key configured

### VPS Requirements
- Ubuntu/Debian-based OS
- SSH access as sudo-capable user
- Internet connectivity

## Security Considerations

- **Sensitive Variables**: `frp_token` and `private_key_path` are marked `sensitive = true`
- **Firewall**: UFW is enabled and configured automatically
- **Dashboard**: frps dashboard (port 7500) is not exposed externally
- **Token Strength**: Use long random tokens (32+ characters)
- **Git Safety**: Keep `terraform.tfvars` in .gitignore
- **TLS**: All client connections use WSS (WebSocket Secure)

## Troubleshooting

### Connection Issues
```bash
# Check SSH connectivity
terraform apply  # Will fail fast if SSH issues

# Check VPS firewall
ssh ubuntu@<VPS_IP> "sudo ufw status"
```

### Container Issues
```bash
# SSH to VPS and check logs
ssh ubuntu@<VPS_IP>
docker ps
docker logs frps
docker logs caddy

# Restart containers
cd /opt/proxy/compose
sudo docker compose restart
```

### Certificate Issues
```bash
# Check Caddy logs
ssh ubuntu@<VPS_IP> "docker logs caddy"

# Verify DNS
dig proxy.example.com
dig myservice.proxy.example.com
```

### Re-deploy Configuration
```bash
# Terraform will detect changes via SHA256 hashes
terraform apply
```

## Development Notes

- Uses `null_resource` with `triggers` for change detection
- SHA256 hashing ensures re-provisioning when configs change
- Provisioners run in sequence: remote-exec → file → file → file → remote-exec
- Bastion host support included but optional
- `set -euxo pipefail` ensures script failures are caught
- Docker Compose v2 syntax (`docker compose` not `docker-compose`)

## Future Enhancements

- **DNS Automation**: Add CloudFlare/Sakura DNS provider for automatic DNS records
- **Secrets Management**: Integrate SOPS + age for encrypted secrets in Git
- **Monitoring**: Add Prometheus/Grafana for metrics
- **Backup**: Automated backup of `/opt/proxy/config`
- **Multi-VPS**: Extend to support multiple VPS deployments
- **Cloud-init**: Move provisioning logic to cloud-init for faster deployment

## Related Files

- `../ansible/`: Legacy Ansible configuration (no longer needed)
- `../README.md`: Project documentation
- `.gitignore`: Should include `terraform.tfvars`, `*.tfstate*`, `.terraform/`
