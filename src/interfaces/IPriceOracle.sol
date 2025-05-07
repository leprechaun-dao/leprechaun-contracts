// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IPriceOracle
 * @dev Interface for price oracle contracts using Pyth Network
 */
interface IPriceOracle {
    /**
     * @dev Struct representing a price with confidence interval and metadata
     */
    struct PriceData {
        int64 price; // Price value in Pyth format (signed)
        uint64 conf; // Confidence interval
        int32 expo; // Price exponent (e.g., -8 for 8 decimal places)
        uint256 publishTime; // Timestamp when the price was published
    }

    /**
     * @dev Get latest price data for an asset
     * @param assetId ID of the asset
     * @return price PriceData struct containing price information
     */
    function getLatestPriceData(
        bytes32 assetId
    ) external view returns (PriceData memory price);

    /**
     * @dev Get normalized price value for an asset in USD (18 decimals)
     * @param assetId ID of the asset
     * @return price Price in USD (18 decimals precision)
     * @return publishTime Timestamp when the price was published
     */
    function getNormalizedPrice(
        bytes32 assetId
    ) external view returns (uint256 price, uint256 publishTime);

    /**
     * @dev Check if price is stale (not updated recently)
     * @param assetId ID of the asset
     * @param maxAge Maximum age in seconds
     * @return True if price is stale
     */
    function isPriceStale(
        bytes32 assetId,
        uint256 maxAge
    ) external view returns (bool);

    /**
     * @dev Get Pyth Network price feed ID for a given asset
     * @param assetId Protocol's asset ID
     * @return pythId Pyth price feed ID
     */
    function getPythPriceFeedId(
        bytes32 assetId
    ) external view returns (bytes32 pythId);
}
