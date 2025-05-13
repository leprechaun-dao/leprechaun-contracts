// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/LeprechaunFactory.sol";
import "../src/PositionManager.sol";
import "../src/OracleInterface.sol";
import "../src/SyntheticAsset.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title LeprechaunInteractionScript
 * @dev Script to interact with the Leprechaun protocol:
 *      1. Mint test collateral tokens
 *      2. Create a position
 *      3. Add more collateral
 *      4. Mint more synthetic tokens
 */
contract LeprechaunInteractionScript is Script {
    // Contract addresses - replace with your actual deployed addresses
    address constant POSITION_MANAGER =
        0x401d1cD4D0ff1113458339065Cf9a1f2e8425afb;
    address constant LEPRECHAUN_FACTORY =
        0x364A6127A8b425b6857f4962412b0664D257BDD5;
    address constant SYNTHETIC_ASSET =
        0xD14F0B478F993967240Aa5995eb2b1Ca6810969a; // sDOW
    address constant MOCK_USDC = 0x39510c9f9E577c65b9184582745117341e7bdD73;

    // Interface declarations
    PositionManager positionManager;
    LeprechaunFactory factory;
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
        syntheticAsset = SyntheticAsset(SYNTHETIC_ASSET);
        collateralToken = IERC20(MOCK_USDC);

        console.log("Leprechaun Protocol Interaction Script");
        console.log("=======================================");
        console.log("User address:", user);

        // Start broadcasting transactions
        vm.startBroadcast(privateKey);

        // Step 1: Mint collateral tokens (assuming the token has a mint function)
        // This would work with your MockToken but might need adjustment for real tokens
        console.log("\n1. Minting collateral tokens...");

        // Casting to interface with mint function - adjust if using real tokens
        try MockToken(MOCK_USDC).mint(user, 1_000_000 * 10 ** 6) {
            console.log("Minted 1,000,000 USDC tokens to user");
        } catch {
            console.log("Minting failed - this is expected with real tokens");
            console.log("Continue with existing token balance");
        }

        // Get current balance
        uint256 initialBalance = collateralToken.balanceOf(user);
        console.log("Current USDC balance:", initialBalance / 10 ** 6, "USDC");

        // Step 2: Approve tokens to be used by Position Manager
        console.log("\n2. Approving tokens for Position Manager...");
        collateralToken.approve(POSITION_MANAGER, type(uint256).max);
        console.log("Approved Position Manager to spend USDC");

        // Step 3: Calculate mintable amount
        console.log("\n3. Calculating mintable amount...");
        uint256 collateralAmount = 500 * 10 ** 6; // 500 USDC
        uint256 mintableAmount = positionManager.getMintableAmount(
            SYNTHETIC_ASSET,
            MOCK_USDC,
            collateralAmount
        );
        console.log(
            "With 500 USDC as collateral, you can mint:",
            mintableAmount / 10 ** 18,
            "synthetic tokens"
        );

        // Step 4: Create a position
        console.log("\n4. Creating position...");
        uint256 mintAmount = (mintableAmount * 90) / 100; // Use 90% of max mintable for safety
        positionId = positionManager.createPosition(
            SYNTHETIC_ASSET,
            MOCK_USDC,
            collateralAmount,
            mintAmount
        );
        console.log("Position created! Position ID:", positionId);

        // Step 5: Check synthetic token balance
        console.log("\n5. Checking synthetic token balance...");
        uint256 syntheticBalance = syntheticAsset.balanceOf(user);
        console.log("Synthetic token balance:", syntheticBalance / 10 ** 18);

        // Get collateral ratio
        uint256 initialRatio = positionManager.getCollateralRatio(positionId);
        console.log("Initial collateral ratio:", initialRatio / 100, "%");

        // Step 6: Add more collateral to the position
        console.log("\n6. Adding more collateral...");
        uint256 additionalCollateral = 200 * 10 ** 6; // 200 USDC
        positionManager.depositCollateral(positionId, additionalCollateral);
        console.log("Added 200 USDC as additional collateral");

        // Step 7: Get current collateral ratio
        console.log("\n7. Checking updated collateral ratio...");
        uint256 newRatio = positionManager.getCollateralRatio(positionId);
        console.log("Updated collateral ratio:", newRatio / 100, "%");

        // Step 8: Get updated position data
        (
            address owner,
            address syntheticAssetAddr,
            address collateralAssetAddr,
            uint256 currentCollateral,
            uint256 currentMintedAmount,
            ,
            bool isActive
        ) = positionManager.getPosition(positionId);

        console.log("\n8. Current position data:");
        console.log("  Owner:", owner);
        console.log("  Synthetic asset:", syntheticAssetAddr);
        console.log("  Collateral asset:", collateralAssetAddr);
        console.log(
            "  Collateral amount:",
            currentCollateral / 10 ** 6,
            "USDC"
        );
        console.log(
            "  Minted amount:",
            currentMintedAmount / 10 ** 18,
            "synthetic tokens"
        );
        console.log("  Is active:", isActive);

        // Step 9: Calculate how much more can be minted with the new collateral
        console.log("\n9. Calculating additional mintable amount...");
        uint256 totalMintableAmount = positionManager.getMintableAmount(
            SYNTHETIC_ASSET,
            MOCK_USDC,
            currentCollateral
        );
        uint256 additionalMintable = totalMintableAmount - currentMintedAmount;
        console.log(
            "Additional mintable amount:",
            additionalMintable / 10 ** 18,
            "synthetic tokens"
        );

        // Step 10: Mint additional synthetic tokens
        console.log("\n10. Minting additional synthetic tokens...");
        uint256 mintMoreAmount = (additionalMintable * 90) / 100; // Use 90% of additional mintable for safety
        positionManager.mintSyntheticAsset(positionId, mintMoreAmount);
        console.log("Minted additional synthetic tokens");

        // Step 11: Final position status
        console.log("\n11. Final position status...");

        // Get updated position data
        (
            ,
            ,
            ,
            uint256 finalCollateral,
            uint256 finalMintedAmount,
            ,

        ) = positionManager.getPosition(positionId);

        uint256 finalRatio = positionManager.getCollateralRatio(positionId);
        uint256 finalSyntheticBalance = syntheticAsset.balanceOf(user);

        console.log("  Final collateral:", finalCollateral / 10 ** 6, "USDC");
        console.log(
            "  Final minted amount:",
            finalMintedAmount / 10 ** 18,
            "synthetic tokens"
        );
        console.log("  Final collateral ratio:", finalRatio / 100, "%");
        console.log(
            "  Final synthetic token balance:",
            finalSyntheticBalance / 10 ** 18
        );

        // End broadcast
        vm.stopBroadcast();

        console.log("\nScript completed successfully!");
    }
}

// Interface for MockToken - only used to attempt minting in the test environment
interface MockToken {
    function mint(address to, uint256 amount) external;
}
