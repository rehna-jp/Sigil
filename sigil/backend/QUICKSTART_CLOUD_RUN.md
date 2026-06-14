# Quick Start: Deploy to Google Cloud Run

Get your Sigil backend running on Google Cloud Run in 5 minutes.

## Prerequisites

- Google Cloud account (free tier available)
- gcloud CLI installed
- Your Groq API key

## Step 1: Install gcloud CLI

**Windows:**
Download and install from: https://cloud.google.com/sdk/docs/install#windows

**macOS/Linux:**
```bash
curl https://sdk.cloud.google.com | bash
exec -l $SHELL
```

## Step 2: Initialize gcloud

```bash
# Login
gcloud init

# Enable required APIs
gcloud services enable run.googleapis.com secretmanager.googleapis.com
```

## Step 3: Deploy (Automated)

```bash
cd sigil/backend
./deploy.sh
```

The script will:
1. Check if secrets exist (GROQ_API_KEY, etc.)
2. Prompt you to create them if missing
3. Build and deploy your container
4. Output your service URL

## Step 4: Test

```bash
# Get your service URL (from deploy output)
SERVICE_URL=https://sigil-backend-xxx-uc.a.run.app

# Test health
curl $SERVICE_URL/health

# Test AI decomposition
curl -X POST $SERVICE_URL/decompose \
  -H "Content-Type: application/json" \
  -d '{
    "text": "Swap 1 ETH for USDC",
    "userAddress": "0x1234567890123456789012345678901234567890"
  }'
```

## Step 5: Update Frontend

Update your frontend to use the Cloud Run URL:

```typescript
// frontend/.env.local
NEXT_PUBLIC_API_URL=https://sigil-backend-xxx-uc.a.run.app
```

## That's it! 🎉

Your backend is now running on Google Cloud Run with:
- ✅ Auto-scaling (0 to 10 instances)
- ✅ HTTPS enabled
- ✅ Global CDN
- ✅ Free tier eligible

### View Logs

```bash
gcloud run services logs tail sigil-backend --region us-central1
```

### Update Deployment

Make code changes, then:

```bash
cd sigil/backend
./deploy.sh
```

### Costs

Free tier includes:
- 2 million requests/month
- 360,000 GiB-seconds/month
- 180,000 vCPU-seconds/month

Typical usage: **$0-5/month**

---

**Troubleshooting:** See [DEPLOYMENT_CLOUD_RUN.md](./DEPLOYMENT_CLOUD_RUN.md) for detailed docs.
