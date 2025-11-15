# SakuraVPS FRP deployment info

- Status: frps server deployment complete (Terraform shows no changes)
- VPS IP: 133.167.107.172

Services
- frps: 7000 (client), 8080 (internal HTTP), 7500 (dashboard)
- Caddy: 80 (HTTP only)

Access
- Main domain: http://kimulabfrp.jp
- Subdomain pattern: http://<任意ID>.kimulabfrp.jp

Next steps (from output)
- Configure frpc client and run connection test
- Check containers on VPS: `ssh ubuntu@133.167.107.172 "docker ps"`
- Check logs: `docker logs frps` / `docker logs caddy`

frpc.toml example
```
# frpc.toml (client-side example)
serverAddr = "kimulabfrp.jp"
serverPort = 7000
protocol   = "wss"

[auth]
method = "token"
token  = "YOUR_FRP_TOKEN"

[[proxies]]
name      = "myservice"
type      = "http"
localPort = 8080
subdomain = "myservice"  # => http://myservice.kimulabfrp.jp
```
