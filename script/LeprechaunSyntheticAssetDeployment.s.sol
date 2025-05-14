// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/LeprechaunFactory.sol";
import "../src/PositionManager.sol";
import "../src/OracleInterface.sol";
import "../src/SyntheticAsset.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title LeprechaunSyntheticAssetDeployment
 * @dev Script to deploy two new synthetic assets to the Leprechaun protocol
 */
contract LeprechaunSyntheticAssetDeployment is Script {
    // Contract addresses - replace with your actual deployed addresses
    address constant LEPRECHAUN_FACTORY =
        0x364A6127A8b425b6857f4962412b0664D257BDD5;
    address constant POSITION_MANAGER =
        0x401d1cD4D0ff1113458339065Cf9a1f2e8425afb;

    // Collateral tokens
    address constant USDC = 0x39510c9f9E577c65b9184582745117341e7bdD73;
    address constant WETH = 0x95539ce7555F53dACF3a79Ff760C06e5B4e310c3;
    address constant WBTC = 0x1DBf5683c73E0D0A0e20AfC76F924e08E95637F7;

    // Pyth price feed IDs - real price feeds provided by the user
    bytes32 constant GOLD_XAU_USD_FEED_ID =
        0x765d2ba906dbc32ca17cc11f5310a89e9ee1f6420508c63861f2f8ba4ee34bb2;
    bytes32 constant US_OIL_FEED_ID =
        0x925ca92ff005ae943c158e3563f59698ce7e75c5a8c8dd43303a0a154887b3e6;

    // Protocol risk parameters
    uint256 constant MIN_COLLATERAL_RATIO = 15000; // 150%
    uint256 constant MEDIUM_VOLATILITY_RATIO = 16500; // 165%
    uint256 constant HIGH_VOLATILITY_RATIO = 18000; // 180%
    uint256 constant AUCTION_DISCOUNT = 1000; // 10%

    // Interface declarations
    LeprechaunFactory factory;

    function run() external {
        // Use the private key from the environment variable
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(privateKey);

        // Initialize factory interface
        factory = LeprechaunFactory(LEPRECHAUN_FACTORY);

        console.log("Deploying New Synthetic Assets");
        console.log("===============================");
        console.log("Deployer address:", deployer);
        console.log("Factory address:", LEPRECHAUN_FACTORY);
        console.log("Position Manager address:", POSITION_MANAGER);

        // Start broadcasting transactions
        vm.startBroadcast(privateKey);

        // 1. DEPLOY SYNTHETIC GOLD (sGOLD/sXAU)
        console.log("\n1. Deploying Synthetic Gold (sXAU)...");

        // Register sXAU with the Gold/XAU price feed and medium volatility collateral ratio
        factory.registerSyntheticAsset(
            "Synthetic Gold",
            "sXAU",
            MEDIUM_VOLATILITY_RATIO, // Medium volatility for gold
            AUCTION_DISCOUNT,
            GOLD_XAU_USD_FEED_ID,
            POSITION_MANAGER
        );

        // Get the address of the newly created synthetic asset
        address sXAU = factory.allSyntheticAssets(
            factory.getSyntheticAssetCount() - 1
        );

        console.log(" sXAU deployed at:", sXAU);

        // Allow all collateral types for sXAU
        console.log("   Configuring allowed collateral for sXAU...");
        factory.allowCollateralForAsset(sXAU, USDC);
        factory.allowCollateralForAsset(sXAU, WETH);
        factory.allowCollateralForAsset(sXAU, WBTC);

        console.log(" Collateral types configured for sXAU");

        // 2. DEPLOY SYNTHETIC US OIL (sOIL)
        console.log("\n2. Deploying Synthetic US Oil (sOIL)...");

        // Register sOIL with the US Oil price feed and high volatility collateral ratio
        factory.registerSyntheticAsset(
            "Synthetic US Oil",
            "sOIL",
            HIGH_VOLATILITY_RATIO, // High volatility for oil prices
            AUCTION_DISCOUNT,
            US_OIL_FEED_ID,
            POSITION_MANAGER
        );

        // Get the address of the newly created synthetic asset
        address sOIL = factory.allSyntheticAssets(
            factory.getSyntheticAssetCount() - 1
        );

        console.log(" sOIL deployed at:", sOIL);

        // Allow all collateral types for sOIL
        console.log("   Configuring allowed collateral for sOIL...");
        factory.allowCollateralForAsset(sOIL, USDC);
        factory.allowCollateralForAsset(sOIL, WETH);
        factory.allowCollateralForAsset(sOIL, WBTC);

        console.log(" Collateral types configured for sOIL");

        // 3. Verify the synthetic assets
        console.log("\n3. Verifying deployed synthetic assets...");

        // Verify sXAU configuration
        (
            address sXAUTokenAddress,
            string memory sXAUName,
            string memory sXAUSymbol,
            uint256 sXAUMinRatio,
            uint256 sXAUAuctionDiscount,
            bool sXAUIsActive
        ) = factory.syntheticAssets(sXAU);

        console.log("\n   sXAU Configuration:");
        console.log("   - Token Address:", sXAUTokenAddress);
        console.log("   - Name:", sXAUName);
        console.log("   - Symbol:", sXAUSymbol);
        console.log("   - Min Collateral Ratio:", sXAUMinRatio / 100, "%");
        console.log("   - Auction Discount:", sXAUAuctionDiscount / 100, "%");
        console.log("   - Is Active:", sXAUIsActive);

        // Verify collateral is allowed for sXAU
        bool isUsdcAllowedForGold = factory.allowedCollateral(sXAU, USDC);
        bool isWethAllowedForGold = factory.allowedCollateral(sXAU, WETH);
        bool isWbtcAllowedForGold = factory.allowedCollateral(sXAU, WBTC);

        console.log("   - USDC allowed as collateral:", isUsdcAllowedForGold);
        console.log("   - WETH allowed as collateral:", isWethAllowedForGold);
        console.log("   - WBTC allowed as collateral:", isWbtcAllowedForGold);

        // Verify sOIL configuration
        (
            address sOILTokenAddress,
            string memory sOILName,
            string memory sOILSymbol,
            uint256 sOILMinRatio,
            uint256 sOILAuctionDiscount,
            bool sOILIsActive
        ) = factory.syntheticAssets(sOIL);

        console.log("\n   sOIL Configuration:");
        console.log("   - Token Address:", sOILTokenAddress);
        console.log("   - Name:", sOILName);
        console.log("   - Symbol:", sOILSymbol);
        console.log("   - Min Collateral Ratio:", sOILMinRatio / 100, "%");
        console.log("   - Auction Discount:", sOILAuctionDiscount / 100, "%");
        console.log("   - Is Active:", sOILIsActive);

        // Verify collateral is allowed for sOIL
        bool isUsdcAllowedForOil = factory.allowedCollateral(sOIL, USDC);
        bool isWethAllowedForOil = factory.allowedCollateral(sOIL, WETH);
        bool isWbtcAllowedForOil = factory.allowedCollateral(sOIL, WBTC);

        console.log("   - USDC allowed as collateral:", isUsdcAllowedForOil);
        console.log("   - WETH allowed as collateral:", isWethAllowedForOil);
        console.log("   - WBTC allowed as collateral:", isWbtcAllowedForOil);

        // End broadcast
        vm.stopBroadcast();

        // 4. Summary of deployed assets
        console.log("\n4. Deployment Summary:");
        console.log("   sXAU (Gold) address:", sXAU);
        console.log("   sOIL (US Oil) address:", sOIL);

        console.log("\nScript completed successfully!");
    }
}
