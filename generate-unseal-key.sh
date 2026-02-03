#!/bin/bash
# Generate Auto-Unseal Key for OpenBao
# This script creates a 32-byte encryption key for static seal auto-unseal

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

SECRETS_DIR="./secrets"
KEY_FILE="$SECRETS_DIR/unseal.key"

echo -e "${GREEN}=== OpenBao Auto-Unseal Key Generator ===${NC}"
echo ""

# Check if secrets directory exists
if [ ! -d "$SECRETS_DIR" ]; then
    echo -e "${YELLOW}Creating secrets directory...${NC}"
    mkdir -p "$SECRETS_DIR"
    chmod 700 "$SECRETS_DIR"
    echo -e "${GREEN}✓ Secrets directory created${NC}"
fi

# Check if key already exists
if [ -f "$KEY_FILE" ]; then
    echo -e "${YELLOW}Warning: Unseal key already exists at $KEY_FILE${NC}"
    echo -e "${YELLOW}If you regenerate the key, you will NOT be able to unseal existing data!${NC}"
    echo ""
    read -p "Do you want to regenerate the key? (yes/NO): " CONFIRM

    if [ "$CONFIRM" != "yes" ]; then
        echo -e "${GREEN}Keeping existing key. Exiting...${NC}"
        exit 0
    fi

    # Backup existing key
    BACKUP_FILE="$KEY_FILE.backup.$(date +%Y%m%d-%H%M%S)"
    echo -e "${YELLOW}Backing up existing key to $BACKUP_FILE${NC}"
    cp "$KEY_FILE" "$BACKUP_FILE"
fi

# Generate 32-byte random key for AES-256-GCM
echo -e "${GREEN}Generating 32-byte encryption key...${NC}"
openssl rand -out "$KEY_FILE" 32

# Set restrictive permissions
chmod 600 "$KEY_FILE"

echo -e "${GREEN}✓ Unseal key generated successfully${NC}"
echo ""
echo -e "${GREEN}Key location: $KEY_FILE${NC}"
echo -e "${YELLOW}Key size: $(stat -f%z "$KEY_FILE" 2>/dev/null || stat -c%s "$KEY_FILE" 2>/dev/null) bytes${NC}"
echo ""
echo -e "${RED}⚠️  IMPORTANT SECURITY NOTES:${NC}"
echo -e "${RED}1. This key is critical for auto-unsealing OpenBao${NC}"
echo -e "${RED}2. Keep a secure backup of this key in a safe location${NC}"
echo -e "${RED}3. Never commit this key to version control${NC}"
echo -e "${RED}4. If you lose this key, you cannot unseal your OpenBao instance${NC}"
echo ""
echo -e "${GREEN}Next steps:${NC}"
echo "1. Start OpenBao: docker compose up -d"
echo "2. Initialize OpenBao (first time only): docker exec -it openbao bao operator init"
echo "3. OpenBao will automatically unseal using the key file"
echo ""
