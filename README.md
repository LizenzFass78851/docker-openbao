# OpenBao Docker Setup

This Docker setup provides a production-ready OpenBao instance with persistent data storage, configured as a Certificate Authority with ACME protocol support and auto-unseal capability.

## Features

✓ **Auto-Unseal** - Automatic unsealing on startup using static key encryption
✓ **Certificate Authority** - Full PKI functionality with root CA
✓ **ACME Protocol** - RFC 8555 compliant for automatic certificate issuance (fully tested and working)
✓ **Persistent Storage** - File-based backend with Docker volumes
✓ **Production Ready** - Configurable with TLS support
✓ **Easy Setup** - Automated scripts for initialization
✓ **Comprehensive Testing** - Included test suite to verify ACME functionality

## Quick Start

1. **Generate Auto-Unseal Key** (first time only):
   ```bash
   ./generate-unseal-key.sh
   ```

   This creates a 32-byte encryption key for automatic unsealing. Keep this key safe!

2. **Start OpenBao**:
   ```bash
   docker-compose up -d
   ```

3. **Initialize OpenBao** (first time only):
   ```bash
   docker exec -it openbao bao operator init
   ```

   **Important**: With auto-unseal enabled, you'll receive **recovery keys** instead of unseal keys.
   Save the recovery keys and root token securely!

4. **Verify Auto-Unseal** (OpenBao should already be unsealed):
   ```bash
   docker exec -it openbao bao status
   ```

   You should see `Sealed: false` without needing to manually unseal.

5. **Configure Settings** (first time only):

   Copy the example environment file and edit it with your token:
   ```bash
   cp .env.example .env
   # Edit .env and set OPENBAO_TOKEN to your root token from step 3
   ```

6. **Setup PKI and ACME** (first time only):

   **Option A: Generate a new CA certificate** (recommended for testing):
   ```bash
   ./init-pki.sh
   ```

   **Option B: Import an existing CA certificate**:

   First, add the CA paths to your [.env](.env) file:
   ```bash
   CA_CERT_PATH=./path/to/ca.crt
   CA_KEY_PATH=./path/to/ca.key
   ```

   Or use a bundle file:
   ```bash
   CA_BUNDLE_PATH=./path/to/ca-bundle.pem
   ```

   Then run:
   ```bash
   ./import-ca.sh
   ```

   This will configure OpenBao as a Certificate Authority with ACME support.

7. **Test ACME Configuration**:
   ```bash
   ./test-acme.sh
   ```

   This will verify that ACME is properly configured and working.

8. **Access the UI**:
   Open http://localhost:8200 in your browser

## Directory Structure

```
.
├── Dockerfile              # OpenBao container image
├── docker-compose.yml      # Docker Compose configuration
├── config.hcl             # OpenBao server configuration
├── init-pki.sh            # PKI and ACME setup script (generates new CA)
├── import-ca.sh           # Import existing CA certificate and key
├── create-test-ca.sh      # Create a test CA for import testing
├── generate-unseal-key.sh # Auto-unseal key generator
├── update-allowed-domains.sh # Update ACME allowed domains
├── test-acme.sh           # ACME configuration test script
├── fix-acme-path.sh       # Fix ACME URL paths (if needed)
├── .env.example           # Environment variables template
├── TESTING.md             # Test results and verification documentation
├── data/                  # Persistent data storage (created automatically)
├── logs/                  # Log files (created automatically)
└── secrets/               # Auto-unseal key storage (created automatically)
    └── unseal.key         # 32-byte encryption key for auto-unseal
```

## Configuration

### Auto-Unseal

This setup uses **Static Key auto-unseal**, which means:
- OpenBao automatically unseals on startup without manual intervention
- The unseal key is stored in `./secrets/unseal.key` (32-byte AES-256 key)
- You receive **recovery keys** during initialization instead of unseal keys
- Recovery keys are used for emergency operations and key rotation

**Important**: The `secrets/unseal.key` file is critical. Without it, you cannot unseal OpenBao. Keep secure backups!

### Storage
Data is persisted in the `./data` directory using the file storage backend. This directory is mounted as a volume and will survive container restarts.

### Ports
- **8200**: API, Web UI, and ACME directory endpoint
- **8201**: Cluster communication (for HA setups)

### Security Notes

⚠️ **Important Security Considerations**:

1. **Auto-Unseal Key Protection**:
   - The `secrets/unseal.key` file must be protected with appropriate file permissions
   - Never commit this file to version control (it's in .gitignore)
   - Create secure backups in a separate location (e.g., encrypted USB drive, password manager)
   - For production, consider using cloud KMS or HSM instead of static key

2. **TLS is disabled by default** - For production, enable TLS in `config.hcl`:
   ```hcl
   listener "tcp" {
     address     = "0.0.0.0:8200"
     tls_disable = 0
     tls_cert_file = "/openbao/certs/cert.pem"
     tls_key_file = "/openbao/certs/key.pem"
   }
   ```

3. **Recovery keys** - With auto-unseal, you receive recovery keys instead of unseal keys. Store them securely!

4. **Root token** - Revoke and create limited-privilege tokens for normal operations

5. **Backups** - Regularly backup both the `./data` directory AND the `./secrets/unseal.key` file

## PKI and ACME Configuration

### Importing an Existing CA Certificate

If you have an existing CA certificate and private key that you want OpenBao to use for signing certificates, use the import script:

**Prerequisites:**
- CA certificate file (PEM format)
- CA private key file (PEM format, unencrypted)
- Or a bundle file containing both
- Your [.env](.env) file configured with OPENBAO_TOKEN

**Import Process:**

1. **Using separate certificate and key files**:

   Add to your [.env](.env) file:

   ```bash
   CA_CERT_PATH=./mycert.crt
   CA_KEY_PATH=./mykey.key
   ISSUER_NAME=my-company-ca  # Optional: friendly name
   ```

   Then run:

   ```bash
   ./import-ca.sh
   ```

2. **Using a bundle file (certificate + key in one file)**:

   Add to your [.env](.env) file:

   ```bash
   CA_BUNDLE_PATH=./ca-bundle.pem
   ISSUER_NAME=my-company-ca  # Optional: friendly name
   ```

   Then run:

   ```bash
   ./import-ca.sh
   ```

**What the import script does:**
- Imports your CA certificate and private key into OpenBao
- Configures the issuer with a friendly name
- Sets it as the default issuer
- Configures ACME support using your imported CA
- Creates certificate roles (general and acme)
- Sets up CRL and auto-tidy

**Important Notes:**
- The private key must be unencrypted (no passphrase)
- PEM format is required
- The CA certificate can be a root or intermediate CA
- After import, all certificates issued by OpenBao will be signed by your imported CA

**Testing the Import Feature:**

If you want to test the import functionality without using a real CA, you can create a test CA:

```bash
# Create a test CA certificate
./create-test-ca.sh

# Add to your .env file
echo "CA_BUNDLE_PATH=./test-ca/ca-bundle.pem" >> .env

# Import it into OpenBao
./import-ca.sh
```

### ACME Directory URL
After running `init-pki.sh` or `import-ca.sh`, your ACME directory will be available at:
```
http://localhost:8200/v1/pki/acme/directory
```

### Using ACME with Certbot

Request a certificate using certbot (with custom directories to avoid permission issues):
```bash
certbot certonly \
  --server http://localhost:8200/v1/pki/acme/directory \
  --email admin@example.com \
  -d example.com \
  -d www.example.com \
  --config-dir ./certbot/config \
  --work-dir ./certbot/work \
  --logs-dir ./certbot/logs \
  --standalone
```

Or run with sudo to use system directories:
```bash
sudo certbot certonly \
  --server http://localhost:8200/v1/pki/acme/directory \
  --email admin@example.com \
  -d example.com \
  -d www.example.com \
  --standalone
```

**Important Notes**:
- You'll need to stop any service running on port 80 for `--standalone` mode
- For local testing without a real domain, use `--manual` with DNS challenges
- The domains must be in the allowed list configured in the PKI role (see `init-pki.sh`)
- For testing, you can modify the `ALLOWED_DOMAINS` or `ACME_ALLOWED_DOMAINS` environment variables

**Testing with a local domain** (without port 80):
```bash
# Use manual mode with DNS challenge for testing
certbot certonly \
  --server http://localhost:8200/v1/pki/acme/directory \
  --email admin@example.com \
  -d test.example.com \
  --config-dir ./certbot/config \
  --work-dir ./certbot/work \
  --logs-dir ./certbot/logs \
  --manual \
  --preferred-challenges dns
```

### Using ACME with acme.sh

```bash
acme.sh --server http://localhost:8200/v1/pki/acme/directory \
  --issue -d example.com \
  --standalone
```

### Manual Certificate Issuance

Issue a certificate directly (without ACME):
```bash
docker exec openbao bao write pki/issue/general \
  common_name=test.example.com \
  ttl=720h
```

### Download Root CA Certificate

```bash
curl http://localhost:8200/v1/pki/ca/pem > root-ca.crt
```

You can then import this root CA certificate into your system's trust store or application.

### Certificate Roles

Two roles are configured by default:

1. **general**: For standard certificate issuance via API
   - Allowed domains: Configured via `ALLOWED_DOMAINS` environment variable
   - Max TTL: 720h (30 days)

2. **acme**: For ACME protocol certificate issuance
   - Allowed domains: Configured via `ACME_ALLOWED_DOMAINS` (default: `*`)
   - Max TTL: 2160h (90 days)
   - Supports wildcard certificates

### Configuring Allowed Domains for ACME

The domains that can be issued via ACME are controlled by the **acme role**. You can configure them in several ways:

**Option 1: Set before initial setup** in your [.env](.env) file:

```bash
ACME_ALLOWED_DOMAINS=example.com,example.org,mydomain.com
```

Then run:

```bash
./init-pki.sh
```

**Option 2: Update after setup** using the helper script:

Edit your [.env](.env) file and set:

```bash
ALLOWED_DOMAINS=example.com,example.org
```

Then run:

```bash
./update-allowed-domains.sh
```

**Option 3: Update manually**:
```bash
# Source your .env file first
source .env
docker exec -e VAULT_TOKEN=$OPENBAO_TOKEN openbao bao write pki/roles/acme \
  allowed_domains="example.com,example.org" \
  allow_subdomains=true \
  allow_wildcard_certificates=true
```

**Domain Configuration Examples:**
- `*` - Allow any domain (default, good for testing)
- `example.com` - Only allow example.com
- `example.com,example.org` - Allow multiple specific domains
- `*.example.com` - Allow any subdomain of example.com
- `example.com,*.example.org` - Mixed: exact match and subdomain wildcard

### Customization

You can customize the PKI setup by editing your [.env](.env) file before running [init-pki.sh](init-pki.sh):

```bash
# Edit your .env file with your settings:
OPENBAO_TOKEN=your-root-token
CA_COMMON_NAME=My Company Root CA
ALLOWED_DOMAINS=example.com,example.org
ACME_ALLOWED_DOMAINS=*.example.com
CLUSTER_PATH=https://openbao.example.com
```

Then run:

```bash
./init-pki.sh
```

See [.env.example](.env.example) for all available configuration options.

## Common Commands

### Test ACME Configuration
```bash
./test-acme.sh
```

This runs a comprehensive test to verify:
- OpenBao is running and unsealed
- ACME directory endpoint is accessible
- ACME URLs are correctly configured
- Nonce endpoint is working
- ACME role is properly set up

### Check status
```bash
docker exec -it openbao bao status
```

**Note**: If you see an error like "http: server gave HTTP response to HTTPS client", the container needs to be rebuilt:
```bash
docker-compose down
docker-compose up -d --build
```

### View logs
```bash
docker-compose logs -f openbao
```

### Stop OpenBao
```bash
docker-compose down
```

### Restart OpenBao
```bash
docker-compose restart
```

### List issued certificates
```bash
docker exec openbao bao list pki/certs
```

### Revoke a certificate
```bash
docker exec openbao bao write pki/revoke serial_number="xx:xx:xx:..."
```

## Auto-Unseal Details

### What is Auto-Unseal?

Traditional Vault/OpenBao requires manual unsealing after every restart by entering multiple unseal keys (Shamir's Secret Sharing). With auto-unseal:
- OpenBao automatically unseals on startup without human intervention
- Uses an encryption key to decrypt the master key
- Provides **recovery keys** instead of unseal keys during initialization
- Recovery keys are used for emergency operations and rekeying

### Static Key Seal

This setup uses the **Static Key** seal method, which:
- Stores a 32-byte AES-256-GCM encryption key in `./secrets/unseal.key`
- Is ideal for development and small-scale deployments
- Requires securing the key file (backups, permissions, etc.)

### Alternative Seal Methods

For production environments, consider these more secure options:

| Seal Type | Use Case | Security Level |
|-----------|----------|----------------|
| **AWS KMS** | AWS deployments | High (managed service) |
| **Azure Key Vault** | Azure deployments | High (managed service) |
| **GCP Cloud KMS** | GCP deployments | High (managed service) |
| **PKCS#11/HSM** | On-premise with HSM | Very High (hardware) |
| **OpenBao Transit** | Multi-instance setup | High (another OpenBao) |
| **Static Key** | Development/testing | Medium (file-based) |

To migrate to a different seal method, update the `seal` block in `config.hcl`:

```hcl
# Example: AWS KMS
seal "awskms" {
  region     = "us-east-1"
  kms_key_id = "your-kms-key-id"
}
```

### Recovery Keys vs Unseal Keys

| Feature | Shamir Unseal Keys | Recovery Keys (Auto-Unseal) |
|---------|-------------------|------------------------------|
| **Purpose** | Unseal OpenBao | Emergency operations only |
| **When used** | Every restart | Rarely (disaster recovery) |
| **Required for normal operation** | Yes | No |
| **Number needed** | 3 of 5 (default) | 3 of 5 (default) |
| **Used for** | Unsealing | Rekeying, regenerating root token |

### Disaster Recovery

If you lose access to the auto-unseal key:

1. **Prevention**: Keep multiple secure backups
   - Encrypted external drive
   - Password manager (as secure note)
   - Secure cloud storage (encrypted)
   - Physical safe/vault

2. **If lost**: You cannot unseal OpenBao. Data is unrecoverable without the key.

3. **Best practice**: Test your backups regularly by:
   ```bash
   # Backup
   cp secrets/unseal.key secrets/unseal.key.backup.$(date +%Y%m%d)

   # Test restore (on a test instance)
   cp secrets/unseal.key.backup.YYYYMMDD secrets/unseal.key
   docker-compose restart
   docker exec openbao bao status
   ```

## Alternative: Using Pre-built Image

If you prefer not to build the Dockerfile, you can run directly:

```bash
# Generate unseal key first
./generate-unseal-key.sh

# Run with Docker
docker run -d \
  --name openbao \
  --cap-add=IPC_LOCK \
  -p 8200:8200 \
  -v $(pwd)/data:/openbao/data \
  -v $(pwd)/secrets:/openbao/secrets:ro \
  -v $(pwd)/config.hcl:/openbao/config/config.hcl:ro \
  quay.io/openbao/openbao:latest \
  server -config=/openbao/config/config.hcl
```

## Troubleshooting

### ACME returns 404 errors with certbot

If you see errors like `acme.errors.ClientError: <Response [404]>`, the ACME directory URLs might be incorrectly configured.

**Diagnosis**: Check the ACME directory response:
```bash
curl http://localhost:8200/v1/pki/acme/directory | jq .
```

If the URLs show `/acme/...` instead of `/v1/pki/acme/...`, the cluster path needs to be fixed.

**Fix**: Run the fix script (it will use your token from [.env](.env)):

```bash
./fix-acme-path.sh
```

Or manually update the configuration:

```bash
source .env  # Load your token
docker exec -e VAULT_TOKEN=$OPENBAO_TOKEN openbao bao write pki/config/cluster \
  path="http://localhost:8200/v1/pki" \
  aia_path="http://localhost:8200/v1/pki"
```

After fixing, verify the directory returns correct URLs:
```bash
curl http://localhost:8200/v1/pki/acme/directory
```

You should see URLs like `http://localhost:8200/v1/pki/acme/new-account` (with `/v1/pki/` in the path).

### OpenBao won't unseal automatically

1. **Check if the unseal key exists**:
   ```bash
   ls -l secrets/unseal.key
   ```

2. **Verify key permissions**:
   ```bash
   chmod 600 secrets/unseal.key
   ```

3. **Check OpenBao logs**:
   ```bash
   docker-compose logs openbao
   ```

4. **Verify the key is readable inside the container**:
   ```bash
   docker exec openbao ls -l /openbao/secrets/unseal.key
   ```

### "Permission denied" errors

Ensure proper file permissions:
```bash
chmod 700 secrets
chmod 600 secrets/unseal.key
```

### Migrating from Shamir to Auto-Unseal

If you have an existing OpenBao instance with Shamir unsealing:

1. **Backup your data**:
   ```bash
   cp -r data data.backup
   ```

2. **Update config.hcl** with the seal block (already done)

3. **Generate unseal key**:
   ```bash
   ./generate-unseal-key.sh
   ```

4. **Restart and unseal manually one last time**:
   ```bash
   docker-compose restart
   docker exec -it openbao bao operator unseal
   # Enter your Shamir keys 3 times
   ```

5. **Migrate to auto-unseal**:
   ```bash
   docker exec -it openbao bao operator unseal -migrate
   ```

6. **Restart to test auto-unseal**:
   ```bash
   docker-compose restart
   docker exec openbao bao status
   ```

## Documentation

For more information, visit:
- OpenBao Documentation: https://openbao.org/docs/
- PKI Secrets Engine: https://openbao.org/docs/secrets/pki/
- ACME Protocol: https://openbao.org/docs/secrets/pki/
- Seal Configuration: https://openbao.org/docs/configuration/seal/
