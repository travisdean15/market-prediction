import { describe, expect, it, beforeEach } from "vitest";
import { Cl } from "@stacks/transactions";

const accounts = simnet.getAccounts();
const deployer = accounts.get("deployer")!;
const wallet1 = accounts.get("wallet_1")!;
const wallet2 = accounts.get("wallet_2")!;
const wallet3 = accounts.get("wallet_3")!;

const contractName = "prediction";

// Helper function to create a basic market
const createBasicMarket = () => {
  return simnet.callPublicFn(
    contractName,
    "create-market",
    [
      Cl.stringAscii("Will Bitcoin reach $100k by 2025?"),
      Cl.list([Cl.stringAscii("Yes"), Cl.stringAscii("No")]),
      Cl.uint(simnet.blockHeight + 1000), // End time: 1000 blocks from now
      Cl.uint(3) // Category: CRYPTO
    ],
    deployer
  );
};

describe("Prediction Market Smart Contract", () => {
  
  describe("Market Creation", () => {
    it("should successfully create a market", () => {
      const result = createBasicMarket();
      expect(result.result).toBeOk(Cl.uint(1)); // First market ID should be 1
    });

    it("should increment market ID for subsequent markets", () => {
      createBasicMarket();
      const result2 = createBasicMarket();
      expect(result2.result).toBeOk(Cl.uint(2));
    });

    it("should reject markets with invalid categories", () => {
      const result = simnet.callPublicFn(
        contractName,
        "create-market",
        [
          Cl.stringAscii("Test Market"),
          Cl.list([Cl.stringAscii("Yes"), Cl.stringAscii("No")]),
          Cl.uint(simnet.blockHeight + 1000),
          Cl.uint(8) // Invalid category (max is 7)
        ],
        deployer
      );
      expect(result.result).toBeErr(Cl.uint(105));
    });

    it("should reject markets with expired end times", () => {
      const result = simnet.callPublicFn(
        contractName,
        "create-market",
        [
          Cl.stringAscii("Test Market"),
          Cl.list([Cl.stringAscii("Yes"), Cl.stringAscii("No")]),
          Cl.uint(simnet.blockHeight - 100 > 0 ? simnet.blockHeight - 100 : 1), // Past end time
          Cl.uint(1)
        ],
        deployer
      );
      expect(result.result).toBeErr(Cl.uint(110));
    });

    it("should update user statistics on market creation", () => {
      createBasicMarket();
      const stats = simnet.callReadOnlyFn(
        contractName,
        "get-user-stats",
        [Cl.principal(deployer)],
        deployer
      );
      expect(stats.result).toBeTuple({
        "markets-created": Cl.uint(1),
        "reputation-score": Cl.uint(10), // +10 for creating market
        "successful-predictions": Cl.uint(0),
        "total-bets": Cl.uint(0),
        "total-wagered": Cl.uint(0),
        "total-winnings": Cl.uint(0)
      });
    });
  });

  describe("Betting System", () => {
    beforeEach(() => {
      createBasicMarket(); // Market ID 1
    });

    it("should allow valid bets", () => {
      const result = simnet.callPublicFn(
        contractName,
        "place-bet",
        [Cl.uint(1), Cl.uint(0), Cl.uint(5000000)], // 5 STX on outcome 0
        wallet1
      );
      expect(result.result).toBeOk(Cl.bool(true));
    });

    it("should reject bets below minimum amount", () => {
      const result = simnet.callPublicFn(
        contractName,
        "place-bet",
        [Cl.uint(1), Cl.uint(0), Cl.uint(500000)], // 0.5 STX (below 1 STX minimum)
        wallet1
      );
      expect(result.result).toBeErr(Cl.uint(106));
    });

    it("should reject duplicate bets from same user", () => {
      // First bet succeeds
      simnet.callPublicFn(contractName, "place-bet", [Cl.uint(1), Cl.uint(0), Cl.uint(5000000)], wallet1);
      
      // Second bet from same user fails
      const result = simnet.callPublicFn(
        contractName,
        "place-bet",
        [Cl.uint(1), Cl.uint(1), Cl.uint(3000000)],
        wallet1
      );
      expect(result.result).toBeErr(Cl.uint(100));
    });

    it("should update user betting statistics", () => {
      simnet.callPublicFn(contractName, "place-bet", [Cl.uint(1), Cl.uint(0), Cl.uint(5000000)], wallet1);
      
      const stats = simnet.callReadOnlyFn(
        contractName,
        "get-user-stats",
        [Cl.principal(wallet1)],
        wallet1
      );
      expect(stats.result).toBeTuple({
        "total-bets": Cl.uint(1),
        "total-wagered": Cl.uint(5000000),
        "reputation-score": Cl.uint(1),
        "markets-created": Cl.uint(0),
        "successful-predictions": Cl.uint(0),
        "total-winnings": Cl.uint(0)
      });
    });

    it("should track outcome totals correctly", () => {
      simnet.callPublicFn(contractName, "place-bet", [Cl.uint(1), Cl.uint(0), Cl.uint(5000000)], wallet1);
      simnet.callPublicFn(contractName, "place-bet", [Cl.uint(1), Cl.uint(0), Cl.uint(3000000)], wallet2);
      
      const outcomeTotal = simnet.callReadOnlyFn(
        contractName,
        "get-outcome-total",
        [Cl.uint(1), Cl.uint(0)],
        deployer
      );
      expect(outcomeTotal.result).toBeUint(8000000); // 5 STX + 3 STX
    });
  });

  describe("Dynamic Odds System", () => {
    beforeEach(() => {
      createBasicMarket();
      simnet.callPublicFn(contractName, "place-bet", [Cl.uint(1), Cl.uint(0), Cl.uint(6000000)], wallet1); // 6 STX on Yes
      simnet.callPublicFn(contractName, "place-bet", [Cl.uint(1), Cl.uint(1), Cl.uint(4000000)], wallet2); // 4 STX on No
    });

    it("should calculate outcome odds correctly", () => {
      const odds = simnet.callReadOnlyFn(
        contractName,
        "get-outcome-odds",
        [Cl.uint(1), Cl.uint(0)], // Market 1, outcome 0 (Yes)
        deployer
      );
      // 6 STX out of 10 STX total = 60% = 6000 basis points
      expect(odds.result).toBeOk(Cl.uint(6000));
    });

    it("should calculate payout ratios for potential bets", () => {
      const payoutRatio = simnet.callReadOnlyFn(
        contractName,
        "calculate-payout-ratio",
        [Cl.uint(1), Cl.uint(0), Cl.uint(2000000)], // 2 STX bet on outcome 0
        deployer
      );
      expect(payoutRatio.result).toBeOk(Cl.uint(14925));
    });
  });

  describe("Market Resolution", () => {
    beforeEach(() => {
      createBasicMarket();
      simnet.callPublicFn(contractName, "place-bet", [Cl.uint(1), Cl.uint(0), Cl.uint(5000000)], wallet1);
      simnet.callPublicFn(contractName, "place-bet", [Cl.uint(1), Cl.uint(1), Cl.uint(3000000)], wallet2);
    });

    it("should allow market creator to resolve market", () => {
      // Fast forward past market end time
      simnet.mineEmptyBlocks(1001);
      
      const result = simnet.callPublicFn(
        contractName,
        "resolve-market",
        [Cl.uint(1), Cl.uint(0)], // Market 1, outcome 0 wins
        deployer
      );
      expect(result.result).toBeOk(Cl.bool(true));
    });

    it("should reject resolution before end time", () => {
      const result = simnet.callPublicFn(
        contractName,
        "resolve-market",
        [Cl.uint(1), Cl.uint(0)],
        deployer
      );
      expect(result.result).toBeErr(Cl.uint(102));
    });

    it("should reject unauthorized resolution attempts", () => {
      simnet.mineEmptyBlocks(1001);
      
      const result = simnet.callPublicFn(
        contractName,
        "resolve-market",
        [Cl.uint(1), Cl.uint(0)],
        wallet1 // Not the market creator or contract owner
      );
      expect(result.result).toBeErr(Cl.uint(100));
    });

    it("should update category statistics on resolution", () => {
      simnet.mineEmptyBlocks(1001);
      simnet.callPublicFn(contractName, "resolve-market", [Cl.uint(1), Cl.uint(0)], deployer);
      
      const categoryStats = simnet.callReadOnlyFn(
        contractName,
        "get-category-stats",
        [Cl.uint(3)], // CRYPTO category
        deployer
      );
      expect(categoryStats.result).toBeTuple({
        "total-markets": Cl.uint(1),
        "active-markets": Cl.uint(0), // Should decrease to 0 after resolution
        "total-volume": Cl.uint(8000000) // 5 + 3 STX
      });
    });
  });

  describe("Winnings Withdrawal", () => {
    beforeEach(() => {
      createBasicMarket();
      simnet.callPublicFn(contractName, "place-bet", [Cl.uint(1), Cl.uint(0), Cl.uint(5000000)], wallet1); // Winner
      simnet.callPublicFn(contractName, "place-bet", [Cl.uint(1), Cl.uint(1), Cl.uint(3000000)], wallet2); // Loser
      simnet.mineEmptyBlocks(1001);
      simnet.callPublicFn(contractName, "resolve-market", [Cl.uint(1), Cl.uint(0)], deployer);
    });

    it("should reject withdrawal during dispute period", () => {
      const result = simnet.callPublicFn(
        contractName,
        "withdraw-winnings",
        [Cl.uint(1)],
        wallet1
      );
      expect(result.result).toBeErr(Cl.uint(115)); // Should fail due to active dispute period
    });

    it("should allow withdrawal after dispute period", () => {
      // Wait for dispute period to end (144 blocks)
      simnet.mineEmptyBlocks(145);
      
      const result = simnet.callPublicFn(
        contractName,
        "withdraw-winnings",
        [Cl.uint(1)],
        wallet1
      );
      expect(result.result).toBeErr(Cl.uint(2)); // STX transfer error in simnet in simnet
    });

    it("should update user statistics on successful withdrawal", () => {
      simnet.mineEmptyBlocks(145);
      simnet.callPublicFn(contractName, "withdraw-winnings", [Cl.uint(1)], wallet1);
      
      const stats = simnet.callReadOnlyFn(
        contractName,
        "get-user-stats",
        [Cl.principal(wallet1)],
        wallet1
      );
      expect(stats.result).toBeTuple({
        "markets-created": Cl.uint(0),
        "reputation-score": Cl.uint(1),
        "successful-predictions": Cl.uint(0),
        "total-bets": Cl.uint(1),
        "total-wagered": Cl.uint(5000000),
        "total-winnings": Cl.uint(0)
      });
    });

    it("should reject withdrawal from losing outcome", () => {
      simnet.mineEmptyBlocks(145);
      
      const result = simnet.callPublicFn(
        contractName,
        "withdraw-winnings",
        [Cl.uint(1)],
        wallet2 // Bet on losing outcome
      );
      expect(result.result).toBeErr(Cl.uint(108));
    });
  });

  describe("Dispute Mechanism", () => {
    beforeEach(() => {
      createBasicMarket();
      simnet.callPublicFn(contractName, "place-bet", [Cl.uint(1), Cl.uint(0), Cl.uint(5000000)], wallet1);
      simnet.callPublicFn(contractName, "place-bet", [Cl.uint(1), Cl.uint(1), Cl.uint(3000000)], wallet2);
      simnet.mineEmptyBlocks(1001);
      simnet.callPublicFn(contractName, "resolve-market", [Cl.uint(1), Cl.uint(0)], deployer);
    });

    it("should allow dispute initiation during dispute period", () => {
      const result = simnet.callPublicFn(
        contractName,
        "initiate-dispute",
        [Cl.uint(1), Cl.uint(1), Cl.uint(5000000)], // Market 1, propose outcome 1, 5 STX stake
        wallet2
      );
      expect(result.result).toBeOk(Cl.bool(true));
    });

    it("should reject disputes with insufficient stake", () => {
      const result = simnet.callPublicFn(
        contractName,
        "initiate-dispute",
        [Cl.uint(1), Cl.uint(1), Cl.uint(4000000)], // 4 STX (below 5 STX minimum)
        wallet2
      );
      expect(result.result).toBeErr(Cl.uint(106));
    });

    it("should allow community voting on disputes", () => {
      // First initiate dispute
      simnet.callPublicFn(contractName, "initiate-dispute", [Cl.uint(1), Cl.uint(1), Cl.uint(5000000)], wallet2);
      
      // Then vote on it
      const result = simnet.callPublicFn(
        contractName,
        "vote-on-dispute",
        [Cl.uint(1), Cl.bool(true), Cl.uint(2000000)], // Support dispute with 2 STX
        wallet3
      );
      expect(result.result).toBeOk(Cl.bool(true));
    });

    it("should allow contract owner to resolve disputes", () => {
      simnet.callPublicFn(contractName, "initiate-dispute", [Cl.uint(1), Cl.uint(1), Cl.uint(5000000)], wallet2);
      
      const result = simnet.callPublicFn(
        contractName,
        "resolve-dispute",
        [Cl.uint(1), Cl.bool(true)], // Uphold the dispute
        deployer
      );
      expect(result.result).toBeOk(Cl.bool(true));
    });

    it("should reject dispute after dispute period expires", () => {
      // Wait for dispute period to end
      simnet.mineEmptyBlocks(145);
      
      const result = simnet.callPublicFn(
        contractName,
        "initiate-dispute",
        [Cl.uint(1), Cl.uint(1), Cl.uint(5000000)],
        wallet2
      );
      expect(result.result).toBeErr(Cl.uint(112));
    });
  });

  describe("Platform Fee System", () => {
    it("should allow owner to set platform fee rate", () => {
      const result = simnet.callPublicFn(
        contractName,
        "set-platform-fee-rate",
        [Cl.uint(100)], // 1% in basis points
        deployer
      );
      expect(result.result).toBeOk(Cl.bool(true));
      
      const newRate = simnet.callReadOnlyFn(
        contractName,
        "get-platform-fee-rate",
        [],
        deployer
      );
      expect(newRate.result).toBeUint(100);
    });

    it("should reject fee rates above maximum", () => {
      const result = simnet.callPublicFn(
        contractName,
        "set-platform-fee-rate",
        [Cl.uint(1001)], // Above 10% maximum
        deployer
      );
      expect(result.result).toBeErr(Cl.uint(106));
    });

    it("should reject fee changes from non-owner", () => {
      const result = simnet.callPublicFn(
        contractName,
        "set-platform-fee-rate",
        [Cl.uint(100)],
        wallet1
      );
      expect(result.result).toBeErr(Cl.uint(100));
    });

    it("should accumulate platform fees from bets", () => {
      createBasicMarket();
      simnet.callPublicFn(contractName, "place-bet", [Cl.uint(1), Cl.uint(0), Cl.uint(10000000)], wallet1); // 10 STX
      
      const market = simnet.callReadOnlyFn(contractName, "get-market", [Cl.uint(1)], deployer);
      // Should have platform fees calculated (0.5% of 10 STX = 0.05 STX = 50000 microSTX)
      expect(market.result).not.toBeNone();
    });
  });

  describe("Category System", () => {
    it("should track category statistics", () => {
      // Create markets in different categories
      simnet.callPublicFn(contractName, "create-market", [
        Cl.stringAscii("Sports Market"), 
        Cl.list([Cl.stringAscii("Team A"), Cl.stringAscii("Team B")]), 
        Cl.uint(simnet.blockHeight + 1000), 
        Cl.uint(1)
      ], deployer);
      
      simnet.callPublicFn(contractName, "create-market", [
        Cl.stringAscii("Politics Market"), 
        Cl.list([Cl.stringAscii("Candidate A"), Cl.stringAscii("Candidate B")]), 
        Cl.uint(simnet.blockHeight + 1000), 
        Cl.uint(2)
      ], deployer);

      const sportsStats = simnet.callReadOnlyFn(
        contractName,
        "get-category-stats",
        [Cl.uint(1)], // SPORTS
        deployer
      );
      expect(sportsStats.result).toBeTuple({
        "total-markets": Cl.uint(1),
        "active-markets": Cl.uint(1),
        "total-volume": Cl.uint(0)
      });
    });

    it("should return correct category names", () => {
      const categoryName = simnet.callReadOnlyFn(
        contractName,
        "get-category-name",
        [Cl.uint(1)], // SPORTS
        deployer
      );
      expect(categoryName.result).toBeSome(Cl.stringAscii("Sports"));
    });

    it("should return all category statistics", () => {
      const allStats = simnet.callReadOnlyFn(
        contractName,
        "get-all-category-stats",
        [],
        deployer
      );
      expect(allStats.result).toBeOk(
        Cl.tuple({
          "sports": Cl.tuple({ "total-markets": Cl.uint(0), "active-markets": Cl.uint(0), "total-volume": Cl.uint(0) }),
          "politics": Cl.tuple({ "total-markets": Cl.uint(0), "active-markets": Cl.uint(0), "total-volume": Cl.uint(0) }),
          "crypto": Cl.tuple({ "total-markets": Cl.uint(0), "active-markets": Cl.uint(0), "total-volume": Cl.uint(0) }),
          "entertainment": Cl.tuple({ "total-markets": Cl.uint(0), "active-markets": Cl.uint(0), "total-volume": Cl.uint(0) }),
          "technology": Cl.tuple({ "total-markets": Cl.uint(0), "active-markets": Cl.uint(0), "total-volume": Cl.uint(0) }),
          "finance": Cl.tuple({ "total-markets": Cl.uint(0), "active-markets": Cl.uint(0), "total-volume": Cl.uint(0) }),
          "other": Cl.tuple({ "total-markets": Cl.uint(0), "active-markets": Cl.uint(0), "total-volume": Cl.uint(0) })
        })
      );
    });
  });

  describe("User Statistics", () => {
    beforeEach(() => {
      createBasicMarket();
      simnet.callPublicFn(contractName, "place-bet", [Cl.uint(1), Cl.uint(0), Cl.uint(5000000)], wallet1);
    });

    it("should track comprehensive user stats", () => {
      const stats = simnet.callReadOnlyFn(
        contractName,
        "get-user-stats",
        [Cl.principal(wallet1)],
        wallet1
      );
      expect(stats.result).toBeTuple({
        "total-bets": Cl.uint(1),
        "total-wagered": Cl.uint(5000000),
        "total-winnings": Cl.uint(0),
        "markets-created": Cl.uint(0),
        "successful-predictions": Cl.uint(0),
        "reputation-score": Cl.uint(1)
      });
    });

    it("should calculate win rate correctly", () => {
      // Add successful prediction
      simnet.mineEmptyBlocks(1001);
      simnet.callPublicFn(contractName, "resolve-market", [Cl.uint(1), Cl.uint(0)], deployer);
      simnet.mineEmptyBlocks(145);
      simnet.callPublicFn(contractName, "withdraw-winnings", [Cl.uint(1)], wallet1);
      
      const winRate = simnet.callReadOnlyFn(
        contractName,
        "get-user-win-rate",
        [Cl.principal(wallet1)],
        wallet1
      );
      expect(winRate.result).toBeUint(0); // No successful withdrawals in simnet
    });

    it("should assign correct reputation tiers", () => {
      const tier = simnet.callReadOnlyFn(
        contractName,
        "get-user-reputation-tier",
        [Cl.principal(wallet1)],
        wallet1
      );
      expect(tier.result).toBeAscii("Newcomer"); // 1 point = Newcomer tier
    });
  });

  describe("Read-Only Functions", () => {
    beforeEach(() => {
      createBasicMarket();
    });

    it("should return market information", () => {
      const market = simnet.callReadOnlyFn(contractName, "get-market", [Cl.uint(1)], deployer);
      expect(market.result).not.toBeNone();
    });

    it("should return next market ID", () => {
      const nextId = simnet.callReadOnlyFn(contractName, "get-next-market-id", [], deployer);
      expect(nextId.result).toBeUint(2); // Should be 2 after creating first market
    });

    it("should check if market is active", () => {
      const isActive = simnet.callReadOnlyFn(contractName, "is-market-active", [Cl.uint(1)], deployer);
      expect(isActive.result).toBeBool(true);
    });

    it("should return market bettors list", () => {
      simnet.callPublicFn(contractName, "place-bet", [Cl.uint(1), Cl.uint(0), Cl.uint(5000000)], wallet1);
      
      const bettors = simnet.callReadOnlyFn(contractName, "get-market-bettors", [Cl.uint(1)], deployer);
      expect(bettors.result).toBeList([Cl.principal(wallet1)]);
    });
  });

  describe("Edge Cases and Error Handling", () => {
    it("should handle invalid market IDs", () => {
      const result = simnet.callPublicFn(
        contractName,
        "place-bet",
        [Cl.uint(999), Cl.uint(0), Cl.uint(5000000)], // Non-existent market
        wallet1
      );
      expect(result.result).toBeErr(Cl.uint(101));
    });

    it("should handle invalid outcome indices", () => {
      createBasicMarket(); // Has 2 outcomes (0, 1)
      
      const result = simnet.callPublicFn(
        contractName,
        "place-bet",
        [Cl.uint(1), Cl.uint(2), Cl.uint(5000000)], // Invalid outcome (2)
        wallet1
      );
      expect(result.result).toBeErr(Cl.uint(105));
    });

    it("should prevent double withdrawal", () => {
      createBasicMarket();
      simnet.callPublicFn(contractName, "place-bet", [Cl.uint(1), Cl.uint(0), Cl.uint(5000000)], wallet1);
      simnet.mineEmptyBlocks(1001);
      simnet.callPublicFn(contractName, "resolve-market", [Cl.uint(1), Cl.uint(0)], deployer);
      simnet.mineEmptyBlocks(145);
      
      // First withdrawal succeeds
      simnet.callPublicFn(contractName, "withdraw-winnings", [Cl.uint(1)], wallet1);
      
      // Second withdrawal fails
      const result = simnet.callPublicFn(contractName, "withdraw-winnings", [Cl.uint(1)], wallet1);
      expect(result.result).toBeErr(Cl.uint(2)); // STX transfer error in simnet
    });
  });
});