// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/LeprechaunFactory.sol";
import "../src/PositionManager.sol";
import "../src/OracleInterface.sol";
import "../src/SyntheticAsset.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockToken
 * @dev Simple ERC20 token for development and testing
 */
contract MockToken is ERC20 {
    uint8 private _decimals;

    constructor(string memory name, string memory symbol, uint8 decimalsValue) ERC20(name, symbol) {
        _decimals = decimalsValue;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }
}

/**
 * @title LeprechaunDeployScript
 * @dev Deployment script for the refactored Leprechaun protocol with math improvements
 */
contract LeprechaunDeployScript is Script {
    // Protocol constants
    uint256 constant MIN_COLLATERAL_RATIO = 15000; // 150%
    uint256 constant AUCTION_DISCOUNT = 1000; // 10%

    // Collateral multipliers (higher = riskier)
    uint256 constant USDC_MULTIPLIER = 10000; // 1.0x (least risky)
    uint256 constant WETH_MULTIPLIER = 11000; // 1.1x
    uint256 constant WBTC_MULTIPLIER = 12000; // 1.2x (most risky)

    // Protocol fee (1.5%)
    uint256 constant PROTOCOL_FEE = 150;

    // Real Pyth oracle address on Arbitrum
    address constant PYTH_ORACLE_ADDRESS = 0x8250f4aF4B972684F7b336503E2D6dFeDeB1487a;

    // Real Pyth price feed IDs
    bytes32 constant DOW_USD_FEED_ID = 0xf3b50961ff387a3d68217e2715637d0add6013e7ecb83c36ae8062f97c46929e;
    bytes32 constant USDC_USD_FEED_ID = 0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a;
    bytes32 constant WBTC_USD_FEED_ID = 0xc9d8b075a5c69303365ae23633d4e085199bf5c520a3b90fed1322a0342ffc33;
    bytes32 constant WETH_USD_FEED_ID = 0x9d4294bbcd1174d6f2003ec365831e64cc31d9f6f15a2b85399db8d5000960f6;

    // Mock tokens
    MockToken public mockUSDC;
    MockToken public mockWETH;
    MockToken public mockWBTC;

    // Protocol contracts
    OracleInterface public oracle;
    LeprechaunFactory public factory;
    PositionManager public positionManager;

    // Synthetic asset address
    address public dowUsdAsset;

    function run() external {
        // Set the fee collector address - can be the deployer's address or another address
        address feeCollector = vm.envOr("FEE_COLLECTOR_ADDRESS", address(msg.sender));

        // Start broadcasting transactions
        vm.startBroadcast();

        // Get the deployer's address (whoever's private key is being used)
        address deployer = msg.sender;

        console.log("Deploying Refactored Leprechaun Protocol to Arbitrum with Math Improvements");
        console.log("Deployer: ", deployer);
        console.log("Fee Collector: ", feeCollector);

        // Deploy mock tokens
        mockUSDC = new MockToken("Mock USD Coin", "mUSDC", 6);
        mockWETH = new MockToken("Mock Wrapped Ether", "mWETH", 18);
        mockWBTC = new MockToken("Mock Wrapped Bitcoin", "mWBTC", 8);

        console.log("Mock USDC deployed at:", address(mockUSDC));
        console.log("Mock WETH deployed at:", address(mockWETH));
        console.log("Mock WBTC deployed at:", address(mockWBTC));

        // Mint tokens to deployer for testing
        uint256 usdcAmount = 1_000_000 * 10 ** 6; // 1 million USDC
        uint256 wethAmount = 1_000 * 10 ** 18; // 1,000 WETH
        uint256 wbtcAmount = 100 * 10 ** 8; // 100 WBTC

        mockUSDC.mint(deployer, usdcAmount);
        mockWETH.mint(deployer, wethAmount);
        mockWBTC.mint(deployer, wbtcAmount);

        console.log("Minted mock tokens to deployer");

        // Deploy new refactored oracle interface with improved math
        oracle = new OracleInterface(PYTH_ORACLE_ADDRESS);
        console.log("Refactored Oracle Interface deployed at:", address(oracle));

        // Deploy factory
        factory = new LeprechaunFactory(deployer, feeCollector, address(oracle));
        console.log("LeprechaunFactory deployed at:", address(factory));

        // Set protocol fee to 1.5%
        factory.updateProtocolFee(PROTOCOL_FEE);
        console.log("Protocol fee set to 1.5%");

        // Deploy position manager with refactored calculations
        positionManager = new PositionManager(address(factory), address(oracle), deployer);
        console.log("Refactored PositionManager deployed at:", address(positionManager));

        // Register DOW/USD synthetic asset
        console.log("Registering DOW/USD synthetic asset...");
        factory.registerSyntheticAsset(
            "Dow Jones Industrial Average",
            "sDOW",
            MIN_COLLATERAL_RATIO,
            AUCTION_DISCOUNT,
            DOW_USD_FEED_ID,
            address(positionManager)
        );

        // Get the synthetic asset address
        dowUsdAsset = factory.allSyntheticAssets(0);
        console.log("DOW/USD Synthetic Asset registered at:", dowUsdAsset);

        // Register mock collateral types with real price feed IDs
        console.log("Registering mock collateral types...");

        // Register mockUSDC as collateral
        factory.registerCollateralType(address(mockUSDC), USDC_MULTIPLIER, USDC_USD_FEED_ID);
        console.log("Mock USDC registered as collateral");

        // Register mockWETH as collateral
        factory.registerCollateralType(address(mockWETH), WETH_MULTIPLIER, WETH_USD_FEED_ID);
        console.log("Mock WETH registered as collateral");

        // Register mockWBTC as collateral
        factory.registerCollateralType(address(mockWBTC), WBTC_MULTIPLIER, WBTC_USD_FEED_ID);
        console.log("Mock WBTC registered as collateral");

        // Allow all mock collateral types for the DOW/USD synthetic asset
        factory.allowCollateralForAsset(dowUsdAsset, address(mockUSDC));
        factory.allowCollateralForAsset(dowUsdAsset, address(mockWETH));
        factory.allowCollateralForAsset(dowUsdAsset, address(mockWBTC));

        console.log("All mock collateral types enabled for DOW/USD asset");

        // End broadcast
        vm.stopBroadcast();

        console.log("\n=== Deployment Summary ===");

        console.log("LeprechaunFactory:  ", address(factory));
        console.log("PositionManager:    ", address(positionManager));
        console.log("OracleInterface:    ", address(oracle));
        console.log("DOW/USD Synthetic:  ", dowUsdAsset);
        console.log("Mock USDC:          ", address(mockUSDC));
        console.log("Mock WETH:          ", address(mockWETH));
        console.log("Mock WBTC:          ", address(mockWBTC));

        console.log("\nNOTE: The mock tokens are using real Pyth price feeds");
    }
}
