// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ITokenizedAsset
 * @dev Interface for the TokenizedAsset contract
 */
interface ITokenizedAsset {
    /**
     * @dev Emitted when tokens are minted
     */
    event TokensMinted(address indexed to, uint256 amount);

    /**
     * @dev Emitted when tokens are burned
     */
    event TokensBurned(address indexed from, uint256 amount);

    /**
     * @dev Emitted when dividends are enabled
     */
    event DividendsEnabled(address indexed distributorAddress);

    /**
     * @dev Returns the asset ID
     */
    function assetId() external view returns (bytes32);

    /**
     * @dev Returns whether dividends are enabled
     */
    function dividendsEnabled() external view returns (bool);

    /**
     * @dev Returns the dividend distributor address
     */
    function dividendDistributor() external view returns (address);

    /**
     * @dev Mints new tokens
     * @param to Address to mint tokens to
     * @param amount Amount of tokens to mint
     */
    function mint(address to, uint256 amount) external;

    /**
     * @dev Burns tokens
     * @param from Address to burn tokens from
     * @param amount Amount of tokens to burn
     */
    function burn(address from, uint256 amount) external;

    /**
     * @dev Enables dividends for this token
     * @param distributorAddress Address of the dividend distributor contract
     */
    function enableDividends(address distributorAddress) external;
}
