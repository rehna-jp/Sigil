/**
 * AI Intent Decomposition Service
 * Uses Groq (Llama 3.1) to parse natural language into structured intent segments and watchers
 */

import Groq from 'groq-sdk';
import { ethers } from 'ethers';
import {
  SegmentType,
  WatcherType,
  ComparisonOp,
  AIDecompositionRequest,
  AIDecomposedIntent,
  Segment,
  WatcherConfig,
  PriceParams,
  TimeParams
} from '../contracts/types';

export class IntentDecomposerService {
  private groq: Groq;

  constructor(apiKey: string) {
    this.groq = new Groq({ apiKey });
  }

  /**
   * Decompose natural language intent into structured segments and watchers
   */
  async decomposeIntent(request: AIDecompositionRequest): Promise<AIDecomposedIntent> {
    const systemPrompt = this.getSystemPrompt();
    const userPrompt = this.buildDecompositionPrompt(request);

    const completion = await this.groq.chat.completions.create({
      model: 'llama-3.3-70b-versatile', // Latest Llama model (Dec 2024)
      messages: [
        {
          role: 'system',
          content: systemPrompt
        },
        {
          role: 'user',
          content: userPrompt
        }
      ],
      temperature: 0.2,
      max_tokens: 2000,
      response_format: { type: 'json_object' } // Force JSON response
    });

    // Extract JSON from Groq's response
    const content = completion.choices[0]?.message?.content;
    if (!content) {
      throw new Error('No response from Groq');
    }

    try {
      const parsed = JSON.parse(content);
      return this.validateAndNormalize(parsed);
    } catch (error) {
      console.error('Failed to parse Groq response:', content);
      throw new Error('Invalid JSON response from AI model');
    }
  }

  /**
   * System prompt for Groq
   */
  private getSystemPrompt(): string {
    return `You are Sigil AI, an expert at decomposing DeFi user intents into structured execution plans.

Your task is to analyze natural language DeFi intents and break them down into:
1. **Immediate Segments**: Atomic on-chain actions to execute now (swaps, deposits, withdraws, etc.)
2. **Persistent Watchers**: Conditions to monitor that trigger future actions (price, time, risk, governance)

IMPORTANT RULES:
- Segments must be executable atomic actions
- Watchers create NEW intents when triggered (this is how the loop closes)
- Be conservative with amounts and use safe defaults
- Always include expiry times for watchers (max 365 days)
- Use standard protocols: Uniswap V3 for swaps, Aave V3 for lending
- For price watchers, use realistic thresholds based on current market

Available Segment Types:
- SWAP: Token swaps on DEXes
- DEPOSIT: Deposit into lending/yield protocols
- WITHDRAW: Withdraw from protocols
- HEDGE: Open hedge positions (perps, options)
- CUSTOM: Custom protocol interactions

Available Watcher Types:
- PRICE: Monitor price feeds (Chainlink oracles)
- TIME: Interval-based triggers (rebalancing, DCA)
- RISK: Monitor TVL drops, upgrades, exploits
- GOVERNANCE: Watch for governance proposals

CRITICAL: You MUST respond with valid JSON only. No markdown, no code blocks, just pure JSON.

Output Format (JSON):
{
  "segments": [
    {
      "type": "SWAP" | "DEPOSIT" | "WITHDRAW" | "HEDGE" | "CUSTOM",
      "protocol": "uniswap-v3" | "aave-v3" | "gmx-v2" | etc,
      "description": "Human readable description",
      "data": {
        // Protocol-specific parameters
        // SWAP: { tokenIn, tokenOut, amountIn, minAmountOut, fee }
        // DEPOSIT: { asset, amount }
        // WITHDRAW: { asset, amount }
      }
    }
  ],
  "watchers": [
    {
      "type": "PRICE" | "TIME" | "RISK" | "GOVERNANCE",
      "description": "What this watcher monitors",
      "params": {
        // Type-specific parameters
        // PRICE: { pair: "ETH/USD", threshold: "3500", comparison: "LT" }
        // TIME: { interval: "86400" (seconds), maxTriggers: "0" (unlimited) }
      }
    }
  ],
  "reasoning": "Brief explanation of the decomposition strategy"
}`;
  }

  /**
   * Build prompt for specific user intent
   */
  private buildDecompositionPrompt(request: AIDecompositionRequest): string {
    let prompt = `Decompose the following DeFi intent:\n\n"${request.userInput}"\n\n`;

    prompt += `User Address: ${request.userAddress}\n\n`;

    if (request.context?.balances) {
      prompt += `User Balances:\n`;
      for (const [token, balance] of Object.entries(request.context.balances)) {
        prompt += `  ${token}: ${balance}\n`;
      }
      prompt += '\n';
    }

    prompt += `Return your analysis as a JSON object following the exact format specified in your system prompt. Remember: respond with ONLY valid JSON, no markdown formatting.`;

    return prompt;
  }

  /**
   * Validate and normalize Groq's output
   */
  private validateAndNormalize(parsed: any): AIDecomposedIntent {
    if (!parsed.segments || !Array.isArray(parsed.segments)) {
      throw new Error('Invalid decomposition: missing or invalid segments');
    }

    if (!parsed.watchers) {
      parsed.watchers = [];
    }

    // Normalize segment types
    parsed.segments = parsed.segments.map((seg: any) => ({
      ...seg,
      type: this.parseSegmentType(seg.type)
    }));

    // Normalize watcher types
    parsed.watchers = parsed.watchers.map((w: any) => ({
      ...w,
      type: this.parseWatcherType(w.type)
    }));

    return parsed as AIDecomposedIntent;
  }

  /**
   * Parse segment type string to enum
   */
  private parseSegmentType(type: string): SegmentType {
    const typeMap: Record<string, SegmentType> = {
      'SWAP': SegmentType.SWAP,
      'DEPOSIT': SegmentType.DEPOSIT,
      'WITHDRAW': SegmentType.WITHDRAW,
      'HEDGE': SegmentType.HEDGE,
      'CUSTOM': SegmentType.CUSTOM
    };

    return typeMap[type.toUpperCase()] ?? SegmentType.CUSTOM;
  }

  /**
   * Parse watcher type string to enum
   */
  private parseWatcherType(type: string): WatcherType {
    const typeMap: Record<string, WatcherType> = {
      'PRICE': WatcherType.PRICE,
      'TIME': WatcherType.TIME,
      'RISK': WatcherType.RISK,
      'GOVERNANCE': WatcherType.GOVERNANCE
    };

    return typeMap[type.toUpperCase()] ?? WatcherType.PRICE;
  }

  /**
   * Encode segment data for on-chain submission
   */
  encodeSegment(segment: AIDecomposedIntent['segments'][0], protocol: string): Segment {
    let callData: string;

    switch (segment.type) {
      case SegmentType.SWAP:
        // Encode UniswapV3 swap parameters
        callData = ethers.AbiCoder.defaultAbiCoder().encode(
          ['address', 'address', 'uint24', 'uint256', 'uint256'],
          [
            segment.data.tokenIn,
            segment.data.tokenOut,
            segment.data.fee || 3000, // Default to 0.3% fee
            ethers.parseEther(segment.data.amountIn || '0'),
            ethers.parseEther(segment.data.minAmountOut || '0')
          ]
        );
        break;

      case SegmentType.DEPOSIT:
        // Encode Aave deposit parameters
        callData = ethers.AbiCoder.defaultAbiCoder().encode(
          ['address', 'uint256'],
          [
            segment.data.asset,
            ethers.parseEther(segment.data.amount || '0')
          ]
        );
        break;

      case SegmentType.WITHDRAW:
        // Encode Aave withdraw parameters
        callData = ethers.AbiCoder.defaultAbiCoder().encode(
          ['address', 'uint256'],
          [
            segment.data.asset,
            ethers.parseEther(segment.data.amount || '0')
          ]
        );
        break;

      default:
        callData = '0x';
    }

    return {
      segmentType: segment.type,
      targetProtocol: protocol,
      callData,
      value: 0n
    };
  }

  /**
   * Encode watcher parameters for on-chain registration
   */
  encodeWatcher(watcher: AIDecomposedIntent['watchers'][0], expiryDays: number = 30): WatcherConfig {
    let parameters: string;
    const expiry = BigInt(Math.floor(Date.now() / 1000) + expiryDays * 24 * 60 * 60);

    switch (watcher.type) {
      case WatcherType.PRICE:
        // Encode price watcher parameters
        const comparison = watcher.params.comparison === 'GT' ? ComparisonOp.GT :
                          watcher.params.comparison === 'LT' ? ComparisonOp.LT :
                          watcher.params.comparison === 'GTE' ? ComparisonOp.GTE :
                          ComparisonOp.LTE;

        const priceParams: PriceParams = {
          priceFeed: watcher.params.priceFeed || ethers.ZeroAddress,
          threshold: ethers.parseUnits(watcher.params.threshold, 8), // Chainlink uses 8 decimals
          comparison
        };

        parameters = ethers.AbiCoder.defaultAbiCoder().encode(
          ['address', 'int256', 'uint8'],
          [priceParams.priceFeed, priceParams.threshold, priceParams.comparison]
        );
        break;

      case WatcherType.TIME:
        // Encode time watcher parameters
        const timeParams: TimeParams = {
          interval: BigInt(watcher.params.interval || 86400), // Default 1 day
          nextTrigger: BigInt(Math.floor(Date.now() / 1000) + Number(watcher.params.interval || 86400)),
          maxTriggers: BigInt(watcher.params.maxTriggers || 0), // 0 = unlimited
          triggerCount: 0n
        };

        parameters = ethers.AbiCoder.defaultAbiCoder().encode(
          ['uint256', 'uint256', 'uint256', 'uint256'],
          [timeParams.interval, timeParams.nextTrigger, timeParams.maxTriggers, timeParams.triggerCount]
        );
        break;

      default:
        parameters = '0x';
    }

    return {
      watcherType: watcher.type,
      parameters,
      triggerAction: '0x', // Will be filled by the contract when triggered
      expiry
    };
  }
}
