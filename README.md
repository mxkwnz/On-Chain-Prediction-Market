## Project Plan — On-Chain Prediction Market (Option D)

We are building a decentralized prediction market with binary outcomes, AMM-based pricing, Chainlink oracle resolution, ERC-1155 outcome tokens, DAO governance, and deployment on an L2 testnet. The system is designed to satisfy all mandatory requirements from the course specification .

---

## 1. System Overview

The protocol consists of the following components:

* MarketFactory for deploying new markets using CREATE and CREATE2
* PredictionMarket contracts managing lifecycle (create → trade → resolve → claim)
* AMM pricing engine (LMSR or CPMM) for trading outcome shares
* ERC-1155 token for YES/NO outcome shares
* ERC-20 governance token (ERC20Votes + Permit)
* Chainlink oracle integration with staleness checks
* Dispute window with DAO override for resolution
* Fee vault (ERC-4626) for collecting and distributing fees
* Governance system (Governor + TimelockController)
* Frontend (JavaScript) interacting with contracts
* Subgraph indexing protocol activity

---

## 2. Task Division

### Mukhammedali — Market Core and AMM

**Smart Contracts**

* MarketFactory.sol (CREATE + CREATE2)
* PredictionMarket.sol (market lifecycle)
* LMSRMarketMaker.sol or CPMM.sol (pricing engine)
* Trading logic with slippage protection and fee handling

**Frontend (JavaScript)**

* Market creation interface
* Trading UI (buy/sell outcome shares)
* Display of market prices and liquidity

**Testing**

* Unit tests for market lifecycle
* Fuzz tests for trading logic
* Invariant tests for AMM correctness

---

### Alikhan — Oracle and Governance

**Smart Contracts**

* OracleAdapter.sol (Chainlink integration with staleness checks)
* Resolution system with dispute window
* GovernanceToken.sol (ERC20Votes + Permit)
* Governor.sol
* Timelock.sol

**Frontend (JavaScript)**

* Governance interface (create proposals, vote, execute)
* Display proposal states (Pending, Active, etc.)
* Dispute handling interface if needed

**Testing**

* Oracle tests (including stale data handling)
* Governance lifecycle tests
* Access control and security tests

---

### Nursultan — Tokens, Vault, and Integration

**Smart Contracts**

* OutcomeToken1155.sol (mint/burn outcome shares)
* FeeVault.sol (ERC-4626)
* Integration logic between market, tokens, and vault

**Frontend**

* Wallet connection (MetaMask)
* User dashboard (balances, positions)
* Claim winnings functionality
* Transaction handling and error messages

**DevOps and Indexing**

* Deployment scripts
* CI pipeline (GitHub Actions)
* Contract verification on L2

**Testing**

* Vault tests (deposit/withdraw)
* Integration tests (end-to-end flows)
* Fork tests (Chainlink, tokens)

---

## 3. Smart Contract Structure

contracts/

* MarketFactory.sol
* PredictionMarket.sol
* LMSRMarketMaker.sol or CPMM.sol
* OutcomeToken1155.sol
* GovernanceToken.sol
* FeeVault.sol
* OracleAdapter.sol
* Governor.sol
* Timelock.sol

---

## 4. Development Timeline

### Week 6–7

* Repository setup and CI
* Base contracts implemented and compiling
* Initial frontend structure

### Week 8

* AMM and trading fully implemented
* Token and vault integration
* Test coverage reaches ~50%

### Week 9

* Oracle integration with staleness checks
* Governance system deployed and working
* Contracts deployed to L2
* Subgraph indexing live

### Week 10

* Frontend fully integrated
* Tests finalized (≥90% coverage)
* Audit report and documentation completed
* Final presentation prepared

---

## 5. Testing Strategy

* At least 80 tests total:

  * Unit tests
  * Fuzz tests
  * Invariant tests
  * Fork tests
* Coverage ≥90% across contracts
* All tests must pass in CI

---

## 6. Key Design Decisions

* AMM: LMSR preferred for more advanced implementation, CPMM as fallback

* Resolution flow:

  1. Oracle provides result
  2. Staleness check enforced
  3. Dispute window opens
  4. DAO can override
  5. Final result is used for claims

* Upgradeability:

  * At least one contract uses UUPS proxy

---

## 7. Security Considerations

* Checks-Effects-Interactions pattern or ReentrancyGuard
* AccessControl or Ownable for privileged functions
* SafeERC20 for all token interactions
* No use of tx.origin or unsafe randomness
* Slither must report zero High/Medium issues
* Two vulnerability case studies included:

  * Reentrancy
  * Access control

---

## 8. DevOps and Deployment

* GitHub Actions CI:

  * Build, test, coverage, Slither
* Linting and formatting checks
* Deployment scripts for L2
* Contract verification on block explorer
* Gas comparison report (L1 vs L2)

---

## 9. Frontend Requirements

* Wallet connection (MetaMask)
* Display balances and protocol state
* Execute transactions:

  * Trade
  * Claim
  * Vote
* Governance UI with proposal states
* Data from subgraph
* Error handling and network switching

---

## 10. Milestones

* Week 6: Team formed and scenario approved
* Week 7: Contracts compile, CI working
* Week 8: AMM and tokens complete, 50% coverage
* Week 9: Governance, oracle, L2 deployment, subgraph live
* Week 10: Final submission and presentation

---

This plan ensures full coverage of all required components, balanced workload, and compliance with all technical and grading requirements .
