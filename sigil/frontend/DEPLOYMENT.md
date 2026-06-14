# Sigil Frontend Deployment Guide

## Prerequisites

1. A [Vercel account](https://vercel.com/signup)
2. Vercel CLI installed: `npm i -g vercel`
3. Backend deployed to Google Cloud Run (already done)
4. Smart contracts deployed to Arbitrum Sepolia (already done)

## Deployment Steps

### Option 1: Deploy via Vercel Dashboard (Recommended)

1. **Import the Repository**
   - Go to [Vercel Dashboard](https://vercel.com/dashboard)
   - Click "Add New Project"
   - Import your Git repository
   - Select the `sigil/frontend` directory as the root directory

2. **Configure Environment Variables**

   Add the following environment variables in the Vercel project settings:

   ```bash
   NEXT_PUBLIC_BACKEND_URL=https://sigil-backend-724136559213.us-central1.run.app
   NEXT_PUBLIC_ARBITRUM_SEPOLIA_RPC=https://sepolia-rollup.arbitrum.io/rpc
   NEXT_PUBLIC_INTENT_DECOMPOSER=0xDaf6B30C15a0Ce8501A685f0606154F517b8d62a
   NEXT_PUBLIC_WATCHER_REGISTRY=0xB3073A12EBD1ffE05B9Bd530A50625779AB8E93d
   NEXT_PUBLIC_TRIGGER_EXECUTOR=0xE80dd053081b941FBfF60eB8b105bBF4f971327a
   NEXT_PUBLIC_INTENT_ROUTER=0x2D514AB7E8C2F05FA82Bb4885de00Da933501022
   NEXT_PUBLIC_MOCK_PRICE_FEED=0xFBdcBBfCa2dC73348F7Cf9b1a572bbe5f4d0cCE3
   ```

3. **Configure Build Settings**
   - Framework Preset: Next.js
   - Root Directory: `sigil/frontend`
   - Build Command: `npm run build` (auto-detected)
   - Output Directory: `.next` (auto-detected)
   - Install Command: `npm install` (auto-detected)

4. **Deploy**
   - Click "Deploy"
   - Wait for the build to complete
   - Your app will be live at `https://your-project.vercel.app`

### Option 2: Deploy via Vercel CLI

1. **Navigate to frontend directory**
   ```bash
   cd sigil/frontend
   ```

2. **Login to Vercel**
   ```bash
   vercel login
   ```

3. **Deploy to preview**
   ```bash
   vercel
   ```

4. **Set environment variables**
   ```bash
   vercel env add NEXT_PUBLIC_BACKEND_URL production
   # Enter: https://sigil-backend-724136559213.us-central1.run.app

   vercel env add NEXT_PUBLIC_ARBITRUM_SEPOLIA_RPC production
   # Enter: https://sepolia-rollup.arbitrum.io/rpc

   vercel env add NEXT_PUBLIC_INTENT_DECOMPOSER production
   # Enter: 0xDaf6B30C15a0Ce8501A685f0606154F517b8d62a

   vercel env add NEXT_PUBLIC_WATCHER_REGISTRY production
   # Enter: 0xB3073A12EBD1ffE05B9Bd530A50625779AB8E93d

   vercel env add NEXT_PUBLIC_TRIGGER_EXECUTOR production
   # Enter: 0xE80dd053081b941FBfF60eB8b105bBF4f971327a

   vercel env add NEXT_PUBLIC_INTENT_ROUTER production
   # Enter: 0x2D514AB7E8C2F05FA82Bb4885de00Da933501022

   vercel env add NEXT_PUBLIC_MOCK_PRICE_FEED production
   # Enter: 0xFBdcBBfCa2dC73348F7Cf9b1a572bbe5f4d0cCE3
   ```

5. **Deploy to production**
   ```bash
   vercel --prod
   ```

## Post-Deployment

### Verify Deployment

1. Open your deployed app URL
2. Connect your wallet (MetaMask with Arbitrum Sepolia)
3. Try casting a sigil with one of the preset intents
4. Check that:
   - AI decomposition works (backend API connected)
   - Transaction submission works (contracts connected)
   - You see two transactions: `submitDecomposition` and `executeSegments`

### Monitor Backend

Check backend logs to verify frontend requests:
```bash
gcloud logs tail --project=sigil-499403 --filter="resource.labels.service_name=sigil-backend"
```

## Environment Variables Reference

| Variable | Description | Value |
|----------|-------------|-------|
| `NEXT_PUBLIC_BACKEND_URL` | Sigil backend API endpoint | `https://sigil-backend-724136559213.us-central1.run.app` |
| `NEXT_PUBLIC_ARBITRUM_SEPOLIA_RPC` | Arbitrum Sepolia RPC URL | `https://sepolia-rollup.arbitrum.io/rpc` |
| `NEXT_PUBLIC_INTENT_DECOMPOSER` | IntentDecomposer contract address | `0xDaf6B30C15a0Ce8501A685f0606154F517b8d62a` |
| `NEXT_PUBLIC_WATCHER_REGISTRY` | WatcherRegistry contract address | `0xB3073A12EBD1ffE05B9Bd530A50625779AB8E93d` |
| `NEXT_PUBLIC_TRIGGER_EXECUTOR` | TriggerExecutor contract address | `0xE80dd053081b941FBfF60eB8b105bBF4f971327a` |
| `NEXT_PUBLIC_INTENT_ROUTER` | IntentRouter contract address | `0x2D514AB7E8C2F05FA82Bb4885de00Da933501022` |
| `NEXT_PUBLIC_MOCK_PRICE_FEED` | MockPriceFeed contract address | `0xFBdcBBfCa2dC73348F7Cf9b1a572bbe5f4d0cCE3` |

## Troubleshooting

### Build Failures

**Error: Module not found**
```bash
# Solution: Ensure all dependencies are in package.json
npm install
```

**Error: Environment variable not defined**
```bash
# Solution: Check that all NEXT_PUBLIC_* variables are set in Vercel dashboard
```

### Runtime Issues

**Error: Failed to connect to backend**
- Verify `NEXT_PUBLIC_BACKEND_URL` is correct
- Check backend logs: `gcloud logs tail --project=sigil-499403 --filter="resource.labels.service_name=sigil-backend"`
- Ensure backend allows unauthenticated requests (already configured)

**Error: Contract not found**
- Verify contract addresses in environment variables match deployed contracts
- Check you're connected to Arbitrum Sepolia (Chain ID: 421614)

**Error: Transaction reverted**
- Check wallet has ETH on Arbitrum Sepolia
- Verify contract addresses are correct
- Check backend logs for AI decomposition errors

## Custom Domain (Optional)

1. Go to Vercel Dashboard → Your Project → Settings → Domains
2. Add your custom domain
3. Update DNS records as instructed
4. Wait for SSL certificate provisioning

## Continuous Deployment

Vercel automatically redeploys when you push to your main branch. To configure:

1. Go to Project Settings → Git
2. Select production branch (usually `main`)
3. Enable automatic deployments from Git
4. Optionally set up preview deployments for pull requests

## Rollback

If you need to rollback to a previous deployment:

1. Go to Vercel Dashboard → Your Project → Deployments
2. Find the previous working deployment
3. Click "..." → "Promote to Production"

## Additional Resources

- [Vercel Next.js Documentation](https://vercel.com/docs/frameworks/nextjs)
- [Environment Variables Guide](https://vercel.com/docs/environment-variables)
- [Custom Domains](https://vercel.com/docs/custom-domains)
