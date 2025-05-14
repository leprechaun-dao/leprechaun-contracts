// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/LeprechaunFactory.sol";
import "../src/PositionManager.sol";
import "../src/Lens.sol";
import "../src/OracleInterface.sol";
import "../src/SyntheticAsset.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title LeprechaunTargetRatioInteraction
 * @dev Script to interact with the Leprechaun protocol:
 *      1. Calculate mint amount for a specific target ratio
 *      2. Create a position with the calculated mint amount
 */
contract LeprechaunTargetRatioInteraction is Script {
    // Contract addresses - replace with your actual deployed addresses
    address constant POSITION_MANAGER =
        0x401d1cD4D0ff1113458339065Cf9a1f2e8425afb;
    address constant LEPRECHAUN_FACTORY =
        0x364A6127A8b425b6857f4962412b0664D257BDD5;
    address constant LENS_CONTRACT = 0x80d4D0e68efDBB8b16fdD1e8ff7511ecc3869503; // Replace with actual address
    address constant SYNTHETIC_ASSET =
        0xD14F0B478F993967240Aa5995eb2b1Ca6810969a; // sDOW
    address constant MOCK_USDC = 0x39510c9f9E577c65b9184582745117341e7bdD73;

    // Interface declarations
    PositionManager positionManager;
    LeprechaunFactory factory;
    LeprechaunLens lens;
    SyntheticAsset syntheticAsset;
    IERC20 collateralToken;

    // Position tracking
    uint256 positionId;

    function run() external {
        // Use the private key from the environment variable
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address user = vm.addr(privateKey);

        // Initialize contract interfaces
        positionManager = PositionManager(POSITION_MANAGER);
        factory = LeprechaunFactory(LEPRECHAUN_FACTORY);
        lens = LeprechaunLens(LENS_CONTRACT);
        syntheticAsset = SyntheticAsset(SYNTHETIC_ASSET);
        collateralToken = IERC20(MOCK_USDC);

        console.log("Leprechaun Protocol Target Ratio Interaction");
        console.log("=============================================");
        console.log("User address:", user);

        // Start broadcasting transactions
        vm.startBroadcast(privateKey);

        // Step 1: Set parameters
        uint256 collateralAmount = 500 * 10 ** 6; // 500 USDC (6 decimals)
        uint256 targetRatio = 25000; // 250% collateralization (in basis points)

        console.log("\n1. Setting up parameters...");
        console.log("   Collateral: 500 USDC");
        console.log("   Target ratio: 250%");

        // Step 2: Calculate the mint amount for target ratio
        console.log("\n2. Calculating mint amount for target ratio...");

        (
            uint256 mintAmount,
            uint256 maxMintable,
            uint256 effectiveRatio,
            uint256 minRequiredRatio
        ) = lens.calculateMintAmountForTargetRatio(
                SYNTHETIC_ASSET,
                MOCK_USDC,
                collateralAmount,
                targetRatio
            );

        console.log(
            "   Mint amount for 250% ratio:",
            mintAmount / 10 ** 18,
            "synthetic tokens"
        );
        console.log(
            "   Maximum mintable amount:",
            maxMintable / 10 ** 18,
            "synthetic tokens"
        );
        console.log("   Effective ratio:", effectiveRatio / 100, "%");
        console.log("   Minimum required ratio:", minRequiredRatio / 100, "%");

        // Step 3: Get a complete position preview
        console.log("\n3. Getting complete position preview...");

        (
            ,
            // mintAmount (already have this)
            uint256 collateralUsdValue,
            uint256 syntheticUsdValue, // effectiveRatio (already have this)
            ,

        ) = lens.previewPositionWithTargetRatio(
                SYNTHETIC_ASSET,
                MOCK_USDC,
                collateralAmount,
                targetRatio
            );

        console.log(
            "   Collateral USD value: $",
            collateralUsdValue / 10 ** 18
        );
        console.log("   Synthetic USD value: $", syntheticUsdValue / 10 ** 18);
        console.log(
            "   USD ratio:",
            (collateralUsdValue * 100) / syntheticUsdValue,
            "%"
        );

        // Step 4: Approve tokens to be used by Position Manager
        console.log("\n4. Approving tokens for Position Manager...");
        collateralToken.approve(POSITION_MANAGER, collateralAmount);
        console.log(" Approved Position Manager to spend USDC");

        // Step 5: Create a position with the calculated mint amount
        console.log("\n5. Creating position with target ratio...");
        positionId = positionManager.createPosition(
            SYNTHETIC_ASSET,
            MOCK_USDC,
            collateralAmount,
            mintAmount
        );
        console.log("Position created! Position ID:", positionId);

        // Step 6: Verify the created position
        (
            address owner,
            address syntheticAssetAddr,
            address collateralAssetAddr,
            uint256 actualCollateral,
            uint256 actualMinted,
            ,
            bool isActive
        ) = positionManager.getPosition(positionId);

        console.log("\n6. Verifying created position:");
        console.log("   Owner:", owner);
        console.log("   Synthetic asset:", syntheticAssetAddr);
        console.log("   Collateral asset:", collateralAssetAddr);
        console.log(
            "   Collateral amount:",
            actualCollateral / 10 ** 6,
            "USDC"
        );
        console.log(
            "   Minted amount:",
            actualMinted / 10 ** 18,
            "synthetic tokens"
        );
        console.log("Is active:", isActive);

        // Step 7: Get actual collateral ratio
        uint256 actualRatio = positionManager.getCollateralRatio(positionId);
        console.log(
            "\n7. Actual position collateral ratio:",
            actualRatio / 100,
            "%"
        );

        // Check if it matches the target
        if (actualRatio >= targetRatio) {
            console.log("Target ratio achieved!");
        } else {
            console.log("Actual ratio is below target. Review calculation.");
        }

        // Step 8: Check synthetic token balance
        uint256 syntheticBalance = syntheticAsset.balanceOf(user);
        console.log(
            "\n8. Synthetic token balance:",
            syntheticBalance / 10 ** 18
        );

        // End broadcast
        vm.stopBroadcast();

        console.log("\nScript completed successfully!");
    }
}
