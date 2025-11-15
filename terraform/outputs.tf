# outputs.tf の deployment_status を置き換え
output "deployment_status" {
  value = <<-EOT
    ✓ frpsサーバーのデプロイが完了しました。

    【サービス情報】
    - frps: ポート 7000 (クライアント接続), 8080 (内部HTTP), 7500 (ダッシュボード)
    - Caddy: %{if var.enable_caddy}%{if var.caddy_mode == "http-only"}ポート 80 (HTTPのみ)%{else}ポート 80, 443 (HTTPS自動TLS)%{endif}%{else}起動なし%{endif}

    【アクセス】
    - メインドメイン: http%{if var.enable_caddy && var.caddy_mode != "http-only"}s%{endif}://${var.domain}
    - サブドメイン例: http%{if var.enable_caddy && var.caddy_mode != "http-only"}s%{endif}://<任意ID>.${var.domain}

    【次のステップ】
    1. frpcクライアントを設定して接続テスト
    2. VPSでコンテナ確認: ssh ${var.ssh_user}@${var.vps_ip} "docker ps"
    3. ログ確認: docker logs frps / docker logs caddy
  EOT
}

output "vps_ip" {
  value       = var.vps_ip
  description = "デプロイ先VPSのIPアドレス"
}

output "frpc_config_example" {
  value = <<-EOT
    # frpc.toml (クライアント側の設定例)
    serverAddr = "${var.domain}"
    serverPort = 7000
    protocol   = "wss"

    [auth]
    method = "token"
    token  = "YOUR_FRP_TOKEN"

    [[proxies]]
    name      = "myservice"
    type      = "http"
    localPort = 8080
    subdomain = "myservice"  # => http%{if var.enable_caddy && var.caddy_mode != "http-only"}s%{endif}://myservice.${var.domain}
  EOT
}
