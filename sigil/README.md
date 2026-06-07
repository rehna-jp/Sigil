# Sigil — Persistent Intent Engine

Inscribe your financial intent once. It watches, reacts, and protects — autonomously.

Architecture

sigil/
├── contracts/          # Foundry project for Solidity smart contracts
├── backend/            # Node.js backend for AI decomposer + keeper service
├── frontend/           # Next.js 14 app with App Router for the dashboard
├── shared/             # Shared types, ABIs, and constants
├── .github/            # CI config
├── README.md
├── package.json        # Root workspace config
└── .env.example

How to run (local)

1. Install Foundry (for contracts):

```bash
curl -L https://foundry.paradigm.xyz | bash
export PATH="$HOME/.foundry/bin:$PATH"
foundryup
```

2. Contracts

```bash
cd sigil/contracts
forge install
forge build
forge test
```

3. Backend

```bash
cd sigil/backend
# install deps
npm install
# create .env from .env.example and set ANTHROPIC_API_KEY
npm run dev
```

4. Frontend

```bash
cd sigil/frontend
npm install
npm run dev
```

How it works (5 steps)

1. User writes a natural-language intent via the dashboard.
2. Frontend sends the text to the backend decomposer (Anthropic Claude).
3. Backend returns a structured Intent (segments + watchers).
4. Contracts execute immediate segments and register persistent watchers on-chain.
5. Keepers observe watchers and fire intents when conditions match.

Tech stack

- Contracts: Solidity, Foundry, OpenZeppelin, Chainlink
- Backend: Node.js, Express, Anthropic Claude, ethers v6
- Frontend: Next.js 14, Tailwind, wagmi/viem, RainbowKit

Team

- TBD

License

MIT
