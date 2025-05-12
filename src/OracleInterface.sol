// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/IPyth.sol";
import "./interfaces/PythStructs.sol";

/**
 * @title OracleInterface
 * @dev Interface for oracle price feeds using the Pyth Network
 *      This contract provides a standardized way to access price data for both
 *      synthetic assets and collateral types in the Leprechaun protocol.
 *      It handles price feed registration, updates, and value conversion
 *      while enforcing maximum staleness requirements for price data.
 */
contract OracleInterface {
    /**
     * @dev Reference to the Pyth Network contract that provides price data
     */
    IPyth public pyth;

    /**
     * @dev Mapping of asset addresses to their corresponding Pyth price feed IDs
     */
    mapping(address => bytes32) public priceFeedIds;

    /**
     * @dev Maximum allowed age for price data in seconds
     *      Prices older than this threshold are considered stale and will be rejected
     */
    uint256 public constant MAX_PRICE_AGE = 60; // 60 seconds

    // Events
    /**
     * @dev Emitted when a new price feed is registered for an asset
     * @param asset The address of the asset (synthetic or collateral)
     * @param feedId The Pyth price feed ID assigned to the asset
     */
    event PriceFeedRegistered(address indexed asset, bytes32 feedId);

    /**
     * @dev Emitted when a price is updated for an asset
     * @param asset The address of the asset
     * @param price The new price value (scaled by 10^8)
     * @param timestamp The timestamp when the price was published
     */
    event PriceUpdated(address indexed asset, int64 price, uint256 timestamp);

    /**
     * @dev Constructor
     * @param _pythAddress The address of the Pyth contract on the current chain
     * @notice Initializes the oracle interface with a connection to the Pyth Network
     */
    constructor(address _pythAddress) {
        require(_pythAddress != address(0), "Invalid Pyth address");
        pyth = IPyth(_pythAddress);
    }

    /**
     * @dev Register a price feed for an asset
     * @param asset The address of the asset (synthetic or collateral)
     * @param feedId The Pyth price feed ID for the asset's price data
     * @notice Only one price feed can be registered per asset
     * @notice This function is called by the LeprechaunFactory when registering new assets
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
     * @param updateData The Pyth price update data (obtained from Pyth Network)
     * @notice This function requires payment of a fee to the Pyth Network
     * @notice The fee is determined by the Pyth Network based on the update data
     * @notice This function should be called regularly to keep prices up-to-date
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
