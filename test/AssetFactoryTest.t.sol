// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/AssetFactory.sol";
import "../src/TokenizedAsset.sol";
import "../src/mocks/MockPriceOracle.sol";
import "../src/mocks/MockERC20.sol";

contract AssetFactoryTest is Test {
    AssetFactory public factory;
    MockPriceOracle public oracle;
    MockERC20 public collateralToken;

    address public owner = address(1);
    address public user = address(2);

    // Test values
    string public constant ASSET_NAME = "Apple Inc.";
    string public constant ASSET_SYMBOL = "AAPL";
    uint256 public constant MIN_COLLATERAL_RATIO = 15000; // 150%
    uint256 public constant LIQUIDATION_PENALTY = 1000; // 10%
    uint256 public constant COLLATERAL_FACTOR = 8000; // 80%

    // Pyth Network price feed IDs (simulated for testing)
    bytes32 public constant AAPL_PYTH_ID = bytes32(uint256(1));
    bytes32 public constant USDC_PYTH_ID = bytes32(uint256(2));

    // Asset price for testing ($200 with 8 decimals)
    int64 public constant ASSET_PRICE = 20000000000;
    uint64 public constant ASSET_CONF = 1000000000; // $10 confidence
    int32 public constant ASSET_EXPO = -8; // 8 decimal places

    bytes32 public assetId;

    function setUp() public {
        // Deploy contracts
        vm.startPrank(owner);

        factory = new AssetFactory();
        oracle = new MockPriceOracle();
        collateralToken = new MockERC20("USD Coin", "USDC", 6);

        // Set up oracle price and register price feed
        assetId = keccak256(abi.encodePacked(ASSET_NAME, ASSET_SYMBOL));
        oracle.registerAssetPriceFeed(assetId, AAPL_PYTH_ID);
        oracle.setMockPrice(assetId, ASSET_PRICE, ASSET_CONF, ASSET_EXPO);

        // Also set up collateral token price feed
        bytes32 collateralId = keccak256(abi.encodePacked("USD Coin", "USDC"));
        oracle.registerAssetPriceFeed(collateralId, USDC_PYTH_ID);
        oracle.setMockPrice(collateralId, 100000000, 1000000, -8); // $1.00 with 8 decimals

        // Mint some tokens to user
        collateralToken.mint(user, 10000 * 10 ** 6); // 10,000 USDC

        vm.stopPrank();
    }

    function testRegisterAssetType() public {
        vm.startPrank(owner);

        // Register asset type
        bytes32 returnedAssetId = factory.registerAssetType(
            ASSET_NAME,
            ASSET_SYMBOL,
            address(oracle),
            AAPL_PYTH_ID,
            MIN_COLLATERAL_RATIO,
            LIQUIDATION_PENALTY
        );

        // Verify asset ID
        assertEq(returnedAssetId, assetId, "Asset ID mismatch");

        // Get asset details
        IAssetFactory.AssetType memory asset = factory.getAssetType(assetId);

        // Verify asset details
        assertEq(asset.assetName, ASSET_NAME, "Asset name mismatch");
        assertEq(asset.assetSymbol, ASSET_SYMBOL, "Asset symbol mismatch");
        assertEq(
            asset.oracleAddress,
            address(oracle),
            "Oracle address mismatch"
        );
        assertEq(
            asset.minCollateralRatio,
            MIN_COLLATERAL_RATIO,
            "Min collateral ratio mismatch"
        );
        assertEq(
            asset.liquidationPenalty,
            LIQUIDATION_PENALTY,
            "Liquidation penalty mismatch"
        );
        assertTrue(asset.isActive, "Asset not active");

        // Verify token address is set and token is deployed
        address tokenAddress = asset.tokenAddress;
        assertTrue(tokenAddress != address(0), "Token address not set");

        // Verify Pyth price feed ID
        bytes32 pythId = factory.getPythPriceFeedId(assetId);
        assertEq(pythId, AAPL_PYTH_ID, "Pyth ID mismatch");

        // Verify token contract
        TokenizedAsset token = TokenizedAsset(tokenAddress);
        assertEq(token.name(), ASSET_NAME, "Token name mismatch");
        assertEq(token.symbol(), ASSET_SYMBOL, "Token symbol mismatch");
        assertEq(token.owner(), address(factory), "Token owner mismatch");

        vm.stopPrank();
    }

    function testGetAssetPrice() public {
        vm.startPrank(owner);

        // Register asset type
        factory.registerAssetType(
            ASSET_NAME,
            ASSET_SYMBOL,
            address(oracle),
            AAPL_PYTH_ID,
            MIN_COLLATERAL_RATIO,
            LIQUIDATION_PENALTY
        );

        // Get price from factory
        (uint256 price, uint256 publishTime) = factory.getAssetPrice(assetId);

        // Verify price conversion (from -8 decimals to 18 decimals)
        // ASSET_PRICE = 20000000000 with 8 decimals = $200
        // Convert to 18 decimals: 200 * 10^18 = 200 * 10^(18+8) = 200 * 10^26
        uint256 expectedPrice = uint256(uint64(ASSET_PRICE)) * 10 ** 26;
        assertEq(price, expectedPrice, "Price conversion mismatch");

        // Verify publish time
        assertEq(publishTime, block.timestamp, "Publish time mismatch");

        vm.stopPrank();
    }

    function testAddCollateralType() public {
        vm.startPrank(owner);

        // Add collateral type
        factory.addCollateralType(
            address(collateralToken),
            address(oracle),
            COLLATERAL_FACTOR
        );

        // Verify collateral type
        IAssetFactory.CollateralType memory collateral = factory
            .getCollateralType(address(collateralToken));

        assertEq(
            collateral.tokenAddress,
            address(collateralToken),
            "Collateral token address mismatch"
        );
        assertEq(
            collateral.oracleAddress,
            address(oracle),
            "Collateral oracle address mismatch"
        );
        assertEq(
            collateral.collateralFactor,
            COLLATERAL_FACTOR,
            "Collateral factor mismatch"
        );
        assertTrue(collateral.isActive, "Collateral not active");

        // Verify it's in the list
        address listedToken = factory.allCollateralTokens(0);
        assertEq(
            listedToken,
            address(collateralToken),
            "Collateral not in list"
        );

        vm.stopPrank();
    }

    function testRemoveCollateralType() public {
        vm.startPrank(owner);

        // Add collateral type
        factory.addCollateralType(
            address(collateralToken),
            address(oracle),
            COLLATERAL_FACTOR
        );

        // Remove collateral type
        factory.removeCollateralType(address(collateralToken));

        // Verify it's inactive
        IAssetFactory.CollateralType memory collateral = factory
            .getCollateralType(address(collateralToken));
        assertFalse(collateral.isActive, "Collateral still active");

        // Verify function returns correct value
        bool isActive = factory.isCollateralActive(address(collateralToken));
        assertFalse(isActive, "isCollateralActive returns wrong value");

        vm.stopPrank();
    }

    function testUpdateAssetParameters() public {
        vm.startPrank(owner);

        // Register asset type
        bytes32 returnedAssetId = factory.registerAssetType(
            ASSET_NAME,
            ASSET_SYMBOL,
            address(oracle),
            AAPL_PYTH_ID,
            MIN_COLLATERAL_RATIO,
            LIQUIDATION_PENALTY
        );

        // New parameters
        uint256 newRatio = 20000; // 200%
        uint256 newPenalty = 1500; // 15%

        // Update parameters
        factory.updateAssetParameters(returnedAssetId, newRatio, newPenalty);

        // Verify updated parameters
        IAssetFactory.AssetType memory asset = factory.getAssetType(
            returnedAssetId
        );
        assertEq(
            asset.minCollateralRatio,
            newRatio,
            "Min collateral ratio not updated"
        );
        assertEq(
            asset.liquidationPenalty,
            newPenalty,
            "Liquidation penalty not updated"
        );

        vm.stopPrank();
    }

    function testStalePriceReverts() public {
        vm.startPrank(owner);

        // Register asset type
        factory.registerAssetType(
            ASSET_NAME,
            ASSET_SYMBOL,
            address(oracle),
            AAPL_PYTH_ID,
            MIN_COLLATERAL_RATIO,
            LIQUIDATION_PENALTY
        );

        // Set max staleness to a small value
        factory.setMaxPriceStaleness(1); // 1 second

        // Warp time forward
        vm.warp(block.timestamp + 10);

        // Try to get price (should revert due to staleness)
        vm.expectRevert("AssetFactory: price is stale");
        factory.getAssetPrice(assetId);

        vm.stopPrank();
    }

    function testGetAllAssetTypes() public {
        vm.startPrank(owner);

        // Register multiple asset types
        factory.registerAssetType(
            ASSET_NAME,
            ASSET_SYMBOL,
            address(oracle),
            AAPL_PYTH_ID,
            MIN_COLLATERAL_RATIO,
            LIQUIDATION_PENALTY
        );

        factory.registerAssetType(
            "Microsoft Corporation",
            "MSFT",
            address(oracle),
            bytes32(uint256(3)), // Different Pyth ID
            MIN_COLLATERAL_RATIO,
            LIQUIDATION_PENALTY
        );

        // Get all asset types
        IAssetFactory.AssetType[] memory assets = factory.getAllAssetTypes();

        // Verify count
        assertEq(assets.length, 2, "Wrong number of assets");

        // Verify first asset
        assertEq(assets[0].assetName, ASSET_NAME, "First asset name mismatch");
        assertEq(
            assets[0].assetSymbol,
            ASSET_SYMBOL,
            "First asset symbol mismatch"
        );

        // Verify second asset
        assertEq(
            assets[1].assetName,
            "Microsoft Corporation",
            "Second asset name mismatch"
        );
        assertEq(assets[1].assetSymbol, "MSFT", "Second asset symbol mismatch");

        vm.stopPrank();
    }

    function testGetAllCollateralTypes() public {
        vm.startPrank(owner);

        // Add multiple collateral types
        factory.addCollateralType(
            address(collateralToken),
            address(oracle),
            COLLATERAL_FACTOR
        );

        MockERC20 wethToken = new MockERC20("Wrapped Ether", "WETH", 18);
        factory.addCollateralType(
            address(wethToken),
            address(oracle),
            7000 // 70% factor
        );

        // Get all collateral types
        IAssetFactory.CollateralType[] memory collaterals = factory
            .getAllCollateralTypes();

        // Verify count
        assertEq(collaterals.length, 2, "Wrong number of collaterals");

        // Verify first collateral
        assertEq(
            collaterals[0].tokenAddress,
            address(collateralToken),
            "First collateral address mismatch"
        );
        assertEq(
            collaterals[0].collateralFactor,
            COLLATERAL_FACTOR,
            "First collateral factor mismatch"
        );

        // Verify second collateral
        assertEq(
            collaterals[1].tokenAddress,
            address(wethToken),
            "Second collateral address mismatch"
        );
        assertEq(
            collaterals[1].collateralFactor,
            7000,
            "Second collateral factor mismatch"
        );

        vm.stopPrank();
    }

    function testOnlyOwnerCanRegisterAsset() public {
        vm.prank(user);

        // Try to register asset as non-owner (should revert)
        vm.expectRevert(
            abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user)
        );
        factory.registerAssetType(
            ASSET_NAME,
            ASSET_SYMBOL,
            address(oracle),
            AAPL_PYTH_ID,
            MIN_COLLATERAL_RATIO,
            LIQUIDATION_PENALTY
        );
    }

    function testOnlyOwnerCanAddCollateral() public {
        vm.prank(user);

        // Try to add collateral as non-owner (should revert)
        vm.expectRevert(
            abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user)
        );
        factory.addCollateralType(
            address(collateralToken),
            address(oracle),
            COLLATERAL_FACTOR
        );
    }
}
