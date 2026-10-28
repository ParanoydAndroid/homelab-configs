#!/usr/bin/env bash
# ==============================================================================
# Script Name: generate-local-cert.sh
# Description:
#   Generates a 10-year self-signed RSA-4096 X.509 wildcard SSL certificate and
#   private key ('turing.crt' and 'turing.key') with Subject Alternative Names
#   (SANs) covering all internal homelab domains ('turing.home', '*.turing.home',
#   'nas.home', and '*.nas.home').
#
# Purpose and Operation:
#   Modern browsers (Chrome, Firefox, Safari) reject self-signed certificates
#   that rely solely on the Distinguished Name Common Name (CN) field and
#   require all matched hostnames/wildcards to appear in the X.509 v3
#   'subjectAltName' (SAN) extension.
#
#   This script dynamically builds an OpenSSL request configuration file
#   ('cert.conf') containing apex and wildcard DNS SAN entries for every domain
#   in the DOMAINS array, and invokes 'openssl req -x509' to output an
#   unencrypted private key ('turing.key') and self-signed certificate
#   ('turing.crt') in the current working directory.
#
#   One single generated certificate can be:
#     1. Imported once into client OS/browser Trusted Root Certificate stores.
#     2. Uploaded to the UGREEN NAS Control Panel (for 'nas.home').
#     3. Uploaded as a Custom Certificate in Nginx Proxy Manager (for '*.turing.home').
#
# Usage:
#   cd ~/services/.configs/nginx
#   ./generate-local-cert.sh
# ==============================================================================

set -euo pipefail

# Base internal LAN domains to include in the certificate's Subject Alternative
# Name (SAN) extension. Both the apex domain (<domain>) and wildcard (*.<domain>)
# are automatically added for each entry.
DOMAINS=("turing.home" "nas.home")

CONFIG_FILE="cert.conf"
KEY_FILE="turing.key"
CERT_FILE="turing.crt"

echo "==> Generating OpenSSL configuration for domains: ${DOMAINS[*]}"

# Write the static portion of the OpenSSL configuration file, setting the
# primary Common Name (CN) to the first domain in DOMAINS and referencing the
# '@alt_names' section for X.509 v3 Subject Alternative Names.
cat <<EOF > "$CONFIG_FILE"
[req]
default_bits = 4096
distinguished_name = req_distinguished_name
req_extensions = req_ext
prompt = no

[req_distinguished_name]
C = US
ST = Ohio
L = Dayton
O = Homelab
CN = ${DOMAINS[0]}

[req_ext]
subjectAltName = @alt_names

[alt_names]
EOF

# Iterate over DOMAINS and append numbered DNS.<N> entries for both the bare
# domain (e.g., turing.home) and its single-level wildcard (e.g., *.turing.home).
counter=1
for domain in "${DOMAINS[@]}"; do
    echo "DNS.$counter = $domain" >> "$CONFIG_FILE"
    ((counter++))
    echo "DNS.$counter = *.$domain" >> "$CONFIG_FILE"
    ((counter++))
done

echo "==> Generating private key ($KEY_FILE) and self-signed certificate ($CERT_FILE)..."

# Generate a new 4096-bit RSA key and self-signed X.509 certificate valid for
# 3650 days (~10 years) without passphrase encryption (-nodes) so Nginx and
# the NAS web server can load the key unattended at boot.
openssl req -x509 -nodes -days 3650 -newkey rsa:4096 \
    -keyout "$KEY_FILE" \
    -out "$CERT_FILE" \
    -config "$CONFIG_FILE" \
    -extensions req_ext

echo "==> Success! Generated $KEY_FILE and $CERT_FILE in $(pwd)"
