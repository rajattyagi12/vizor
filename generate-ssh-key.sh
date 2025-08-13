#!/bin/bash

# Generate SSH key pair for backend services
ssh-keygen -t rsa -b 4096 -f ./backend-service-key -N "" -C "backend-service@vizor"

# Create the public key in the format needed for SFTPGo
echo "Generated SSH keys:"
echo "Private key: backend-service-key"
echo "Public key: backend-service-key.pub"

# Display the public key content
echo ""
echo "Public key content (save this for later):"
cat backend-service-key.pub

echo ""
echo "Base64 encoded private key for Kubernetes secret:"
base64 -w 0 backend-service-key