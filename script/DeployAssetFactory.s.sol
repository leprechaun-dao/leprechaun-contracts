// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {AssetFactory} from "../src/AssetFactory.sol";
import {PythPriceOracle} from "../src/PythPriceOracle.sol";
import {TokenizedAsset} from "../src/TokenizedAsset.sol";
import "../src/mocks/MockPriceOracle.sol";
import "../src/mocks/MockERC20.sol";
import "forge-std/console2.sol";

/**
 * @title DeployAssetFactory
 * @dev Deployment script for AssetFactory and related contracts
 */
contract DeployAssetFactory is Script {
    // Sample data for demo
    string constant ASSET_NAME = "Apple Inc.";
    string constant ASSET_SYMBOL = "AAPL";
    uint256 constant MIN_COLLATERAL_RATIO = 15000; // 150%
    uint256 constant LIQUIDATION_PENALTY = 1000; // 10%
    uint256 constant COLLATERAL_FACTOR = 8000; // 80%

    // Pyth price feed IDs for Base Mainnet
    bytes32 constant AAPL_PYTH_ID =
        0x49f6b65cb1de6b10eaf75e7c03ca029c306d0357e91b5311b175084a5ad55688;
    bytes32 constant USDC_PYTH_ID =
        0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a;

    function setUp() public {}

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy Pyth oracle wrapper
        address pythAddress = 0x8250f4aF4B972684F7b336503E2D6dFeDeB1487a; // Pyth on Base Mainnet
        PythPriceOracle pythOracle = new PythPriceOracle(pythAddress);

        // Deploy factory
        AssetFactory factory = new AssetFactory();

        // Registrar o price feed do AAPL
        bytes32 assetId = keccak256(abi.encodePacked(ASSET_NAME, ASSET_SYMBOL));
        pythOracle.registerAssetPriceFeed(assetId, AAPL_PYTH_ID);

        // Registrar o tipo de asset
        factory.registerAssetType(
            ASSET_NAME,
            ASSET_SYMBOL,
            address(pythOracle),
            AAPL_PYTH_ID,
            MIN_COLLATERAL_RATIO,
            LIQUIDATION_PENALTY
        );

        // Adicionar USDC como tipo de collateral
        address usdcAddress = vm.envOr(
            "USDC_ADDRESS",
            address(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913)
        ); // USDC on Base Mainnet
        factory.addCollateralType(
            usdcAddress,
            address(pythOracle),
            COLLATERAL_FACTOR
        );

        vm.stopBroadcast();

        // Log dos endereços
        console2.log("PythPriceOracle deployed to:", address(pythOracle));
        console2.log("AssetFactory deployed to:", address(factory));
    }
}
