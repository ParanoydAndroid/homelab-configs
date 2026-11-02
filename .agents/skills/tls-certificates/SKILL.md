---
name: tls-certificates
description: >-
  Operational runbook for managing local TLS certificates, generating internal
  root Certificate Authorities (CA), provisioning wildcard certificates for *.home
  domains, importing into Nginx Proxy Manager and UGREEN NAS, and establishing trust
  across client operating systems (macOS, Windows, Linux, iOS, Android, Firefox).
---

# TLS Certificates & Trust Management Runbook

This skill guides the creation, deployment, and client distribution of local TLS certificates and Certificate Authorities (CAs) across the homelab infrastructure.

---

## 1. Local Wildcard Certificate Generation

The repository provides an automated generation script at `.configs/nginx/generate-local-cert.sh`.

### Execution
```bash
cd .configs/nginx
./generate-local-cert.sh
```

### Artifacts Produced
- `turing.key`: 2048-bit RSA private key.
- `turing.crt`: Self-signed root CA and wildcard certificate valid for 10 years (3650 days).
- **Subject Alternative Names (SANs)**:
  - `turing.home`, `*.turing.home`
  - `nas.home`, `*.nas.home`
  - `192.168.0.4` (NPM macvlan IP)
  - `192.168.0.5` (Tailscale IP)
  - `192.168.0.2` (Pi-hole IP)

---

## 2. Deploying to Nginx Proxy Manager (NPM)

1. Open NPM Admin UI at `https://proxy.turing.home` (or `http://192.168.0.4:81`).
2. Navigate to **SSL Certificates** -> click **Add SSL Certificate** -> select **Custom**.
3. **Name**: `Local Wildcard (turing.home + nas.home)`.
4. **Certificate Key**: Paste contents of `.configs/nginx/turing.key`.
5. **Certificate**: Paste contents of `.configs/nginx/turing.crt`.
6. Click **Save**.
7. In **Proxy Hosts**, edit each `*.turing.home` host:
   - Under **SSL**, select the new Custom certificate.
   - Check **Force SSL**, **HTTP/2 Support**, and **HSTS Enabled**.

---

## 3. Deploying to Host Storage OS Portal (UGREEN NAS / Synology)

### UGREEN NAS (UGOS)
1. Open **Control Panel** -> **Security** -> **Certificate**.
2. Click **Add Certificate** -> select **Upload Certificate**.
3. Upload `turing.key` as private key and `turing.crt` as certificate.
4. Set as the default certificate for the portal.

### Synology DSM
1. Open **Control Panel** -> **Security** -> **Certificate**.
2. Click **Add** -> **Add a new certificate** -> **Import certificate**.
3. Upload `turing.key` and `turing.crt`.
4. Click **Configure** and assign to DSM system default.

---

## 4. Client OS & Browser Trust Distribution

To remove browser warning pages ("Your connection is not private") and establish green padlocks:

### macOS
1. Open **Keychain Access** app.
2. Select **System** keychain, then **Certificates** category.
3. Drag `turing.crt` into the window (requires administrator password).
4. Double-click the imported certificate, expand **Trust**, and change **When using this certificate** to **Always Trust**.

### Windows
1. Press `Win + R`, type `certmgr.msc`, and press Enter.
2. Expand **Trusted Root Certification Authorities** -> right-click **Certificates**.
3. Select **All Tasks** -> **Import...**.
4. Browse to and select `turing.crt`.
5. Place in **Trusted Root Certification Authorities** store and finish wizard.

### Linux (Ubuntu / Debian)
```bash
sudo cp turing.crt /usr/local/share/ca-certificates/turing.crt
sudo update-ca-certificates
```

### Firefox (Independent Certificate Store)
1. Open **Settings** -> search for **Certificates** -> click **View Certificates**.
2. Select **Authorities** tab -> click **Import...**.
3. Select `turing.crt`.
4. Check **Trust this CA to identify websites** and click **OK**.

### iOS / iPadOS
1. AirDrop or email `turing.crt` to the device.
2. Go to **Settings** -> **Profile Downloaded** -> tap **Install**.
3. Go to **Settings** -> **General** -> **About** -> **Certificate Trust Settings**.
4. Under "Enable full trust for root certificates", toggle the switch **ON** for the certificate.

### Android
1. Open **Settings** -> **Security** -> **Encryption & credentials**.
2. Tap **Install a certificate** -> select **CA certificate**.
3. Tap **Install anyway** and select `turing.crt`.
