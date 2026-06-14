#!/usr/bin/env bash
# bootstrap-gcp: one-time project preparation before `make deploy-control-plane`.
# Verifies auth, enables the required APIs. Terraform runs with YOUR
# Application Default Credentials — no bootstrap service account is needed.
set -euo pipefail

PROJECT_ID="${GCP_PROJECT_ID:-quicklysign-terraform-dev}"

echo "Bootstrapping GCP project: $PROJECT_ID"

if ! command -v gcloud >/dev/null 2>&1; then
  echo "ERROR: gcloud CLI not installed (https://cloud.google.com/sdk/docs/install)"
  exit 1
fi

if ! gcloud auth list --filter=status:ACTIVE --format='value(account)' | grep -q .; then
  echo "ERROR: no active gcloud account. Run: gcloud auth login"
  exit 1
fi

if ! gcloud projects describe "$PROJECT_ID" >/dev/null 2>&1; then
  echo "ERROR: project $PROJECT_ID not found or no access."
  exit 1
fi

if ! gcloud auth application-default print-access-token >/dev/null 2>&1; then
  echo "Terraform needs Application Default Credentials. Run:"
  echo "    gcloud auth application-default login"
  exit 1
fi

echo "Enabling APIs (idempotent)..."
gcloud services enable \
  compute.googleapis.com \
  sqladmin.googleapis.com \
  secretmanager.googleapis.com \
  iam.googleapis.com \
  cloudresourcemanager.googleapis.com \
  servicenetworking.googleapis.com \
  logging.googleapis.com \
  monitoring.googleapis.com \
  --project "$PROJECT_ID"

echo "Bootstrap complete. Next: make deploy-control-plane"
