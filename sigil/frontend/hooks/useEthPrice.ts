'use client';

import { useEffect, useState } from 'react';
import { useReadContracts, useAccount } from 'wagmi';
import { CONTRACTS } from '../lib/constants';
import { MockPriceFeedABI } from '../lib/contracts';

const ETH_USD_FEED = '0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165'; // Chainlink Arb Sepolia ETH/USD

export function useEthPrice() {
  const { isConnected, chain } = useAccount();
  const [restEthPrice, setRestEthPrice] = useState<number | null>(null);

  const { data: priceData } = useReadContracts({
    contracts: [
      {
        address: ETH_USD_FEED as `0x${string}`,
        abi: MockPriceFeedABI,
        functionName: 'latestRoundData',
      },
    ],
    query: {
      enabled: !isConnected || chain?.id === 421614,
      refetchInterval: 30_000,
    },
  });

  const onChainPrice = priceData?.[0]?.status === 'success'
    ? Number((priceData[0].result as readonly [bigint, bigint, bigint, bigint, bigint])[1]) / 1e8
    : null;

  useEffect(() => {
    if (onChainPrice === null) {
      const fetchPrice = async () => {
        try {
          const res = await fetch('https://min-api.cryptocompare.com/data/price?fsym=ETH&tsyms=USD');
          const data = await res.json();
          if (data && typeof data.USD === 'number') {
            setRestEthPrice(data.USD);
          }
        } catch (err) {
          console.error('Failed to fetch fallback price', err);
        }
      };
      fetchPrice();
      const interval = setInterval(fetchPrice, 30_000);
      return () => clearInterval(interval);
    }
  }, [onChainPrice]);

  return onChainPrice ?? restEthPrice ?? 3750;
}
