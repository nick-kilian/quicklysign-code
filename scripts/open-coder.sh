#!/bin/bash

PROJECT_ID="nick-coder"
REGION="us-west1"

CODER_URL=$(gcloud run services describe coder --platform managed --region "$REGION" --project "$PROJECT_ID" --format 'value(status.url)')

if [ -n "$CODER_URL" ]; then
    echo "🌍 Opening Coder: $CODER_URL"
    open "$CODER_URL"
else
    echo "❌ Coder service not found in Cloud Run."
fi
