// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/LeprechaunFactory.sol";
import "../src/PositionManager.sol";
import "../src/OracleInterface.sol";
import "../src/SyntheticAsset.sol";

contract VerifyDeploymentScript is Script {
    // Contract addresses
    address constant LEPRECHAUN_FACTORY = 0x5c7FF36e0BB492c81d85e501C8ce9a418618A4eD;
    address constant POSITION_MANAGER = 0xA202BBa404427dEa715D0ca424FB7dA337fF3a46;
    address constant ORACLE_INTERFACE = 0x3979eeBA732A0d8B422557f489E381e6ee2DD1F8;
    address constant SYNTHETIC_DOW = 0x9E623E30bddA40464945cf14777CA990BE2Ba984;
    address constant MOCK_USDC = 0x26bb5E0E1b93440720cebFCdD94CaA7B515af1cf;
    address constant MOCK_WETH = 0x9FB8bc690C3Dcf32464062f27658A42C87F25C26;
    address constant MOCK_WBTC = 0xE157a88bDaFf6487408131b8369CaaE56691E562;
    address constant PYTH_ORACLE = 0xff1a0f4744e8582DF1aE09D5611b887B6a12925C;

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

        console.log("\n========== VERIFICATION COMPLETE ==========\n");
    }

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

        // Check feed IDs (this requires custom function in OracleInterface to expose them)
        console.log("  Note: Cannot verify price feed IDs directly as they're not exposed via public getters");

        console.log("OracleInterface verification complete.");
    }

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
            (address tokenAddress, uint256 multiplier, bool isActive) = factory.collateralTypes(collateralAddress);

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
        // console.log(
        //     "    mUSDC:",
        //     usdcRatio,
        //     "(Expected:",
        //     expectedUsdcRatio,
        //     ")"
        // );
        // console.log(
        //     "    mWETH:",
        //     wethRatio,
        //     "(Expected:",
        //     expectedWethRatio,
        //     ")"
        // );
        // console.log(
        //     "    mWBTC:",
        //     wbtcRatio,
        //     "(Expected:",
        //     expectedWbtcRatio,
        //     ")"
        // );

        // if (
        //     usdcRatio != expectedUsdcRatio ||
        //     wethRatio != expectedWethRatio ||
        //     wbtcRatio != expectedWbtcRatio
        // ) {
        //     console.log(
        //         "  ERROR: Some effective collateral ratios don't match expected values!"
        //     );
        // }

        // console.log("Collateral Allowances verification complete.");
    }
}
