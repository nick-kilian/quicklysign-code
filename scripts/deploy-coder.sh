#!/usr/bin/env bash
# deploy-coder: terraform apply for the control plane, then print next steps.
set -euo pipefail

cd "$(dirname "$0")/../infra/terraform"

terraform init -input=false
terraform apply

IP=$(terraform output -raw control_plane_ip)
URL=$(terraform output -raw coder_url)
HOSTNAME=${URL#https://}

cat <<EOF

==========================================================
Control plane deployed.

1. Create this DNS record (required before TLS can issue):

     $HOSTNAME.   A   $IP

2. Wait a minute or two for the VM bootstrap + Let's Encrypt, then open:

     $URL

   The first visit creates the admin account.

3. Log in the CLI and push the workspace template:

     coder login $URL
     make create-template
==========================================================
EOF
