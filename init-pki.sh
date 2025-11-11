#!/bin/bash
# OpenBao PKI and ACME Initialization Script
# This script sets up OpenBao as a Certificate Authority with ACME support

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
CA_COMMON_NAME=${CA_COMMON_NAME:-"OpenBao Root CA"}
CA_TTL=${CA_TTL:-"87600h"}  # 10 years
ALLOWED_DOMAINS=${ALLOWED_DOMAINS:-"example.com,localhost"}
ACME_ALLOWED_DOMAINS=${ACME_ALLOWED_DOMAINS:-"*"}
CLUSTER_PATH=${CLUSTER_PATH:-"http://localhost:8200"}

echo -e "${GREEN}=== OpenBao PKI and ACME Setup ===${NC}"
echo ""

# Check if OpenBao is initialized and unsealed
echo -e "${YELLOW}Checking OpenBao status...${NC}"
if ! docker exec openbao bao status > /dev/null 2>&1; then
    echo -e "${RED}Error: OpenBao is sealed or not initialized.${NC}"
    echo "Please initialize and unseal OpenBao first:"
    echo "  docker exec -it openbao bao operator init"
    echo "  docker exec -it openbao bao operator unseal (run 3 times)"
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

echo -e "${GREEN}Step 1: Enabling PKI secrets engine...${NC}"
if bao_exec secrets list | grep -q "^pki/"; then
    echo -e "${YELLOW}PKI engine already enabled, skipping...${NC}"
else
    bao_exec secrets enable pki
    echo -e "${GREEN}✓ PKI engine enabled${NC}"
fi

echo -e "${GREEN}Step 2: Configuring PKI maximum TTL...${NC}"
bao_exec secrets tune -max-lease-ttl=$CA_TTL pki
echo -e "${GREEN}✓ Maximum TTL set to $CA_TTL${NC}"

echo -e "${GREEN}Step 3: Generating root CA certificate...${NC}"
if bao_exec read -field=certificate pki/cert/ca > /dev/null 2>&1; then
    echo -e "${YELLOW}Root CA already exists, skipping generation...${NC}"
else
    bao_exec write pki/root/generate/internal \
        common_name="$CA_COMMON_NAME" \
        ttl=$CA_TTL \
        key_type=rsa \
        key_bits=4096 \
        ou="IT Department" \
        exclude_cn_from_sans=true
    echo -e "${GREEN}✓ Root CA certificate generated${NC}"
fi

echo -e "${GREEN}Step 4: Configuring CA URLs...${NC}"
bao_exec write pki/config/urls \
    issuing_certificates="$CLUSTER_PATH/v1/pki/ca" \
    crl_distribution_points="$CLUSTER_PATH/v1/pki/crl" \
    ocsp_servers="$CLUSTER_PATH/v1/pki/ocsp" \
    enable_templating=true
echo -e "${GREEN}✓ CA URLs configured${NC}"

echo -e "${GREEN}Step 5: Configuring cluster path for ACME...${NC}"
bao_exec write pki/config/cluster \
    path="$CLUSTER_PATH/v1/pki" \
    aia_path="$CLUSTER_PATH/v1/pki"
echo -e "${GREEN}✓ Cluster path configured${NC}"

echo -e "${GREEN}Step 6: Enabling ACME...${NC}"
bao_exec write pki/config/acme \
    enabled=true \
    allowed_issuers=default \
    allowed_roles="*" \
    default_directory_policy=sign-verbatim \
    eab_policy=not-required \
    dns_resolver=""
echo -e "${GREEN}✓ ACME enabled${NC}"

echo -e "${GREEN}Step 7: Enabling required response headers...${NC}"
bao_exec secrets tune \
    -passthrough-request-headers=If-Modified-Since \
    -allowed-response-headers=Last-Modified \
    -allowed-response-headers=Location \
    -allowed-response-headers=Replay-Nonce \
    -allowed-response-headers=Link \
    pki
echo -e "${GREEN}✓ Response headers configured${NC}"

echo -e "${GREEN}Step 8: Creating certificate roles...${NC}"

# Create a general purpose role
bao_exec write pki/roles/general \
    allowed_domains="$ALLOWED_DOMAINS" \
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
    allowed_domains="$ACME_ALLOWED_DOMAINS" \
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

echo -e "${GREEN}Step 9: Configuring CRL...${NC}"
bao_exec write pki/config/crl \
    expiry=72h \
    disable=false \
    auto_rebuild=true \
    auto_rebuild_grace_period=12h \
    enable_delta=false
echo -e "${GREEN}✓ CRL configured${NC}"

echo -e "${GREEN}Step 10: Setting up auto-tidy for ACME...${NC}"
bao_exec write pki/config/auto-tidy \
    enabled=true \
    interval_duration=12h \
    tidy_cert_store=true \
    tidy_revoked_certs=true \
    tidy_acme=true \
    safety_buffer=72h
echo -e "${GREEN}✓ Auto-tidy configured${NC}"

echo ""
echo -e "${GREEN}=== Setup Complete! ===${NC}"
echo ""
echo -e "${GREEN}Your OpenBao CA is now ready with ACME support!${NC}"
echo ""
echo "ACME Directory URL:"
echo -e "  ${GREEN}$CLUSTER_PATH/v1/pki/acme/directory${NC}"
echo ""
echo "Certificate Roles:"
echo "  - general: For standard certificate issuance"
echo "  - acme: For ACME protocol certificate issuance"
echo ""
echo "Example ACME client usage (with certbot):"
echo "  certbot certonly --server $CLUSTER_PATH/v1/pki/acme/directory \\"
echo "    --email admin@example.com \\"
echo "    -d example.com"
echo ""
echo "Manual certificate issuance:"
echo "  bao write pki/issue/general common_name=test.example.com"
echo ""
echo "Download root CA certificate:"
echo -e "  ${GREEN}curl $CLUSTER_PATH/v1/pki/ca/pem${NC}"
echo ""
