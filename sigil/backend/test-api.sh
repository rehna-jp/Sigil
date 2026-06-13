#!/bin/bash

# Sigil Backend API Test Script
# Tests all major endpoints

BASE_URL="http://localhost:3001"
TEST_ADDRESS="0x1234567890123456789012345678901234567890"

echo "🧪 Testing Sigil Backend API"
echo "================================"
echo ""

# Test 1: Health Check
echo "1️⃣  Testing /health..."
curl -s "$BASE_URL/health" | jq .
echo ""
echo ""

# Test 2: Get Contracts
echo "2️⃣  Testing /contracts..."
curl -s "$BASE_URL/contracts" | jq .contracts
echo ""
echo ""

# Test 3: Get Block Number
echo "3️⃣  Testing /block..."
curl -s "$BASE_URL/block" | jq .
echo ""
echo ""

# Test 4: Keeper Stats
echo "4️⃣  Testing /keeper/stats..."
curl -s "$BASE_URL/keeper/stats" | jq .
echo ""
echo ""

# Test 5: Get User Intents (should be empty for test address)
echo "5️⃣  Testing /intents/:address..."
curl -s "$BASE_URL/intents/$TEST_ADDRESS" | jq .
echo ""
echo ""

# Test 6: Get User Watchers (should be empty for test address)
echo "6️⃣  Testing /watchers/:address..."
curl -s "$BASE_URL/watchers/$TEST_ADDRESS" | jq .
echo ""
echo ""

# Test 7: Decompose (requires ANTHROPIC_API_KEY)
echo "7️⃣  Testing /decompose (requires ANTHROPIC_API_KEY)..."
curl -s -X POST "$BASE_URL/decompose" \
  -H "Content-Type: application/json" \
  -d "{
    \"text\": \"Swap 1 ETH for USDC\",
    \"userAddress\": \"$TEST_ADDRESS\"
  }" | jq .
echo ""
echo ""

echo "================================"
echo "✅ API tests complete!"
echo ""
echo "To test with real transactions:"
echo "1. Add ANTHROPIC_API_KEY to .env"
echo "2. Add PRIVATE_KEY to .env (with Arbitrum Sepolia ETH)"
echo "3. Run: curl -X POST $BASE_URL/decompose-and-submit -H 'Content-Type: application/json' -d '{\"text\":\"Swap 0.01 ETH for USDC\",\"userAddress\":\"YOUR_ADDRESS\"}'"
echo ""
