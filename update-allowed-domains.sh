#!/bin/bash
# Update Allowed Domains for ACME Role
# This script updates the allowed domains for certificate issuance via ACME

set -e

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Load environment variables from .env file if it exists
if [ -f .env ]; then
    echo -e "${GREEN}Loading configuration from .env file...${NC}"
    set -a  # Automatically export all variables
    source .env
    set +a
    echo ""
else
    echo -e "${YELLOW}Warning: .env file not found.${NC}"
    echo ""
fi

# Configuration variables (with defaults if not set in .env)
OPENBAO_TOKEN=${OPENBAO_TOKEN:-""}
ALLOWED_DOMAINS=${ALLOWED_DOMAINS:-""}

echo -e "${GREEN}=== Update ACME Allowed Domains ===${NC}"
echo ""

# Check if token is set
if [ -z "$OPENBAO_TOKEN" ]; then
    echo -e "${YELLOW}Enter your OpenBao root token:${NC}"
    read -s OPENBAO_TOKEN
    echo ""
fi

export VAULT_TOKEN=$OPENBAO_TOKEN
export VAULT_ADDR=http://localhost:8200

# Function to run bao commands
bao_exec() {
    docker exec -e VAULT_TOKEN=$VAULT_TOKEN -e VAULT_ADDR=$VAULT_ADDR openbao bao "$@"
}

# Get current configuration
echo -e "${YELLOW}Current ACME role configuration:${NC}"
CURRENT_DOMAINS=$(bao_exec read -field=allowed_domains pki/roles/acme 2>/dev/null || echo "Role not found")
echo "  Allowed domains: $CURRENT_DOMAINS"
echo ""

# Prompt for new domains if not set
if [ -z "$ALLOWED_DOMAINS" ]; then
    echo -e "${YELLOW}Enter allowed domains (comma-separated, or '*' for all):${NC}"
    echo "Examples:"
    echo "  example.com,example.org"
    echo "  *.example.com"
    echo "  *"
    read ALLOWED_DOMAINS
    echo ""
fi

echo -e "${YELLOW}Updating ACME role with allowed domains: $ALLOWED_DOMAINS${NC}"

# Update the role
bao_exec write pki/roles/acme \
    allowed_domains="$ALLOWED_DOMAINS" \
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

echo -e "${GREEN}✓ ACME role updated${NC}"
echo ""

# Show new configuration
echo -e "${GREEN}New ACME role configuration:${NC}"
bao_exec read pki/roles/acme | grep -E "(allowed_domains|allow_subdomains|allow_bare_domains|allow_wildcard)"
echo ""

echo -e "${GREEN}Domain restrictions updated successfully!${NC}"
echo ""
echo "ACME clients can now request certificates for:"
if [ "$ALLOWED_DOMAINS" = "*" ]; then
    echo "  - Any domain"
else
    echo "  - Domains: $ALLOWED_DOMAINS"
fi
echo "  - Subdomains: allowed"
echo "  - Wildcard certificates: allowed"
echo ""
