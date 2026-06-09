#!/bin/bash
set -e

PROJECT_ID="nick-coder"
REGION="us-west1"

echo "🌟 Bootstrapping GCP Project: $PROJECT_ID..."

# 1. Enable APIs
gcloud services enable \
  compute.googleapis.com \
  run.googleapis.com \
  sqladmin.googleapis.com \
  secretmanager.googleapis.com \
  artifactregistry.googleapis.com \
  iam.googleapis.com \
  cloudresourcemanager.googleapis.com \
  vpcaccess.googleapis.com \
  servicenetworking.googleapis.com \
  --project "$PROJECT_ID"

echo "✅ APIs enabled."

# 2. Create Terraform Service Account if it doesn't exist
SA_NAME="coder-terraform"
SA_EMAIL="$SA_NAME@$PROJECT_ID.iam.gserviceaccount.com"

if ! gcloud iam service-accounts describe "$SA_EMAIL" --project "$PROJECT_ID" &>/dev/null; then
    echo "Creating service account: $SA_EMAIL..."
    gcloud iam service-accounts create "$SA_NAME" \
      --display-name "Coder Terraform SA" \
      --project "$PROJECT_ID"
else
    echo "✅ Service account $SA_EMAIL already exists."
fi

# 3. Grant Editor role (or more specific roles) to SA
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member "serviceAccount:$SA_EMAIL" \
  --role "roles/editor"

echo "✅ Bootstrap complete!"
