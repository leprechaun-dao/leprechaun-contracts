// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IAssetFactory
 * @dev Interface for the AssetFactory contract
 */
interface IAssetFactory {
    /**
     * @dev Struct representing a tokenized asset type
     */
    struct AssetType {
        bytes32 assetId; // Unique identifier for the asset
        string assetName; // Name of the asset
        string assetSymbol; // Symbol of the asset
        address tokenAddress; // Address of the ERC20 token contract
        address oracleAddress; // Address of the price oracle
        uint256 minCollateralRatio; // Minimum collateralization ratio (in basis points)
        uint256 liquidationThreshold; // Threshold for liquidation (in basis points)
        uint256 liquidationPenalty; // Penalty for liquidation (in basis points)
        bool isActive; // Whether the asset is active
    }

    /**
     * @dev Struct representing a collateral type
     */
    struct CollateralType {
        address tokenAddress; // Address of the collateral token
        address oracleAddress; // Address of the price oracle
        uint256 collateralFactor; // Collateral factor (in basis points)
        bool isActive; // Whether the collateral is active
    }

    /**
     * @dev Registers a new asset type in the protocol
     */
    function registerAssetType(
        string memory name,
        string memory symbol,
        address oracleAddress,
        bytes32 pythPriceFeedId,
        uint256 minCollateralRatio,
        uint256 liquidationPenalty
    ) external returns (bytes32 assetId);

    /**
     * @dev Set the maximum staleness for price feeds
     */
    function setMaxPriceStaleness(uint256 staleness) external;

    /**
     * @dev Adds a collateral type to the protocol
     */
    function addCollateralType(
        address tokenAddress,
        address oracleAddress,
        uint256 collateralFactor
    ) external;

    /**
     * @dev Removes a collateral type from the protocol
     */
    function removeCollateralType(address tokenAddress) external;

    /**
     * @dev Updates parameters for an asset type
     */
    function updateAssetParameters(
        bytes32 assetId,
        uint256 minCollateralRatio,
        uint256 liquidationPenalty
    ) external;

    /**
     * @dev Get all registered asset types
     */
    function getAllAssetTypes() external view returns (AssetType[] memory);

    /**
     * @dev Get all registered collateral types
     */
    function getAllCollateralTypes()
        external
        view
        returns (CollateralType[] memory);

    /**
     * @dev Check if a collateral type is active
     */
    function isCollateralActive(
        address tokenAddress
    ) external view returns (bool);

    /**
     * @dev Get token address for an asset ID
     */
    function getTokenAddress(bytes32 assetId) external view returns (address);

    /**
     * @dev Get Pyth price feed ID for an asset
     */
    function getPythPriceFeedId(
        bytes32 assetId
    ) external view returns (bytes32);

    /**
     * @dev Get asset price in USD (normalized to 18 decimals)
     */
    function getAssetPrice(
        bytes32 assetId
    ) external view returns (uint256 price, uint256 publishTime);
}
