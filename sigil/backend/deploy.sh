#!/bin/bash

# Sigil Backend - Google Cloud Run Deployment Script

set -e

echo "🚀 Deploying Sigil Backend to Google Cloud Run"
echo "================================================"
echo ""

# Check if gcloud is installed
if ! command -v gcloud &> /dev/null; then
    echo "❌ Error: gcloud CLI is not installed"
    echo "Please install from: https://cloud.google.com/sdk/docs/install"
    exit 1
fi

# Get project ID
PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
if [ -z "$PROJECT_ID" ]; then
    echo "❌ Error: No GCP project configured"
    echo "Run: gcloud init"
    exit 1
fi

echo "📦 Project ID: $PROJECT_ID"
echo ""

# Check if secrets exist
echo "🔐 Checking secrets..."
SECRETS=$(gcloud secrets list --format="value(name)" 2>/dev/null)

if ! echo "$SECRETS" | grep -q "GROQ_API_KEY"; then
    echo "⚠️  GROQ_API_KEY secret not found"
    read -p "Enter your Groq API key: " GROQ_KEY
    echo -n "$GROQ_KEY" | gcloud secrets create GROQ_API_KEY --data-file=-
    echo "✅ Created GROQ_API_KEY secret"
fi

if ! echo "$SECRETS" | grep -q "ARBITRUM_SEPOLIA_RPC_URL"; then
    echo "⚠️  ARBITRUM_SEPOLIA_RPC_URL secret not found"
    RPC_URL="https://sepolia-rollup.arbitrum.io/rpc"
    echo -n "$RPC_URL" | gcloud secrets create ARBITRUM_SEPOLIA_RPC_URL --data-file=-
    echo "✅ Created ARBITRUM_SEPOLIA_RPC_URL secret"
fi

if ! echo "$SECRETS" | grep -q "PRIVATE_KEY"; then
    echo "⚠️  PRIVATE_KEY secret not found (optional for deployment)"
    read -p "Do you want to add a private key now? (y/n): " ADD_KEY
    if [ "$ADD_KEY" = "y" ]; then
        read -p "Enter your private key: " PRIV_KEY
        echo -n "$PRIV_KEY" | gcloud secrets create PRIVATE_KEY --data-file=-
        echo "✅ Created PRIVATE_KEY secret"
    else
        echo "⏭️  Skipping private key (intent submission will not work)"
    fi
fi

echo ""
echo "🔨 Building and deploying..."
echo ""

# Deploy to Cloud Run
gcloud run deploy sigil-backend \
  --source . \
  --region us-central1 \
  --platform managed \
  --allow-unauthenticated \
  --set-env-vars PORT=8080 \
  --update-secrets GROQ_API_KEY=GROQ_API_KEY:latest,ARBITRUM_SEPOLIA_RPC_URL=ARBITRUM_SEPOLIA_RPC_URL:latest \
  --memory 512Mi \
  --cpu 1 \
  --max-instances 10 \
  --min-instances 0 \
  --timeout 300 \
  --concurrency 80

# Add PRIVATE_KEY if it exists
if echo "$SECRETS" | grep -q "PRIVATE_KEY"; then
    gcloud run services update sigil-backend \
      --region us-central1 \
      --update-secrets PRIVATE_KEY=PRIVATE_KEY:latest
fi

echo ""
echo "✅ Deployment complete!"
echo ""

# Get service URL
SERVICE_URL=$(gcloud run services describe sigil-backend \
  --region us-central1 \
  --format 'value(status.url)')

echo "🌐 Service URL: $SERVICE_URL"
echo ""
echo "📡 Test your deployment:"
echo "  Health: curl $SERVICE_URL/health"
echo "  Contracts: curl $SERVICE_URL/contracts"
echo ""
echo "📊 View logs:"
echo "  gcloud run services logs tail sigil-backend --region us-central1"
echo ""
echo "🔗 Cloud Console:"
echo "  https://console.cloud.google.com/run/detail/us-central1/sigil-backend"
echo ""
