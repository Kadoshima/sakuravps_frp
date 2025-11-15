InfluxDB endpoint subdomain
- Subdomain: influx.kimulabfrp.jp
- Purpose: Public HTTPS endpoint for InfluxDB (Caddy TLS via DNS-01/Cloudflare; reverse_proxy to container influxdb:8086)
- DNS (Cloudflare): A influx -> 133.167.107.172 (DNS only / grey cloud). TTL Auto.
- Notes: Even with http-only edge sites, influx.* uses HTTPS. Ensure CLOUDFLARE_API_TOKEN permits DNS edits for ACME DNS-01.