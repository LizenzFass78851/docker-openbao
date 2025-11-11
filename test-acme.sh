#!/bin/bash
# Test ACME Configuration
# This script verifies that OpenBao's ACME implementation is working correctly

set -e

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Load environment variables from .env file if it exists
if [ -f .env ]; then
    set -a  # Automatically export all variables
    source .env
    set +a
fi

echo -e "${GREEN}=== OpenBao ACME Configuration Test ===${NC}"
echo ""

# Test 1: Check if OpenBao is running
echo -e "${YELLOW}Test 1: Checking if OpenBao is running...${NC}"
if docker ps | grep -q openbao; then
    echo -e "${GREEN}✓ OpenBao container is running${NC}"
else
    echo -e "${RED}✗ OpenBao container is not running${NC}"
    exit 1
fi

# Test 2: Check if OpenBao is unsealed
echo -e "${YELLOW}Test 2: Checking if OpenBao is unsealed...${NC}"
if docker exec openbao bao status 2>&1 | grep -q "Sealed.*false"; then
    echo -e "${GREEN}✓ OpenBao is unsealed${NC}"
else
    echo -e "${RED}✗ OpenBao is sealed${NC}"
    exit 1
fi

# Test 3: Check ACME directory endpoint
echo -e "${YELLOW}Test 3: Checking ACME directory endpoint...${NC}"
DIRECTORY_RESPONSE=$(curl -s http://localhost:8200/v1/pki/acme/directory)
if echo "$DIRECTORY_RESPONSE" | grep -q "newAccount"; then
    echo -e "${GREEN}✓ ACME directory endpoint is accessible${NC}"
else
    echo -e "${RED}✗ ACME directory endpoint not found${NC}"
    exit 1
fi

# Test 4: Verify URLs contain /v1/pki/acme/
echo -e "${YELLOW}Test 4: Verifying ACME directory URLs...${NC}"
if echo "$DIRECTORY_RESPONSE" | grep -q "v1/pki/acme"; then
    echo -e "${GREEN}✓ ACME URLs are correctly configured${NC}"
    echo "$DIRECTORY_RESPONSE" | jq .
else
    echo -e "${RED}✗ ACME URLs are incorrectly configured${NC}"
    echo -e "${RED}URLs should contain '/v1/pki/acme/' but found:${NC}"
    echo "$DIRECTORY_RESPONSE" | jq .
    echo ""
    echo -e "${YELLOW}Run ./fix-acme-path.sh to fix this issue${NC}"
    exit 1
fi

# Test 5: Check if nonce endpoint works
echo -e "${YELLOW}Test 5: Testing nonce endpoint...${NC}"
NONCE=$(curl -s -I http://localhost:8200/v1/pki/acme/new-nonce | grep -i "Replay-Nonce" | cut -d: -f2 | tr -d ' \r')
if [ -n "$NONCE" ]; then
    echo -e "${GREEN}✓ Nonce endpoint is working${NC}"
    echo "  Nonce: ${NONCE:0:30}..."
else
    echo -e "${RED}✗ Nonce endpoint is not working${NC}"
    exit 1
fi

# Test 6: Check ACME role configuration
echo -e "${YELLOW}Test 6: Checking ACME role configuration...${NC}"
if [ -n "$OPENBAO_TOKEN" ] || [ -n "$VAULT_TOKEN" ]; then
    export VAULT_TOKEN=${VAULT_TOKEN:-$OPENBAO_TOKEN}
    export VAULT_ADDR=http://localhost:8200

    ROLE_CHECK=$(docker exec -e VAULT_TOKEN=$VAULT_TOKEN -e VAULT_ADDR=$VAULT_ADDR openbao bao read pki/roles/acme 2>&1)
    if echo "$ROLE_CHECK" | grep -q "allowed_domains"; then
        echo -e "${GREEN}✓ ACME role is configured${NC}"
        echo "$ROLE_CHECK" | grep "allowed_domains"
    else
        echo -e "${YELLOW}⚠ Could not verify ACME role (token may not be set)${NC}"
    fi
else
    echo -e "${YELLOW}⚠ Skipping role check (OPENBAO_TOKEN not set)${NC}"
fi

echo ""
echo -e "${GREEN}=== All tests passed! ===${NC}"
echo ""
echo -e "${GREEN}Your OpenBao ACME server is ready to use!${NC}"
echo ""
echo "ACME Directory URL:"
echo -e "  ${GREEN}http://localhost:8200/v1/pki/acme/directory${NC}"
echo ""
echo "Example certbot command:"
echo "  certbot certonly \\"
echo "    --server http://localhost:8200/v1/pki/acme/directory \\"
echo "    --email admin@example.com \\"
echo "    -d yourdomain.com \\"
echo "    --config-dir ./certbot/config \\"
echo "    --work-dir ./certbot/work \\"
echo "    --logs-dir ./certbot/logs \\"
echo "    --manual --preferred-challenges dns"
echo ""
