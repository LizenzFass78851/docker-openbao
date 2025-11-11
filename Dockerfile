# OpenBao Dockerfile with persistent storage
FROM quay.io/openbao/openbao:latest

# Set environment variables
ENV VAULT_ADDR=http://127.0.0.1:8200
ENV OPENBAO_ADDR=http://127.0.0.1:8200
ENV SKIP_SETCAP=true

# Create directories for data and configuration
RUN mkdir -p /openbao/data /openbao/config /openbao/logs

# Copy configuration file
COPY config.hcl /openbao/config/config.hcl

# Expose OpenBao ports
# 8200: API/UI port
# 8201: Cluster communication port
EXPOSE 8200 8201

# Set working directory
WORKDIR /openbao

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:8200/v1/sys/health || exit 1

# Run OpenBao server
ENTRYPOINT ["bao"]
CMD ["server", "-config=/openbao/config/config.hcl"]
