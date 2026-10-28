# Network configuration details for homelab setup

## Basic Network Configuration:

### Subnets
- Single NAT -- IP masquerade assigns WAN IP directly to my gateway from the modem
- Gateway at 192.168.0.1/24
- Gateway exposes a wireguard vpn at 192.168.1.128/25 (gateway at 128)
- Docker on NAS uses *user created* network homelab, at 192.168.255.0/24 (gateway at 1)
- NPM connects to the homelab network but also must be exposed directly on the LAN in order to properly intercept 80/443 traffic.  So another docker network must be setup with the macvlan driver, which allows the container to present as a device on the network:

```
docker network create -d macvlan \
  --subnet=192.168.0.0/24 \
  --gateway=192.168.0.1 \
  -o parent=eth0 \
  external_npm
```

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
| Tandoor      |                 |                        |          |          |
|              | 8050            | 8050                   |          | *        |
| Postgres     |                 |                        |          |          |
|              |                 | 5432                   |          | *        |
| nginx        |                 |                        |          |          |
|              | 8480            | 80                     |          | These ports are set by the gateway on port foward (e.g. ext 80 --> int 4880).  \This avoids an issue with binding 80/443 on the DSM reverse proxy|
|              | 8443            | 443                    |          |          |
|              | 8444            | 81                     |          | *        |



Individual app notes:

nginx - Reverse proxy setup for all external addresses via npm rules:
- http -> default page
- Get certs
- setup https (force HTTPS), redirect to http protocol.
- Custom location for apps that need media service: mount /media everywhere, then the location is just
    ```
    location /media/ {
        root /;
    }
    ```
