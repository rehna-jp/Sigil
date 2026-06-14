# Deploying Sigil Backend to Google Cloud Run

This guide walks you through deploying the Sigil backend to Google Cloud Run.

## Prerequisites

1. **Google Cloud Account** - Sign up at https://cloud.google.com/
2. **Google Cloud SDK** - Install from https://cloud.google.com/sdk/docs/install
3. **Docker** - Install from https://docs.docker.com/get-docker/
4. **API Keys**:
   - Groq API Key (FREE from https://console.groq.com/)
   - Wallet Private Key (with Arbitrum Sepolia ETH)

## Initial Setup

### 1. Install Google Cloud CLI

**Windows:**
```powershell
# Download and run installer
# https://cloud.google.com/sdk/docs/install#windows
```

**macOS:**
```bash
curl https://sdk.cloud.google.com | bash
exec -l $SHELL
```

**Linux:**
```bash
curl https://sdk.cloud.google.com | bash
exec -l $SHELL
```

### 2. Initialize gcloud

```bash
# Login to your Google account
gcloud init

# Select or create a project
gcloud config set project YOUR_PROJECT_ID

# Enable required APIs
gcloud services enable \
  run.googleapis.com \
  cloudbuild.googleapis.com \
  secretmanager.googleapis.com \
  containerregistry.googleapis.com
```

### 3. Set Up Secrets

Store your API keys securely in Google Secret Manager:

```bash
# Create Groq API Key secret
echo -n "your_groq_api_key_here" | \
  gcloud secrets create GROQ_API_KEY \
  --data-file=-

# Create Private Key secret
echo -n "your_private_key_here" | \
  gcloud secrets create PRIVATE_KEY \
  --data-file=-

# Create RPC URL secret (or use default)
echo -n "https://sepolia-rollup.arbitrum.io/rpc" | \
  gcloud secrets create ARBITRUM_SEPOLIA_RPC_URL \
  --data-file=-
```

Verify secrets were created:
```bash
gcloud secrets list
```

## Deployment Methods

### Option 1: Deploy with gcloud (Quickest)

```bash
cd sigil/backend

# Deploy to Cloud Run
gcloud run deploy sigil-backend \
  --source . \
  --region us-central1 \
  --platform managed \
  --allow-unauthenticated \
  --set-env-vars PORT=8080 \
  --set-secrets GROQ_API_KEY=GROQ_API_KEY:latest,PRIVATE_KEY=PRIVATE_KEY:latest,ARBITRUM_SEPOLIA_RPC_URL=ARBITRUM_SEPOLIA_RPC_URL:latest \
  --memory 512Mi \
  --cpu 1 \
  --max-instances 10 \
  --timeout 300
```

This command will:
- Build your Docker container
- Push it to Google Container Registry
- Deploy to Cloud Run
- Set up environment variables from secrets

### Option 2: Manual Docker Build & Deploy

```bash
cd sigil/backend

# Set your project ID
export PROJECT_ID=your-project-id

# Build the container
docker build -t gcr.io/$PROJECT_ID/sigil-backend:latest .

# Configure Docker for GCR
gcloud auth configure-docker

# Push to Google Container Registry
docker push gcr.io/$PROJECT_ID/sigil-backend:latest

# Deploy to Cloud Run
gcloud run deploy sigil-backend \
  --image gcr.io/$PROJECT_ID/sigil-backend:latest \
  --region us-central1 \
  --platform managed \
  --allow-unauthenticated \
  --set-env-vars PORT=8080 \
  --set-secrets GROQ_API_KEY=GROQ_API_KEY:latest,PRIVATE_KEY=PRIVATE_KEY:latest,ARBITRUM_SEPOLIA_RPC_URL=ARBITRUM_SEPOLIA_RPC_URL:latest \
  --memory 512Mi \
  --cpu 1 \
  --max-instances 10 \
  --timeout 300
```

### Option 3: CI/CD with Cloud Build (Production)

Set up automatic deployments from GitHub:

```bash
# Connect your GitHub repository
gcloud builds triggers create github \
  --repo-name=Sigil \
  --repo-owner=rehna-jp \
  --branch-pattern=^main$ \
  --build-config=sigil/backend/cloudbuild.yaml

# Or trigger manually
gcloud builds submit --config cloudbuild.yaml ..
```

## Post-Deployment

### 1. Get Your Service URL

```bash
gcloud run services describe sigil-backend \
  --region us-central1 \
  --format 'value(status.url)'
```

Example output: `https://sigil-backend-abc123-uc.a.run.app`

### 2. Test Your Deployment

```bash
# Health check
curl https://YOUR_SERVICE_URL/health

# Test decomposition
curl -X POST https://YOUR_SERVICE_URL/decompose \
  -H "Content-Type: application/json" \
  -d '{
    "text": "Swap 1 ETH for USDC",
    "userAddress": "0x1234567890123456789012345678901234567890"
  }'

# Get contracts
curl https://YOUR_SERVICE_URL/contracts

# Keeper stats
curl https://YOUR_SERVICE_URL/keeper/stats
```

### 3. View Logs

```bash
# Stream logs
gcloud run services logs tail sigil-backend --region us-central1

# Or view in Cloud Console
echo "https://console.cloud.google.com/run/detail/us-central1/sigil-backend/logs"
```

## Configuration

### Environment Variables

Cloud Run automatically sets:
- `PORT` - Port to listen on (8080)
- Secrets are injected as environment variables

### Scaling

The default configuration:
- **Min instances:** 0 (scales to zero when idle)
- **Max instances:** 10
- **CPU:** 1 vCPU
- **Memory:** 512 MB
- **Timeout:** 300 seconds (5 minutes)

Adjust scaling:
```bash
gcloud run services update sigil-backend \
  --region us-central1 \
  --min-instances 1 \
  --max-instances 50 \
  --memory 1Gi \
  --cpu 2
```

### Auto-Start Keeper

To run the keeper service automatically:

```bash
# Update secret with AUTO_START_KEEPER
echo -n "true" | gcloud secrets create AUTO_START_KEEPER --data-file=-

# Update service to use the secret
gcloud run services update sigil-backend \
  --region us-central1 \
  --update-secrets AUTO_START_KEEPER=AUTO_START_KEEPER:latest
```

## Custom Domain (Optional)

Map a custom domain to your service:

```bash
# Verify domain ownership first in Cloud Console

# Map domain
gcloud run domain-mappings create \
  --service sigil-backend \
  --domain api.yourdomain.com \
  --region us-central1
```

## Costs

Cloud Run pricing (as of 2024):
- **CPU:** $0.00002400 per vCPU-second
- **Memory:** $0.00000250 per GiB-second
- **Requests:** $0.40 per million requests
- **Free tier:** 2 million requests/month, 360,000 GiB-seconds

Estimated monthly cost for moderate usage:
- ~10,000 requests/month: **$0.00** (free tier)
- ~100,000 requests/month: **~$2-5**
- ~1,000,000 requests/month: **~$10-20**

## Monitoring

### Set Up Uptime Checks

```bash
gcloud monitoring uptime create sigil-backend-health \
  --resource-type=uptime-url \
  --host=YOUR_SERVICE_URL \
  --path=/health \
  --period=60
```

### Metrics Dashboard

View in Cloud Console:
```
https://console.cloud.google.com/run/detail/us-central1/sigil-backend/metrics
```

Monitor:
- Request count
- Request latency
- Instance count
- Memory usage
- CPU utilization

## Troubleshooting

### Container fails to start

Check logs:
```bash
gcloud run services logs read sigil-backend --region us-central1 --limit 50
```

Common issues:
- Missing secrets
- Contract ABIs not copied
- Port mismatch (must use PORT env var)

### Out of memory errors

Increase memory:
```bash
gcloud run services update sigil-backend \
  --region us-central1 \
  --memory 1Gi
```

### Timeout errors

Increase timeout:
```bash
gcloud run services update sigil-backend \
  --region us-central1 \
  --timeout 600
```

### Test locally first

```bash
# Build container
docker build -t sigil-backend .

# Run locally
docker run -p 3001:3001 \
  -e GROQ_API_KEY=your_key \
  -e PRIVATE_KEY=your_key \
  -e PORT=3001 \
  sigil-backend

# Test
curl http://localhost:3001/health
```

## Security Best Practices

1. **Never commit secrets** - Use Secret Manager
2. **Enable authentication** if needed:
   ```bash
   gcloud run services update sigil-backend \
     --region us-central1 \
     --no-allow-unauthenticated
   ```
3. **Set up Cloud Armor** for DDoS protection
4. **Enable VPC** for private networking
5. **Use service accounts** with minimal permissions

## Updating Your Service

When you make code changes:

```bash
# Rebuild and deploy
cd sigil/backend
gcloud run deploy sigil-backend --source . --region us-central1

# Or with Cloud Build
gcloud builds submit --config cloudbuild.yaml ..
```

Cloud Run will:
- Build new container
- Deploy with zero downtime
- Gradually shift traffic to new version

## Rollback

If something goes wrong:

```bash
# List revisions
gcloud run revisions list --service sigil-backend --region us-central1

# Rollback to previous revision
gcloud run services update-traffic sigil-backend \
  --region us-central1 \
  --to-revisions REVISION_NAME=100
```

## Clean Up

To delete everything:

```bash
# Delete service
gcloud run services delete sigil-backend --region us-central1

# Delete secrets
gcloud secrets delete GROQ_API_KEY
gcloud secrets delete PRIVATE_KEY
gcloud secrets delete ARBITRUM_SEPOLIA_RPC_URL

# Delete container images
gcloud container images delete gcr.io/$PROJECT_ID/sigil-backend
```

## Next Steps

After deployment:

1. **Update frontend** - Point frontend API calls to Cloud Run URL
2. **Set up monitoring** - Cloud Monitoring + alerting
3. **Configure CORS** - If needed for frontend
4. **Add rate limiting** - Use Cloud Armor
5. **Set up CI/CD** - Automatic deployments from GitHub

---

## Support

- **Cloud Run Docs:** https://cloud.google.com/run/docs
- **Pricing Calculator:** https://cloud.google.com/products/calculator
- **Status:** https://status.cloud.google.com/

---

**Your persistent intent loop is ready for production!** 🚀
