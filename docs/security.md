# Security Design

## 1. Identity & Access
- **Service Accounts**:
  - `coder-control-plane`: Minimal permissions to talk to Cloud SQL and Secret Manager.
  - `coder-workspace`: Minimal permissions to access Artifact Registry and Secret Manager.
- **Coder Authentication**: Coder should be configured with OIDC (Google) or standard username/password (initially).

## 2. Secrets Management
- **Secret Manager**: All sensitive values (DB passwords, GitHub tokens, Coder session tokens) are stored in GCP Secret Manager.
- **Terraform Integration**: Terraform retrieves secret versions to inject into Cloud Run environment variables or Coder configuration.

## 3. Network Security
- **Cloud Run Ingress**: Set to `allow-all` (public) since Coder handles its own authentication.
- **Workspace Access**:
  - No public SSH ports are opened by default.
  - Access is via `coder ssh` (which uses a relay) or the Coder Web Terminal.
- **Database**: Cloud SQL uses Private IP if possible (via VPC Peering/Private Service Connect) or is restricted to the Cloud Run service account.

## 4. GitHub & Agent Credentials
- **SSH Keys**: Users are encouraged to use `gh auth` or mount their own SSH keys into the workspace.
- **Claude/Codex**: Credentials should be provided via environment variables in the workspace, ideally pulled from Secret Manager or configured in the Coder Template as secrets.

## 5. Secret Rotation
- Regularly update secrets in Secret Manager.
- Redeploy Cloud Run services to pick up new versions of environment variables.
- Workspace VMs pick up new values on restart (if the template pulls from Secret Manager at boot).
