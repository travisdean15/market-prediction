# Prediction Market Smart Contract

A decentralized prediction market built on the Stacks blockchain using Clarity smart contracts. Users can create markets on future events, place STX bets, and automatically receive winnings when markets resolve.

## 🎯 Features

### Core Features
- **Create Markets**: Anyone can create prediction markets for future events with up to 10 possible outcomes
- **Place Bets**: Bet STX tokens on different outcomes with a minimum bet of 1 STX
- **Secure Escrow**: All funds are safely locked in the smart contract until resolution
- **Automatic Distribution**: Winners receive proportional payouts based on their bet size
- **Admin Resolution**: Market creators or contract owner can resolve markets

### Advanced Features
- **Platform Fee System**: Configurable fees (0.5% default, up to 10%) with automated collection
- **Dynamic Odds Display**: Real-time odds calculation and payout ratio estimation
- **Dispute Mechanism**: 24-hour dispute period with community voting (5 STX minimum stake)
- **Market Categories**: 7 predefined categories with statistics tracking
- **User Statistics**: Comprehensive tracking with reputation tiers and performance metrics

## 🏗️ Architecture

### Core Components

- **Markets**: Each market has a unique ID, description, outcomes, end time, category, and resolution status
- **Bets**: Users can place one bet per market on their chosen outcome
- **Escrow System**: STX tokens are held securely until market resolution
- **Payout Calculation**: Winners split the total pool proportionally minus platform fees
- **Dispute System**: Community-driven resolution challenges with voting mechanism
- **Statistics Engine**: Real-time tracking of user performance and market analytics

### Smart Contract Functions

#### Public Functions

**Market Management**
- `create-market(description, outcomes, end-time, category)` - Create a new prediction market
- `place-bet(market-id, outcome, amount)` - Bet STX on a specific outcome
- `resolve-market(market-id, winning-outcome)` - Resolve market with winning outcome (admin only)
- `withdraw-winnings(market-id)` - Claim winnings after market resolution and dispute period

**Platform Administration**
- `set-platform-fee-rate(new-rate)` - Adjust platform fee rate (owner only)
- `collect-fees()` - Collect accumulated platform fees (owner only)  
- `collect-market-fees(market-id)` - Collect fees from specific market (owner only)

**Dispute System**
- `initiate-dispute(market-id, proposed-outcome, stake)` - Challenge market resolution
- `vote-on-dispute(market-id, support-dispute, vote-stake)` - Vote on ongoing dispute
- `resolve-dispute(market-id, uphold-dispute)` - Resolve dispute (owner only)

#### Read-Only Functions

**Market Information**
- `get-market(market-id)` - Get complete market details
- `get-bet(market-id, bettor)` - Check user's bet on specific market
- `get-outcome-total(market-id, outcome)` - Get total bets for specific outcome
- `get-next-market-id()` - Get current market ID counter
- `is-market-active(market-id)` - Check if market is still accepting bets
- `get-market-bettors(market-id)` - Get list of all bettors in market

**Odds and Calculations**
- `get-outcome-odds(market-id, outcome)` - Get current odds for specific outcome
- `calculate-payout-ratio(market-id, outcome, bet-amount)` - Preview payout ratio
- `calculate-potential-winnings(market-id, bettor)` - Calculate potential winnings

**Platform Analytics**
- `get-platform-fee-rate()` - Get current platform fee rate
- `get-accumulated-fees()` - Get total accumulated platform fees

**Category System**
- `get-category-stats(category)` - Get statistics for specific category
- `get-category-name(category)` - Get category name string
- `get-all-category-stats()` - Get comprehensive category analytics

**User Analytics**
- `get-user-stats(user)` - Get comprehensive user statistics
- `get-user-win-rate(user)` - Calculate user's win rate percentage
- `get-user-profit-loss(user)` - Get user's total profit or loss
- `get-user-reputation-tier(user)` - Get user's reputation tier (Newcomer to Legend)

**Dispute Information**
- `get-dispute(market-id)` - Get dispute details
- `get-dispute-vote(market-id, voter)` - Get user's dispute vote

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
  (list "Yes" "No")
  u1000000  ;; end time (block height or timestamp)
  u3)       ;; category: CATEGORY-CRYPTO
```

### Placing a Bet
```clarity
(contract-call? .prediction place-bet 
  u1        ;; market ID
  u0        ;; outcome (0 = Yes, 1 = No)
  u5000000) ;; 5 STX bet
```

### Getting Real-time Odds
```clarity
(contract-call? .prediction get-outcome-odds u1 u0) ;; Market 1, outcome 0
```

### Calculating Potential Payout
```clarity
(contract-call? .prediction calculate-payout-ratio u1 u0 u5000000) ;; 5 STX bet
```

### Resolving a Market
```clarity
(contract-call? .prediction resolve-market u1 u0) ;; Market 1, outcome 0 wins
```

### Initiating a Dispute
```clarity
(contract-call? .prediction initiate-dispute 
  u1        ;; market ID
  u1        ;; proposed correct outcome
  u5000000) ;; 5 STX dispute stake
```

### Withdrawing Winnings
```clarity
(contract-call? .prediction withdraw-winnings u1) ;; Withdraw from market 1
```

### Getting User Statistics
```clarity
(contract-call? .prediction get-user-stats 'ST1EXAMPLE...)
(contract-call? .prediction get-user-reputation-tier 'ST1EXAMPLE...)
```

## 💰 Economic Model

### Fee Structure
- **Platform Fee**: Configurable (0.5% default, 10% maximum)
- **Minimum Bet**: 1 STX (1,000,000 microSTX)
- **Dispute Stake**: 5 STX minimum
- **Payout Calculation**: `(user_bet / winning_pool) * (total_pool - platform_fees)`

### Market Categories
1. **Sports** - Sports events and competitions
2. **Politics** - Elections and political outcomes
3. **Cryptocurrency** - Crypto price predictions and events
4. **Entertainment** - Awards, releases, and pop culture
5. **Technology** - Tech announcements and developments
6. **Finance** - Economic indicators and market movements
7. **Other** - Miscellaneous predictions

### Reputation System
Users earn reputation points through:
- **Market Creation**: +10 points per market
- **Betting Activity**: +1 point per bet
- **Successful Predictions**: +1 point per STX won

**Reputation Tiers:**
- **Newcomer**: 0-24 points
- **Active**: 25-99 points  
- **Experienced**: 100-499 points
- **Expert**: 500-999 points
- **Legend**: 1000+ points

### Example Payout
If a market has:
- Total pool: 1000 STX
- Your bet: 100 STX on winning outcome
- Winning pool: 400 STX
- Platform fee: 5 STX (0.5%)

Your winnings: `(100 / 400) * (1000 - 5) = 248.75 STX`

## 🔒 Security Features

- **Fund Escrow**: All bets locked in contract until resolution
- **Access Control**: Only authorized users can resolve markets
- **Withdrawal Protection**: Users can only withdraw once per market
- **Input Validation**: Comprehensive checks on all user inputs with proper market ID validation
- **Time-based Controls**: Markets can only be resolved after end time
- **Dispute Period**: 24-hour window for challenging resolutions
- **One Bet Limit**: Users can only place one bet per market to prevent manipulation
- **Stake Requirements**: Minimum stakes required for disputes to prevent spam

## 🔧 Dispute Mechanism

### How Disputes Work
1. **Resolution**: Market creator or contract owner resolves market
2. **Dispute Period**: 24-hour window opens for challenges
3. **Challenge**: Any user can dispute with 5 STX minimum stake
4. **Community Voting**: Other users can vote on the dispute with STX stakes
5. **Final Resolution**: Contract owner makes final decision
6. **Outcome**: If dispute upheld, challenger gets stake back; if rejected, stake goes to platform

### Dispute Process
```clarity
;; 1. Initiate dispute
(contract-call? .prediction initiate-dispute market-id correct-outcome stake)

;; 2. Community voting
(contract-call? .prediction vote-on-dispute market-id support-dispute vote-stake)

;; 3. Final resolution (owner only)  
(contract-call? .prediction resolve-dispute market-id uphold-dispute)
```

## 🧪 Testing

The project includes comprehensive test coverage:

```bash
# Run all tests
npm test

# Run specific test file
npx vitest tests/prediction.test.ts

# Run with coverage
npm run test:report
```

## 📁 Project Structure

```
market_predicts/
├── contracts/
│   └── prediction.clar          # Main smart contract (947 lines)
├── tests/
│   └── prediction.test.ts       # Test suite
├── settings/
│   ├── Devnet.toml             # Development network config
│   ├── Testnet.toml            # Testnet config
│   └── Mainnet.toml            # Mainnet config
├── Clarinet.toml               # Project configuration
├── package.json                # Dependencies
├── tsconfig.json               # TypeScript config
└── vitest.config.js            # Test configuration
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

## 📊 Analytics and Monitoring

### Category Analytics
Track market performance across different categories:
- Total markets created per category
- Active markets count
- Total volume per category
- Category-specific statistics

### User Analytics  
Monitor user engagement and performance:
- Betting history and patterns
- Win/loss ratios and profitability
- Reputation scores and tier progression
- Market creation activity

### Platform Metrics
- Total platform fees collected
- Dispute resolution statistics  
- Market resolution accuracy
- Overall platform usage metrics

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Ensure all tests pass and no compiler warnings
6. Submit a pull request

## 📄 License

This project is licensed under the MIT License.

## ⚠️ Disclaimer

This is experimental software. Use at your own risk. Always test thoroughly before deploying to mainnet. The dispute mechanism and community voting features are designed for fairness but should be carefully evaluated in production environments.

## 🔄 Version History

- **v1.0.0**: Initial release with basic market functionality
- **v2.0.0**: Added platform fees, dynamic odds, disputes, categories, and user statistics
  - Platform Fee System with configurable rates
  - Real-time odds calculation and payout estimation
  - Community-driven dispute mechanism with 24hr periods
  - 7 market categories with comprehensive analytics
  - User reputation system with 5-tier progression
  - Enhanced security with comprehensive input validation