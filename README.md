# Prediction Market Smart Contract

A decentralized prediction market built on the Stacks blockchain using Clarity smart contracts. Users can create markets on future events, place STX bets, and automatically receive winnings when markets resolve.

## 🎯 Features

- **Create Markets**: Anyone can create prediction markets for future events with up to 10 possible outcomes
- **Place Bets**: Bet STX tokens on different outcomes with a minimum bet of 1 STX
- **Secure Escrow**: All funds are safely locked in the smart contract until resolution
- **Automatic Distribution**: Winners receive proportional payouts based on their bet size
- **Admin Resolution**: Market creators or contract owner can resolve markets
- **Platform Fees**: Built-in 0.5% platform fee mechanism

## 🏗️ Architecture

### Core Components

- **Markets**: Each market has a unique ID, title, description, end time, and possible outcomes
- **Bets**: Users can place multiple bets on different outcomes within the same market
- **Escrow System**: STX tokens are held securely until market resolution
- **Payout Calculation**: Winners split the total pool proportionally minus platform fees

### Smart Contract Functions

#### Public Functions
- `create-market()` - Create a new prediction market
- `place-bet()` - Bet STX on a specific outcome
- `resolve-market()` - Resolve market with winning outcome (admin only)
- `withdraw-winnings()` - Claim winnings after market resolution
- `collect-fees()` - Collect platform fees (contract owner only)

#### Read-Only Functions
- `get-market()` - Get market details
- `get-user-bet()` - Check user's bet on specific outcome
- `calculate-potential-winnings()` - Preview potential payout
- `has-withdrawn()` - Check if user has already withdrawn

## 🚀 Getting Started

### Prerequisites

- [Clarinet](https://github.com/hirosystems/clarinet) - Stacks development framework
- Node.js and npm
- Stacks wallet for testing

### Installation

1. Clone the repository:
```bash
git clone https://github.com/travisdean15/market-prediction.git
cd market-prediction/market_predicts
```

2. Install dependencies:
```bash
npm install
```

3. Run tests:
```bash
npm test
```

4. Deploy locally:
```bash
clarinet integrate
```

## 📖 Usage Examples

### Creating a Market
```clarity
(contract-call? .prediction create-market 
  "Will Bitcoin reach $100k by 2025?" 
  "Prediction market for Bitcoin price milestone"
  u1000000  ;; end block height
  u2)       ;; 2 outcomes: Yes/No
```

### Placing a Bet
```clarity
(contract-call? .prediction place-bet 
  u1        ;; market ID
  u0        ;; outcome (0 = Yes, 1 = No)
  u5000000) ;; 5 STX bet
```

### Resolving a Market
```clarity
(contract-call? .prediction resolve-market u1 u0) ;; Market 1, outcome 0 wins
```

### Withdrawing Winnings
```clarity
(contract-call? .prediction withdraw-winnings u1) ;; Withdraw from market 1
```

## 💰 Economic Model

### Fee Structure
- **Platform Fee**: 0.5% of total pool
- **Minimum Bet**: 1 STX
- **Payout Calculation**: `(user_bet / winning_pool) * (total_pool - fees)`

### Example Payout
If a market has:
- Total pool: 1000 STX
- Your bet: 100 STX on winning outcome
- Winning pool: 400 STX
- Platform fee: 5 STX

Your winnings: `(100 / 400) * (1000 - 5) = 248.75 STX`

## 🔒 Security Features

- **Fund Escrow**: All bets locked in contract until resolution
- **Access Control**: Only authorized users can resolve markets
- **Withdrawal Protection**: Users can only withdraw once per market
- **Input Validation**: Comprehensive checks on all user inputs
- **Time-based Controls**: Markets can only be resolved after end time

## 🧪 Testing

The project includes comprehensive test coverage:

```bash
# Run all tests
npm test

# Run specific test file
npx vitest tests/prediction.test.ts
```

## 📁 Project Structure

```
market_predicts/
├── contracts/
│   └── prediction.clar          # Main smart contract
├── tests/
│   └── prediction.test.ts       # Test suite
├── settings/
│   ├── Devnet.toml             # Development network config
│   ├── Testnet.toml            # Testnet config
│   └── Mainnet.toml            # Mainnet config
├── Clarinet.toml               # Project configuration
├── package.json                # Dependencies
└── tsconfig.json               # TypeScript config
```

## 🌐 Deployment

### Testnet Deployment
1. Configure your Stacks wallet
2. Update `settings/Testnet.toml` with your deployment address
3. Deploy using Clarinet:
```bash
clarinet deployments apply -p testnet
```

### Mainnet Deployment
1. Ensure thorough testing on testnet
2. Update `settings/Mainnet.toml`
3. Deploy to mainnet:
```bash
clarinet deployments apply -p mainnet
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License.

## ⚠️ Disclaimer

This is experimental software. Use at your own risk. Always test thoroughly before deploying to mainnet.
