# QuicklySign Coder Environment

This repo contains the infrastructure and Coder templates for the QuicklySign development environment on GCP.

## Structure

- `docs/`: Architecture, Operations, Idle Detection, and Security documentation.
- `infra/terraform/`: GCP Infrastructure (Cloud Run, Cloud SQL, VPC).
- `coder/templates/`: Coder Terraform templates for workspaces.
- `scripts/`: Deployment and bootstrap helpers.

## Prerequisites

- [Terraform](https://www.terraform.io/downloads.html)
- [gcloud CLI](https://cloud.google.com/sdk/docs/install)
- [Coder CLI](https://coder.com/docs/coder-oss/latest/install)

## Quick Start

1.  **Bootstrap GCP**:
    ```bash
    ./scripts/bootstrap-gcp.sh
    ```
2.  **Deploy Control Plane**:
    ```bash
    cd infra/terraform
    terraform init
    terraform apply
    ```
3.  **Deploy Coder Template**:
    ```bash
    ./scripts/create-template.sh
    ```
4.  **Open Coder**:
    ```bash
    ./scripts/open-coder.sh
    ```

## Agent-Aware Idle Detection

Workspaces include custom logic to keep the VM alive while `claude` or `codex` agents are working.

- Use `agent-run` to start a session.
- Use `agent-status` to see session health.
- Use `worklane` to attach to a session.

See `docs/idle-detection.md` for details.
