# Network configuration details for homelab setup

## Basic Network Configuration:

### Subnets
- Single NAT -- IP masquerade assigns WAN IP directly to my gateway from the modem
- Gateway at 192.168.0.1/24
- Gateway exposes a wireguard vpn at 192.168.1.128/25 (gateway at 128)
- Docker on NAS uses *user created* network homelab, at 192.168.255.0/24 (gateway at 1)

### Static ip and dns assignments
- Pi-hole at 0.2
- Gateway assigns 0.2 as dns to all dhcp clients
- dhcp gets .home local domain
- pi-hole gets same local domain
- NAS at 0.3
- pihole gets a conditional forwarding setup to forward .home DNS to DhCP client (0.1)
- a local AAAA record for turing.home to NAS

### Firewall Settings
SOURCE 192.168.0.0/16 ALLOW
PORT 443 ALLOW
ALL DENY


## Application Setup
All services are provided by the NAS.  It exposes service ports as subdomains, via a reverse proxy.

- Each application is run in docker, the reverse dns exposes that port to a custom local domain
name.
 
- pi-hole gets a CNAME record for each subdomain exposed via the reverse proxy, to turing.home

## Port Mappings
-- Port mappings for each <Service> provides by docker, in host:container format for each port

| Service Name | Host Port (NAS) | Internal Port (Docker) | Protocol | Notes    |
|--------------|-----------------|------------------------|----------|----------|
| DSM          |                 |                        |          |          |
|              | 5000            |                        | HTTP     | *        |
|              | 5001            |                        | HTTPS    |          |
| Portainer    |                 |                        |          |          |
|              | 8010            | 8000                   | HTTPS    |          |
|              | 8011            | 9000                   | HTTP     | *        |
| Jellyfin     |                 |                        |          |          |
|              | 8020            | 8096                   | HTTP     | *        |
|              | 8021            | 8920                   |          |          |
|              | 8022            | 7359                   | udp      | announce |
| Homepage     |                 |                        |          |          |
|              | 8030            | 3000                   |          | *        |
| Radarr       |                 |                        |          |          |
|              | 8040            | 7878                   |          |          |
| Sonarr       |                 |                        |          |          |
|              | 8041            | 8989                   |          |          |
| Prowlarr     |                 |                        |          |          |
|              | 8042            | 9696                   |          |          |
| Flaresolverr |                 |                        |          |          |
|              | 8043            | 8191                   |          |          |