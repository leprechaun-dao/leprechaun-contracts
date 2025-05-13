# Leprechaun Protocol

> A decentralized protocol for creating and trading synthetic assets backed by collateral.

Leprechaun Protocol is a DeFi system that enables users to create synthetic assets representing real-world assets or indices by depositing collateral. It uses price oracle data from Pyth Network to ensure proper collateralization and liquidation mechanisms.

## Table of Contents

- [Overview](#overview)
- [Core Components](#core-components)
- [Key Features](#key-features)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Usage](#usage)
- [Contract Architecture](#contract-architecture)
- [Contributing](#contributing)
- [License](#license)

## Overview

Leprechaun Protocol allows users to mint synthetic assets (e.g., synthetic gold, synthetic stocks) by depositing various types of collateral. The protocol maintains strict collateralization requirements and use oracle price feeds, with liquidation mechanisms to ensure system solvency.

## Core Components

- **LeprechaunFactory**: Central registry that manages synthetic assets and collateral types
- **PositionManager**: Handles collateralized debt positions (CDPs)
- **SyntheticAsset**: ERC20 token implementation representing synthetic assets
- **OracleInterface**: Integration with Pyth Network for reliable price feeds
- **LeprechaunLens**: A view contract that provides formatted data access for frontends

## Key Features

- 🏦 **Multi-Collateral Support**: Use various tokens as collateral with different risk parameters
- 🧠 **Dynamic Risk Management**: Collateral-specific risk multipliers and asset-specific minimum collateral ratios
- 📊 **Enhanced Oracle Integration**: Real-time price feeds from Pyth Network with staleness checks
- 💰 **Liquidation Incentives**: Configurable auction discounts for liquidators
- 🔄 **Flexible Position Management**: Deposit, withdraw, mint, burn operations for CDP management
- 💼 **Protocol Fees**: Configurable fee system for sustainability
- 👀 **Data Access Layer**: Dedicated LeprechaunLens contract for easy frontend integration

## Prerequisites

- [Foundry](https://getfoundry.sh/) - Ethereum development toolkit

## Installation

1. Clone the repository:

```bash
git clone https://github.com/yourusername/leprechaun-contracts.git
cd leprechaun-contracts
```

2. Install dependencies:

```bash
forge install
```

## Usage

### Build

Compile the contracts:

```bash
forge build
```

### Test

Run the test suite:

```bash
forge test
```

Run tests with gas reporting:

```bash
forge test --gas-report
```

Run a specific test:

```bash
forge test --match-test testBidirectionalCalculations
```

### Run Local Node

Start a local Ethereum node:

```bash
anvil
```

### Deploy

Deploy to a network:

```bash
FEE_COLLECTOR_ADDRESS= forge script script/LeprechaunDeploy.s.sol:LeprechaunDeployScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

## Contract Architecture

### LeprechaunFactory

The central registry contract manages protocol parameters, synthetic assets, and collateral types. It serves as the configuration hub for the entire protocol.

**Key Functions:**

- Register and manage synthetic assets
- Register and manage collateral types
- Set collateral acceptance for specific synthetic assets
- Configure protocol fees and risk parameters

### PositionManager

Handles collateralized debt positions (CDPs), allowing users to create, modify, and close positions.

**Key Functions:**

- Create positions with collateral to mint synthetic assets
- Deposit additional collateral to positions
- Withdraw collateral from positions
- Mint additional synthetic assets
- Burn synthetic assets to reduce debt
- Close positions
- Liquidate under-collateralized positions

### SyntheticAsset

ERC20 token implementation representing synthetic assets. Each instance represents a different synthetic asset.

**Key Functions:**

- Standard ERC20 functionality
- Permissioned minting and burning controlled by the PositionManager

### OracleInterface

Connects to Pyth Network for reliable price feeds, ensuring the protocol has accurate asset prices.

**Key Functions:**

- Register price feeds for assets
- Retrieve current prices
- Convert token amounts to USD values

### LeprechaunLens

A view contract that provides formatted data access for frontend applications without modifying protocol state.

**Key Functions:**

- Get protocol configuration information
- Retrieve synthetic asset and collateral details
- Get user positions with current health metrics
- Find positions at risk of liquidation
- Calculate liquidation returns
- Preview operations like minting or withdrawing

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
