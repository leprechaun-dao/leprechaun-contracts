// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {PythStructs} from "./PythStructs.sol";

/**
 * @title IPyth
 * @dev Interface for Pyth Network contract (simplified)
 */
interface IPyth {
    /**
     * @dev Get the price for a price feed
     * @param id The Pyth price feed ID
     */
    function getPriceUnsafe(
        bytes32 id
    ) external view returns (PythStructs.Price memory);

    /**
     * @dev Get the price for a price feed, ensuring the price is no more than maxAge seconds old
     * @param id The Pyth price feed ID
     */
    function getPrice(
        bytes32 id
    ) external view returns (PythStructs.Price memory);

    /**
     * @dev Get the price for a price feed, ensuring the price is no more than age seconds old
     * @param id The Pyth price feed ID
     * @param age The maximum age of the price feed in seconds
     */
    function getPriceNoOlderThan(
        bytes32 id,
        uint256 age
    ) external view returns (PythStructs.Price memory);

    /**
     * @dev Get the price for a price feed, ensuring the price is no more than age seconds old
     * @param id The Pyth price feed ID
     */
    function getEmaPriceUnsafe(
        bytes32 id
    ) external view returns (PythStructs.Price memory);

    /**
     * @dev Get the price for a price feed, ensuring the price is no more than age seconds old
     * @param id The Pyth price feed ID
     */
    function getEmaPrice(
        bytes32 id
    ) external view returns (PythStructs.Price memory);

    /**
     * @dev Get the price for a price feed, ensuring the price is no more than age seconds old
     * @param id The Pyth price feed ID
     * @param age The maximum age of the price feed in seconds
     */
    function getEmaPriceNoOlderThan(
        bytes32 id,
        uint256 age
    ) external view returns (PythStructs.Price memory);

    /**
     * @dev Calculate the fee for updating price feeds
     * @param updateData The price update data
     * @return feeAmount The required fee in wei
     */
    function getUpdateFee(
        bytes[] calldata updateData
    ) external view returns (uint256 feeAmount);

    /**
     * @dev Update price feeds with the given update data
     * @param updateData The price update data
     */
    function updatePriceFeeds(bytes[] calldata updateData) external payable;

    /**
     * @dev Update price feeds with the given update data if necessary
     * @param updateData The price update data
     * @param priceIds The list of price IDs
     * @param publishTimes The list of publish times
     */
    function updatePriceFeedsIfNecessary(
        bytes[] calldata updateData,
        bytes32[] calldata priceIds,
        uint256[] calldata publishTimes
    ) external payable;

    /**
     * @dev Parse price feed updates from the given data
     * @param updateData The price update data
     * @param priceIds The list of price IDs
     * @param minPublishTime The minimum publish time
     * @param maxPublishTime The maximum publish time
     * @return priceFeeds The list of price feeds
     */
    function parsePriceFeedUpdates(
        bytes[] calldata updateData,
        bytes32[] calldata priceIds,
        uint256 minPublishTime,
        uint256 maxPublishTime
    ) external payable returns (PythStructs.PriceFeed[] memory priceFeeds);
}
