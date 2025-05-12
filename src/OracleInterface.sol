// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/IPyth.sol";
import "./interfaces/PythStructs.sol";

/**
 * @title OracleInterface
 * @dev Interface for oracle price feeds (using Pyth)
 */
contract OracleInterface {
    IPyth public pyth;

    // Mapping of asset address to Pyth price feed ID
    mapping(address => bytes32) public priceFeedIds;

    // Maximum price staleness (in seconds)
    uint256 public constant MAX_PRICE_AGE = 60;

    // Events
    event PriceFeedRegistered(address indexed asset, bytes32 feedId);
    event PriceUpdated(address indexed asset, int64 price, uint256 timestamp);

    /**
     * @dev Constructor
     * @param _pythAddress The address of the Pyth contract
     */
    constructor(address _pythAddress) {
        require(_pythAddress != address(0), "Invalid Pyth address");
        pyth = IPyth(_pythAddress);
    }

    /**
     * @dev Register a price feed for an asset
     * @param asset The address of the asset
     * @param feedId The Pyth price feed ID
     */
    function registerPriceFeed(address asset, bytes32 feedId) external {
        require(asset != address(0), "Invalid asset address");
        require(feedId != bytes32(0), "Invalid feed ID");
        require(
            priceFeedIds[asset] == bytes32(0),
            "Price feed already registered"
        );

        priceFeedIds[asset] = feedId;

        emit PriceFeedRegistered(asset, feedId);
    }

    /**
     * @dev Update price for a specific asset using Pyth price update data
     * @param asset The address of the asset
     * @param updateData The Pyth price update data
     */
    function updatePrice(
        address asset,
        bytes[] calldata updateData
    ) external payable {
        bytes32 feedId = priceFeedIds[asset];
        require(feedId != bytes32(0), "Price feed not registered");

        // Update the price feed with the provided update data
        uint256 fee = pyth.getUpdateFee(updateData);
        pyth.updatePriceFeeds{value: fee}(updateData);

        // Get the updated price
        PythStructs.Price memory price = pyth.getPrice(feedId);

        emit PriceUpdated(asset, price.price, price.publishTime);
    }

    /**
     * @dev Get the latest price for an asset
     * @param asset The address of the asset
     * @return price The price in USD (scaled by 10^8)
     * @return timestamp The timestamp of the price
     * @return decimals The number of decimals in the price
     */
    function getPrice(
        address asset
    ) external view returns (int64 price, uint256 timestamp, int32 decimals) {
        bytes32 feedId = priceFeedIds[asset];
        require(feedId != bytes32(0), "Price feed not registered");

        // Get the price from Pyth
        PythStructs.Price memory pythPrice = pyth.getPrice(feedId);

        // Check if price is stale
        require(
            block.timestamp - pythPrice.publishTime <= MAX_PRICE_AGE,
            "Price is stale"
        );

        return (pythPrice.price, pythPrice.publishTime, pythPrice.expo);
    }

    /**
     * @dev Check if a price feed is registered for an asset
     * @param asset The address of the asset
     * @return registered Whether the price feed is registered
     */
    function isPriceFeedRegistered(address asset) external view returns (bool) {
        return priceFeedIds[asset] != bytes32(0);
    }

    /**
     * @dev Get the USD value of a token amount
     * @param asset The address of the asset
     * @param amount The amount of tokens
     * @param assetDecimals The number of decimals in the asset
     * @return value The USD value of the tokens (scaled by 10^18)
     */
    function getUsdValue(
        address asset,
        uint256 amount,
        uint8 assetDecimals
    ) external view returns (uint256 value) {
        (int64 price, , int32 priceExpo) = this.getPrice(asset);
        require(price > 0, "Invalid price");

        // Convert price to positive (safe because we checked price > 0)
        uint256 positivePrice = uint256(uint64(price));

        // Calculate base value (amount * price)
        value = amount * positivePrice;

        // Adjust for price exponent
        if (priceExpo != 0) {
            if (priceExpo < 0) {
                value = value / (10 ** uint256(uint32(-priceExpo)));
            } else {
                value = value * (10 ** uint256(uint32(priceExpo)));
            }
        }

        // Adjust for token decimals
        value = value / (10 ** uint256(assetDecimals));

        return value;
    }
}
