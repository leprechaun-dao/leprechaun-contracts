// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/LeprechaunFactory.sol";
import "../src/PositionManager.sol";
import "../src/Lens.sol";

/**
 * @title DeployLensScript
 * @dev Script to deploy the Leprechaun Lens contract
 */
contract DeployLensScript is Script {
    function run() external {
        // Get the addresses of the main contracts from .env or use defaults
        address factoryAddress = vm.envOr("FACTORY_ADDRESS", address(0));
        address positionManagerAddress = vm.envOr("POSITION_MANAGER_ADDRESS", address(0));

        // Make sure addresses are set
        require(factoryAddress != address(0), "Factory address not set");
        require(positionManagerAddress != address(0), "Position Manager address not set");

        // Start broadcasting transactions
        vm.startBroadcast();

        // Deploy the Lens contract
        LeprechaunLens lens = new LeprechaunLens(factoryAddress, positionManagerAddress);

        // End broadcast
        vm.stopBroadcast();

        // Log the deployment results
        console.log("\n=== Leprechaun Protocol Lens Deployed ===");
        console.log("Lens Contract: ", address(lens));
        console.log("Factory: ", factoryAddress);
        console.log("Position Manager: ", positionManagerAddress);

        // Test the Lens contract with some basic queries
        console.log("\n=== Testing Lens Contract ===");

        // Get protocol info
        LeprechaunLens.ProtocolInfo memory protocolInfo = lens.getProtocolInfo();

        console.log("Protocol Fee: ", protocolInfo.fee, "basis points");
        console.log("Fee Collector: ", protocolInfo.collector);
        console.log("Oracle Address: ", protocolInfo.oracleAddress);
        console.log("Owner: ", protocolInfo.owner);
        console.log("Synthetic Asset Count: ", protocolInfo.assetCount);
        console.log("Collateral Type Count: ", protocolInfo.collateralCount);

        console.log("\nLens contract verification complete!");
    }
}
