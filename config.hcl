# OpenBao Configuration File
# Storage configuration using file backend for persistent data
storage "file" {
  path = "/openbao/data"
}

# Auto-unseal configuration using static key
# The key file will be automatically generated on first run
seal "static" {
  current_key_id = "openbao-unseal-key-v1"
  current_key    = "file:///openbao/secrets/unseal.key"
}

# HTTP listener configuration
listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = 1

  # For production, enable TLS:
  # tls_disable = 0
  # tls_cert_file = "/openbao/certs/cert.pem"
  # tls_key_file = "/openbao/certs/key.pem"
}

# API address for this node
api_addr = "http://0.0.0.0:8200"

# Cluster address for node communication
cluster_addr = "http://0.0.0.0:8201"

# Disable memory swap to prevent secrets from being written to disk
disable_mlock = true

# UI configuration
ui = true

# Log level (trace, debug, info, warn, error)
log_level = "info"
