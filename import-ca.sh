#!/bin/bash
# Import Existing CA Certificate and Private Key into OpenBao PKI
# This script imports an external CA certificate and private key to use for signing

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Load environment variables from .env file if it exists
if [ -f .env ]; then
    echo -e "${GREEN}Loading configuration from .env file...${NC}"
    set -a  # Automatically export all variables
    source .env
    set +a
else
    echo -e "${YELLOW}Warning: .env file not found. Using default values.${NC}"
    echo -e "${YELLOW}Consider copying .env.example to .env and customizing it.${NC}"
    echo ""
fi

# Configuration variables (with defaults if not set in .env)
OPENBAO_ADDR=${OPENBAO_ADDR:-"http://localhost:8200"}
OPENBAO_TOKEN=${OPENBAO_TOKEN:-""}
CLUSTER_PATH=${CLUSTER_PATH:-"http://localhost:8200"}

# CA certificate and key paths
CA_CERT_PATH=${CA_CERT_PATH:-""}
CA_KEY_PATH=${CA_KEY_PATH:-""}
CA_BUNDLE_PATH=${CA_BUNDLE_PATH:-""}
ISSUER_NAME=${ISSUER_NAME:-"imported-ca"}

echo -e "${GREEN}=== OpenBao CA Certificate Import ===${NC}"
echo ""

# Check if OpenBao is initialized and unsealed
echo -e "${YELLOW}Checking OpenBao status...${NC}"
if ! docker exec openbao bao status > /dev/null 2>&1; then
    echo -e "${RED}Error: OpenBao is sealed or not initialized.${NC}"
    echo "Please initialize and unseal OpenBao first."
    exit 1
fi

# Check if token is set
if [ -z "$OPENBAO_TOKEN" ]; then
    echo -e "${YELLOW}Enter your OpenBao root token:${NC}"
    read -s OPENBAO_TOKEN
    echo ""
fi

export VAULT_TOKEN=$OPENBAO_TOKEN
export VAULT_ADDR=$OPENBAO_ADDR

# Function to run bao commands inside container
bao_exec() {
    docker exec -e VAULT_TOKEN=$VAULT_TOKEN -e VAULT_ADDR=$VAULT_ADDR openbao bao "$@"
}

echo -e "${GREEN}Step 1: Checking for existing PKI engine...${NC}"
if bao_exec secrets list | grep -q "^pki/"; then
    echo -e "${YELLOW}PKI engine already enabled.${NC}"
else
    echo -e "${YELLOW}Enabling PKI secrets engine...${NC}"
    bao_exec secrets enable pki
    echo -e "${GREEN}✓ PKI engine enabled${NC}"
fi

# Determine input method
if [ -n "$CA_BUNDLE_PATH" ]; then
    # Option 1: Using a bundle file (cert + key in one file)
    echo -e "${GREEN}Step 2: Importing CA from bundle file...${NC}"

    if [ ! -f "$CA_BUNDLE_PATH" ]; then
        echo -e "${RED}Error: Bundle file not found: $CA_BUNDLE_PATH${NC}"
        exit 1
    fi

    PEM_BUNDLE=$(cat "$CA_BUNDLE_PATH")

elif [ -n "$CA_CERT_PATH" ] && [ -n "$CA_KEY_PATH" ]; then
    # Option 2: Separate cert and key files
    echo -e "${GREEN}Step 2: Importing CA from separate cert and key files...${NC}"

    if [ ! -f "$CA_CERT_PATH" ]; then
        echo -e "${RED}Error: Certificate file not found: $CA_CERT_PATH${NC}"
        exit 1
    fi

    if [ ! -f "$CA_KEY_PATH" ]; then
        echo -e "${RED}Error: Private key file not found: $CA_KEY_PATH${NC}"
        exit 1
    fi

    # Combine cert and key into PEM bundle
    PEM_BUNDLE=$(cat "$CA_CERT_PATH" "$CA_KEY_PATH")

else
    echo -e "${RED}Error: You must provide either:${NC}"
    echo -e "${RED}  1. CA_BUNDLE_PATH (certificate and key in one file)${NC}"
    echo -e "${RED}  2. CA_CERT_PATH and CA_KEY_PATH (separate files)${NC}"
    echo ""
    echo "Usage examples:"
    echo "  # Using bundle:"
    echo "  CA_BUNDLE_PATH=./ca-bundle.pem OPENBAO_TOKEN=xxx ./import-ca.sh"
    echo ""
    echo "  # Using separate files:"
    echo "  CA_CERT_PATH=./ca.crt CA_KEY_PATH=./ca.key OPENBAO_TOKEN=xxx ./import-ca.sh"
    exit 1
fi

# Import the CA certificate and key
echo -e "${YELLOW}Importing CA certificate and private key...${NC}"

IMPORT_RESULT=$(bao_exec write -format=json pki/issuers/import/bundle pem_bundle=- <<< "$PEM_BUNDLE")

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ CA certificate and key imported successfully${NC}"

    # Extract issuer IDs
    IMPORTED_ISSUERS=$(echo "$IMPORT_RESULT" | jq -r '.data.imported_issuers[]' 2>/dev/null)
    IMPORTED_KEYS=$(echo "$IMPORT_RESULT" | jq -r '.data.imported_keys[]' 2>/dev/null)

    echo -e "${GREEN}Imported Issuer ID(s): $IMPORTED_ISSUERS${NC}"
    echo -e "${GREEN}Imported Key ID(s): $IMPORTED_KEYS${NC}"

    # Get the first issuer ID
    FIRST_ISSUER=$(echo "$IMPORTED_ISSUERS" | head -1)

    if [ -n "$FIRST_ISSUER" ]; then
        # Set a friendly name for the issuer
        echo -e "${YELLOW}Setting issuer name to '$ISSUER_NAME'...${NC}"
        bao_exec write "pki/issuer/$FIRST_ISSUER" issuer_name="$ISSUER_NAME"

        # Set as default issuer
        echo -e "${YELLOW}Setting as default issuer...${NC}"
        bao_exec write pki/config/issuers default="$FIRST_ISSUER"

        echo -e "${GREEN}✓ Issuer configured with name '$ISSUER_NAME'${NC}"
    fi
else
    echo -e "${RED}✗ Failed to import CA certificate${NC}"
    exit 1
fi

echo -e "${GREEN}Step 3: Configuring PKI URLs...${NC}"
bao_exec write pki/config/urls \
    issuing_certificates="$CLUSTER_PATH/v1/pki/ca" \
    crl_distribution_points="$CLUSTER_PATH/v1/pki/crl" \
    ocsp_servers="$CLUSTER_PATH/v1/pki/ocsp" \
    enable_templating=true
echo -e "${GREEN}✓ PKI URLs configured${NC}"

echo -e "${GREEN}Step 4: Configuring cluster path for ACME...${NC}"
bao_exec write pki/config/cluster \
    path="$CLUSTER_PATH/v1/pki" \
    aia_path="$CLUSTER_PATH/v1/pki"
echo -e "${GREEN}✓ Cluster path configured${NC}"

echo -e "${GREEN}Step 5: Enabling ACME...${NC}"
bao_exec write pki/config/acme \
    enabled=true \
    allowed_issuers="$ISSUER_NAME" \
    allowed_roles="*" \
    default_directory_policy=sign-verbatim \
    eab_policy=not-required \
    dns_resolver=""
echo -e "${GREEN}✓ ACME enabled${NC}"

echo -e "${GREEN}Step 6: Enabling required response headers...${NC}"
bao_exec secrets tune \
    -passthrough-request-headers=If-Modified-Since \
    -allowed-response-headers=Last-Modified \
    -allowed-response-headers=Location \
    -allowed-response-headers=Replay-Nonce \
    -allowed-response-headers=Link \
    pki
echo -e "${GREEN}✓ Response headers configured${NC}"

echo -e "${GREEN}Step 7: Creating certificate roles...${NC}"

# Create a general purpose role
bao_exec write pki/roles/general \
    issuer_ref="$ISSUER_NAME" \
    allowed_domains="*" \
    allow_subdomains=true \
    allow_localhost=true \
    allow_ip_sans=true \
    max_ttl=720h \
    key_type=rsa \
    key_bits=2048 \
    require_cn=false \
    use_csr_common_name=true \
    use_csr_sans=true
echo -e "${GREEN}✓ General role created${NC}"

# Create an ACME-specific role
bao_exec write pki/roles/acme \
    issuer_ref="$ISSUER_NAME" \
    allowed_domains="*" \
    allow_subdomains=true \
    allow_bare_domains=true \
    allow_localhost=true \
    allow_wildcard_certificates=true \
    allow_ip_sans=true \
    max_ttl=2160h \
    key_type=rsa \
    key_bits=2048 \
    no_store=false \
    require_cn=false
echo -e "${GREEN}✓ ACME role created${NC}"

echo -e "${GREEN}Step 8: Configuring CRL...${NC}"
bao_exec write pki/config/crl \
    expiry=72h \
    disable=false \
    auto_rebuild=true \
    auto_rebuild_grace_period=12h \
    enable_delta=false
echo -e "${GREEN}✓ CRL configured${NC}"

echo -e "${GREEN}Step 9: Setting up auto-tidy for ACME...${NC}"
bao_exec write pki/config/auto-tidy \
    enabled=true \
    interval_duration=12h \
    tidy_cert_store=true \
    tidy_revoked_certs=true \
    tidy_acme=true \
    safety_buffer=72h
echo -e "${GREEN}✓ Auto-tidy configured${NC}"

echo ""
echo -e "${GREEN}=== Import Complete! ===${NC}"
echo ""
echo -e "${GREEN}Your imported CA is now configured with ACME support!${NC}"
echo ""
echo "Issuer Name: $ISSUER_NAME"
echo "ACME Directory URL:"
echo -e "  ${GREEN}$CLUSTER_PATH/v1/pki/acme/directory${NC}"
echo ""
echo "Certificate information:"
bao_exec read "pki/issuer/$ISSUER_NAME" | grep -E "(issuer_name|subject)"
echo ""
echo "Test certificate issuance:"
echo "  bao write pki/issue/general common_name=test.example.com"
echo ""
