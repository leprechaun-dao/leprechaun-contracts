// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/LeprechaunFactory.sol";
import "../src/PositionManager.sol";
import "../src/OracleInterface.sol";
import "../src/SyntheticAsset.sol";

/**
 * @title VerifyDeploymentScript
 * @dev Script to verify the deployment and configuration of the Leprechaun protocol
 */
contract VerifyDeploymentScript is Script {
    // Replace these addresses with your actual deployed contract addresses
    address constant LEPRECHAUN_FACTORY = 0x364A6127A8b425b6857f4962412b0664D257BDD5;
    address constant POSITION_MANAGER = 0x401d1cD4D0ff1113458339065Cf9a1f2e8425afb;
    address constant ORACLE_INTERFACE = 0xBc2e651eD3566c6dF862815Ed05b99eFb9bC0255;
    address constant SYNTHETIC_DOW = 0xD14F0B478F993967240Aa5995eb2b1Ca6810969a;
    address constant MOCK_USDC = 0x39510c9f9E577c65b9184582745117341e7bdD73;
    address constant MOCK_WETH = 0x95539ce7555F53dACF3a79Ff760C06e5B4e310c3;
    address constant MOCK_WBTC = 0x1DBf5683c73E0D0A0e20AfC76F924e08E95637F7;

    // Real Pyth oracle on Arbitrum
    address constant PYTH_ORACLE = 0x8250f4aF4B972684F7b336503E2D6dFeDeB1487a;

    // Expected configuration values
    bytes32 constant DOW_USD_FEED_ID = 0xf3b50961ff387a3d68217e2715637d0add6013e7ecb83c36ae8062f97c46929e;
    bytes32 constant USDC_USD_FEED_ID = 0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a;
    bytes32 constant WBTC_USD_FEED_ID = 0xc9d8b075a5c69303365ae23633d4e085199bf5c520a3b90fed1322a0342ffc33;
    bytes32 constant WETH_USD_FEED_ID = 0x9d4294bbcd1174d6f2003ec365831e64cc31d9f6f15a2b85399db8d5000960f6;

    uint256 constant EXPECTED_MIN_COLLATERAL_RATIO = 15000; // 150%
    uint256 constant EXPECTED_AUCTION_DISCOUNT = 1000; // 10%
    uint256 constant EXPECTED_USDC_MULTIPLIER = 10000; // 1.0x
    uint256 constant EXPECTED_WETH_MULTIPLIER = 11000; // 1.1x
    uint256 constant EXPECTED_WBTC_MULTIPLIER = 12000; // 1.2x
    uint256 constant EXPECTED_PROTOCOL_FEE = 150; // 1.5%

    function run() external {
        // No need to broadcast transactions for read-only checks
        console.log("\n========== LEPRECHAUN PROTOCOL DEPLOYMENT VERIFICATION ==========\n");

        // Check Oracle configuration
        _verifyOracleInterface();

        // Check Factory configuration
        _verifyLeprechaunFactory();

        // Check Position Manager configuration
        _verifyPositionManager();

        // Check Synthetic Asset configuration
        _verifySyntheticAsset();

        // Check Collateral Token registrations
        _verifyCollateralRegistrations();

        // Check Collateral allowances for DOW asset
        _verifyCollateralAllowances();

        // Math verification tests
        _verifyMathCalculations();

        console.log("\n========== VERIFICATION COMPLETE ==========\n");
    }

    /**
     * @dev Verify Oracle Interface configuration
     */
    function _verifyOracleInterface() internal view {
        console.log("Verifying OracleInterface...");
        OracleInterface oracle = OracleInterface(ORACLE_INTERFACE);

        // Verify connection to Pyth oracle
        address pythAddress = address(oracle.pyth());
        bool pythMatch = pythAddress == PYTH_ORACLE;
        console.log("  Pyth Oracle address:", pythAddress);
        console.log("  Matches expected value:", pythMatch);
        if (!pythMatch) {
            console.log("  ERROR: Pyth Oracle address mismatch!");
            console.log("  Expected:", PYTH_ORACLE);
        }

        // Verify price feeds are registered
        bool dowFeedRegistered = oracle.isPriceFeedRegistered(SYNTHETIC_DOW);
        bool usdcFeedRegistered = oracle.isPriceFeedRegistered(MOCK_USDC);
        bool wethFeedRegistered = oracle.isPriceFeedRegistered(MOCK_WETH);
        bool wbtcFeedRegistered = oracle.isPriceFeedRegistered(MOCK_WBTC);

        console.log("  Price feed registrations:");
        console.log("    sDOW USD feed registered:", dowFeedRegistered);
        console.log("    mUSDC USD feed registered:", usdcFeedRegistered);
        console.log("    mWETH USD feed registered:", wethFeedRegistered);
        console.log("    mWBTC USD feed registered:", wbtcFeedRegistered);

        if (!dowFeedRegistered || !usdcFeedRegistered || !wethFeedRegistered || !wbtcFeedRegistered) {
            console.log("  ERROR: Some price feeds are not registered!");
        }

        console.log("OracleInterface verification complete.");
    }

    /**
     * @dev Verify LeprechaunFactory configuration
     */
    function _verifyLeprechaunFactory() internal view {
        console.log("\nVerifying LeprechaunFactory...");
        LeprechaunFactory factory = LeprechaunFactory(LEPRECHAUN_FACTORY);

        // Verify owner
        address owner = factory.owner();
        console.log("  Owner:", owner);

        // Verify oracle
        address oracle = address(factory.oracle());
        bool oracleMatch = oracle == ORACLE_INTERFACE;
        console.log("  Oracle Interface address:", oracle);
        console.log("  Matches expected value:", oracleMatch);
        if (!oracleMatch) {
            console.log("  ERROR: Oracle Interface address mismatch!");
            console.log("  Expected:", ORACLE_INTERFACE);
        }

        // Verify fee collector
        address feeCollector = factory.feeCollector();
        console.log("  Fee Collector:", feeCollector);

        // Verify protocol fee
        uint256 protocolFee = factory.protocolFee();
        bool feeMatch = protocolFee == EXPECTED_PROTOCOL_FEE;
        console.log("  Protocol Fee:", protocolFee, "basis points");
        console.log("  Matches expected value:", feeMatch);
        if (!feeMatch) {
            console.log("  ERROR: Protocol Fee mismatch!");
            console.log("  Expected:", EXPECTED_PROTOCOL_FEE);
        }

        // Verify synthetic assets count
        uint256 syntheticAssetCount = factory.getSyntheticAssetCount();
        console.log("  Synthetic Asset Count:", syntheticAssetCount);
        if (syntheticAssetCount != 1) {
            console.log("  WARNING: Expected 1 synthetic asset, found", syntheticAssetCount);
        }

        // Verify first synthetic asset
        address assetAddress = factory.allSyntheticAssets(0);
        bool assetMatch = assetAddress == SYNTHETIC_DOW;
        console.log("  First Synthetic Asset address:", assetAddress);
        console.log("  Matches sDOW address:", assetMatch);
        if (!assetMatch) {
            console.log("  ERROR: Synthetic Asset address mismatch!");
            console.log("  Expected:", SYNTHETIC_DOW);
        }

        // Get details for sDOW
        (
            address tokenAddress,
            string memory name,
            string memory symbol,
            uint256 minCollateralRatio,
            uint256 auctionDiscount,
            bool isActive
        ) = factory.syntheticAssets(SYNTHETIC_DOW);

        console.log("  sDOW details:");
        console.log("    Token Address:", tokenAddress);
        console.log("    Name:", name);
        console.log("    Symbol:", symbol);
        console.log("    Min Collateral Ratio:", minCollateralRatio);
        console.log("    Auction Discount:", auctionDiscount);
        console.log("    Is Active:", isActive);

        bool ratioMatch = minCollateralRatio == EXPECTED_MIN_COLLATERAL_RATIO;
        bool discountMatch = auctionDiscount == EXPECTED_AUCTION_DISCOUNT;

        if (!ratioMatch) {
            console.log("    ERROR: Min Collateral Ratio mismatch!");
            console.log("    Expected:", EXPECTED_MIN_COLLATERAL_RATIO);
        }

        if (!discountMatch) {
            console.log("    ERROR: Auction Discount mismatch!");
            console.log("    Expected:", EXPECTED_AUCTION_DISCOUNT);
        }

        console.log("LeprechaunFactory verification complete.");
    }

    /**
     * @dev Verify PositionManager configuration
     */
    function _verifyPositionManager() internal view {
        console.log("\nVerifying PositionManager...");
        PositionManager manager = PositionManager(POSITION_MANAGER);

        // Verify owner
        address owner = manager.owner();
        console.log("  Owner:", owner);

        // Verify registry
        address registry = address(manager.registry());
        bool registryMatch = registry == LEPRECHAUN_FACTORY;
        console.log("  Factory Registry address:", registry);
        console.log("  Matches expected value:", registryMatch);
        if (!registryMatch) {
            console.log("  ERROR: Factory Registry address mismatch!");
            console.log("  Expected:", LEPRECHAUN_FACTORY);
        }

        // Check position count
        uint256 positionCount = manager.nextPositionId();
        console.log("  Next Position ID:", positionCount);

        console.log("PositionManager verification complete.");
    }

    /**
     * @dev Verify Synthetic Asset configuration
     */
    function _verifySyntheticAsset() internal view {
        console.log("\nVerifying sDOW Synthetic Asset...");
        SyntheticAsset asset = SyntheticAsset(SYNTHETIC_DOW);

        // Verify token details
        string memory name = asset.name();
        string memory symbol = asset.symbol();
        uint8 decimals = asset.decimals();

        console.log("  Name:", name);
        console.log("  Symbol:", symbol);
        console.log("  Decimals:", decimals);

        // Verify position manager
        address posManager = asset.positionManager();
        bool posManagerMatch = posManager == POSITION_MANAGER;
        console.log("  Position Manager:", posManager);
        console.log("  Matches expected value:", posManagerMatch);
        if (!posManagerMatch) {
            console.log("  ERROR: Position Manager address mismatch!");
            console.log("  Expected:", POSITION_MANAGER);
        }

        console.log("sDOW Synthetic Asset verification complete.");
    }

    /**
     * @dev Verify Collateral Token registrations
     */
    function _verifyCollateralRegistrations() internal view {
        console.log("\nVerifying Collateral Registrations...");
        LeprechaunFactory factory = LeprechaunFactory(LEPRECHAUN_FACTORY);

        // Verify collateral count
        uint256 collateralCount = factory.getCollateralTypeCount();
        console.log("  Collateral Type Count:", collateralCount);
        if (collateralCount != 3) {
            console.log("  WARNING: Expected 3 collateral types, found", collateralCount);
        }

        // Verify each collateral type
        for (uint256 i = 0; i < collateralCount && i < 3; i++) {
            address collateralAddress = factory.allCollateralTypes(i);
            (, uint256 multiplier, bool isActive) = factory.collateralTypes(collateralAddress);

            string memory collateralName;
            if (collateralAddress == MOCK_USDC) {
                collateralName = "mUSDC";
                if (multiplier != EXPECTED_USDC_MULTIPLIER) {
                    console.log("  ERROR: mUSDC multiplier mismatch!");
                    console.log("  Expected:", EXPECTED_USDC_MULTIPLIER, "Got:", multiplier);
                }
            } else if (collateralAddress == MOCK_WETH) {
                collateralName = "mWETH";
                if (multiplier != EXPECTED_WETH_MULTIPLIER) {
                    console.log("  ERROR: mWETH multiplier mismatch!");
                    console.log("  Expected:", EXPECTED_WETH_MULTIPLIER, "Got:", multiplier);
                }
            } else if (collateralAddress == MOCK_WBTC) {
                collateralName = "mWBTC";
                if (multiplier != EXPECTED_WBTC_MULTIPLIER) {
                    console.log("  ERROR: mWBTC multiplier mismatch!");
                    console.log("  Expected:", EXPECTED_WBTC_MULTIPLIER, "Got:", multiplier);
                }
            } else {
                collateralName = "Unknown";
            }

            console.log("  Collateral #", i, ":", collateralName);
            console.log("    Address:", collateralAddress);
            console.log("    Multiplier:", multiplier);
            console.log("    Is Active:", isActive);
        }

        console.log("Collateral Registrations verification complete.");
    }

    /**
     * @dev Verify Collateral allowances for sDOW
     */
    function _verifyCollateralAllowances() internal view {
        console.log("\nVerifying Collateral Allowances for sDOW...");
        LeprechaunFactory factory = LeprechaunFactory(LEPRECHAUN_FACTORY);

        // Check allowances for sDOW
        bool usdcAllowed = factory.allowedCollateral(SYNTHETIC_DOW, MOCK_USDC);
        bool wethAllowed = factory.allowedCollateral(SYNTHETIC_DOW, MOCK_WETH);
        bool wbtcAllowed = factory.allowedCollateral(SYNTHETIC_DOW, MOCK_WBTC);

        console.log("  mUSDC allowed for sDOW:", usdcAllowed);
        console.log("  mWETH allowed for sDOW:", wethAllowed);
        console.log("  mWBTC allowed for sDOW:", wbtcAllowed);

        if (!usdcAllowed || !wethAllowed || !wbtcAllowed) {
            console.log("  ERROR: Not all collateral types are allowed for sDOW!");
        }

        // Check effective collateral ratios
        uint256 usdcRatio = factory.getEffectiveCollateralRatio(SYNTHETIC_DOW, MOCK_USDC);
        uint256 wethRatio = factory.getEffectiveCollateralRatio(SYNTHETIC_DOW, MOCK_WETH);
        uint256 wbtcRatio = factory.getEffectiveCollateralRatio(SYNTHETIC_DOW, MOCK_WBTC);

        uint256 expectedUsdcRatio = (EXPECTED_MIN_COLLATERAL_RATIO * EXPECTED_USDC_MULTIPLIER) / 10000;
        uint256 expectedWethRatio = (EXPECTED_MIN_COLLATERAL_RATIO * EXPECTED_WETH_MULTIPLIER) / 10000;
        uint256 expectedWbtcRatio = (EXPECTED_MIN_COLLATERAL_RATIO * EXPECTED_WBTC_MULTIPLIER) / 10000;

        console.log("  Effective collateral ratios:");
        console.log("    mUSDC:", usdcRatio, "(Expected:", expectedUsdcRatio);
        console.log("    mWETH:", wethRatio, "(Expected:", expectedWethRatio);
        console.log("    mWBTC:", wbtcRatio, "(Expected:", expectedWbtcRatio);

        if (usdcRatio != expectedUsdcRatio || wethRatio != expectedWethRatio || wbtcRatio != expectedWbtcRatio) {
            console.log("  ERROR: Some effective collateral ratios don't match expected values!");
        }

        console.log("Collateral Allowances verification complete.");
    }

    /**
     * @dev Verify Math Calculations with refactored code
     */
    function _verifyMathCalculations() internal view {
        console.log("\nVerifying Math Calculations...");
        PositionManager manager = PositionManager(POSITION_MANAGER);

        // Test bidirectional calculations with different collateral types
        _testBidirectionalCalculation("USDC Collateral", MOCK_USDC, 100 * 10 ** 6, 6); // 100 USDC
        _testBidirectionalCalculation("WETH Collateral", MOCK_WETH, 1 * 10 ** 18, 18); // 1 WETH
        _testBidirectionalCalculation("WBTC Collateral", MOCK_WBTC, 0.1 * 10 ** 8, 8); // 0.1 WBTC

        console.log("Math Calculations verification complete.");
    }

    /**
     * @dev Test bidirectional calculations for collateral to synthetic amount and back
     */
    function _testBidirectionalCalculation(
        string memory label,
        address collateralAsset,
        uint256 collateralAmount,
        uint8 decimals
    ) internal view {
        console.log("\n  Testing", label);
        PositionManager manager = PositionManager(POSITION_MANAGER);

        // Calculate mintable synthetic amount
        uint256 mintableAmount = manager.getMintableAmount(SYNTHETIC_DOW, collateralAsset, collateralAmount);

        if (decimals == 6) {
            console.log("    Input collateral:", collateralAmount / 1e6, "tokens (6 decimals)");
        } else if (decimals == 8) {
            console.log("    Input collateral:", collateralAmount / 1e8, "tokens (8 decimals)");
        } else {
            console.log("    Input collateral:", collateralAmount / 1e18, "tokens (18 decimals)");
        }

        console.log("    Calculated mintable synthetic:", mintableAmount / 1e18, "tokens");

        // If mintable is 0, can't do bidirectional test
        if (mintableAmount == 0) {
            console.log("    No synthetic tokens can be minted, skipping bidirectional check");
            return;
        }

        // Calculate required collateral for the mintable amount
        uint256 requiredCollateral = manager.getRequiredCollateral(SYNTHETIC_DOW, collateralAsset, mintableAmount);

        if (decimals == 6) {
            console.log("    Required collateral:", requiredCollateral / 1e6, "tokens (6 decimals)");
        } else if (decimals == 8) {
            console.log("    Required collateral:", requiredCollateral / 1e8, "tokens (8 decimals)");
        } else {
            console.log("    Required collateral:", requiredCollateral / 1e18, "tokens (18 decimals)");
        }

        // Calculate percentage difference
        uint256 differencePercentage = 0;
        if (collateralAmount > 0) {
            if (requiredCollateral > collateralAmount) {
                differencePercentage = ((requiredCollateral - collateralAmount) * 100) / collateralAmount;
            } else {
                differencePercentage = ((collateralAmount - requiredCollateral) * 100) / collateralAmount;
            }
        }

        console.log("    Bidirectional difference: ", differencePercentage, "%");

        if (differencePercentage > 1) {
            console.log("    WARNING: Bidirectional calculation difference exceeds 1%!");
        } else {
            console.log("    Bidirectional calculations match (within 1% tolerance)");
        }

        // Preview collateral ratio
        uint256 ratio = manager.previewCollateralRatio(SYNTHETIC_DOW, collateralAsset, collateralAmount, mintableAmount);

        // Get minimum required ratio
        LeprechaunFactory factory = LeprechaunFactory(LEPRECHAUN_FACTORY);
        uint256 minRatio = factory.getEffectiveCollateralRatio(SYNTHETIC_DOW, collateralAsset);

        console.log("    Collateral ratio:", ratio);
        console.log("    Minimum required ratio:", minRatio);

        if (ratio < minRatio) {
            console.log("    ERROR: Collateral ratio below minimum requirement!");
        } else {
            console.log("    Collateral ratio meets or exceeds minimum requirement");
        }
    }
}
