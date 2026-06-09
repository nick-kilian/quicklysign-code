# Operations Guide

## Bootstrap
1.  **GCP Project**: Ensure you have a project named `nick-coder`.
2.  **Initial Credentials**: Run `gcloud auth application-default login`.
3.  **Bootstrap Script**:
    ```bash
    ./scripts/bootstrap-gcp.sh
    ```
    This enables necessary APIs and creates the bootstrap service account.

## Deployment
1.  **Terraform**:
    ```bash
    cd infra/terraform
    terraform init
    terraform apply
    ```
2.  **Coder Template**:
    ```bash
    ./scripts/create-template.sh
    ```

## Workspace Usage

### Starting an Agent Task
Use `agent-run` to start a task that should keep the VM alive:
```bash
agent-run claude "refactor-api" --repo ~/src/quicklysign-api --ttl 4h
```

### Checking Status
```bash
agent-status.sh
```

### Resuming Work
If the VM stopped and restarted, use `worklane` to resume:
```bash
worklane refactor-api
```
Inside the session, you can run `claude --resume refactor-api`.

## Cost Management
- **Spot VMs**: Workspaces use Spot VMs to save ~60-91% vs on-demand.
- **Autostop**: Default autostop is 60 minutes.
- **Agent Bumping**: Only active agents extend the deadline.
- **Cloud SQL**: Uses a small instance; consider stopping it if not used for long periods (though Coder needs it to start).

## Troubleshooting
- **Logs**:
  - Watchdog: `~/.local/state/agent-watchdog.log`
  - Coder Agent: `/tmp/coder-agent.log`
- **Manual Extension**:
  - `coder schedule extend 1h`
