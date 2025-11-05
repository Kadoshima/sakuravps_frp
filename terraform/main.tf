terraform {
  required_version = ">= 1.6.0"
}

# テンプレートファイルから設定を生成
locals {
  caddyfile = templatefile("${path.module}/templates/Caddyfile.tmpl", {
    domain     = var.domain
    acme_email = var.acme_email
  })
  frps_toml = templatefile("${path.module}/templates/frps.toml.tmpl", {
    domain    = var.domain
    frp_token = var.frp_token
  })
  compose_yml = templatefile("${path.module}/templates/docker-compose.yml.tmpl", {})
}

# VPSへのfrps + Caddy デプロイ
resource "null_resource" "provision" {
  triggers = {
    host       = var.vps_ip
    caddy_hash = sha256(local.caddyfile)
    frps_hash  = sha256(local.frps_toml)
    comp_hash  = sha256(local.compose_yml)
    ports_hash = sha256(join(",", var.open_ports))
  }

  connection {
    type        = "ssh"
    host        = var.vps_ip
    user        = var.ssh_user
    private_key = file(var.private_key_path)
    timeout     = "60s"

    # 踏み台が必要な場合だけ設定
    bastion_host = var.bastion_host != "" ? var.bastion_host : null
    bastion_user = var.bastion_user != "" ? var.bastion_user : null
  }

  # 0) 事前準備とUFW設定
  provisioner "remote-exec" {
    inline = [
      "set -eux",
      "sudo apt-get update -y",
      "sudo apt-get install -y ufw",
      "sudo systemctl enable docker || true",
      "sudo systemctl start docker || true",
      "sudo ufw --force enable || true",
      "for p in ${join(" ", var.open_ports)}; do sudo ufw allow $p/tcp || true; done",
      "sudo mkdir -p /opt/proxy/config /opt/proxy/compose",
      "sudo chown -R ${var.ssh_user}:${var.ssh_user} /opt/proxy",
    ]
  }

  # 1) Caddyfile 配置
  provisioner "file" {
    content     = local.caddyfile
    destination = "/opt/proxy/config/Caddyfile"
  }

  # 2) frps.toml 配置
  provisioner "file" {
    content     = local.frps_toml
    destination = "/opt/proxy/config/frps.toml"
  }

  # 3) docker-compose.yml 配置
  provisioner "file" {
    content     = local.compose_yml
    destination = "/opt/proxy/compose/docker-compose.yml"
  }

  # 4) コンテナ起動
  provisioner "remote-exec" {
    inline = [
      "set -eux",
      "cd /opt/proxy/compose",
      "sudo docker compose pull",
      "sudo docker compose up -d",
      "sleep 5",
      "sudo docker ps",
      "echo 'frps and Caddy containers are running'",
    ]
  }
}
