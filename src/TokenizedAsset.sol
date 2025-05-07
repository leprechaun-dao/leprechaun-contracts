// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/ITokenizedAsset.sol";

/**
 * @title TokenizedAsset
 * @dev ERC20 token representing a tokenized real-world asset
 */
contract TokenizedAsset is ITokenizedAsset, ERC20, Ownable {
    // The asset ID in the factory
    bytes32 public assetId;

    // Indicates if dividends are enabled for this token
    bool public dividendsEnabled;

    // Address of dividend distributor contract (if enabled)
    address public dividendDistributor;

    /**
     * @dev Constructor creates a new tokenized asset
     * @param name Name of the token
     * @param symbol Symbol of the token
     * @param factoryAddress Address of the AssetFactory that created this token
     */
    constructor(
        string memory name,
        string memory symbol,
        address factoryAddress
    ) ERC20(name, symbol) Ownable(factoryAddress) {
        // Set asset ID
        assetId = keccak256(abi.encodePacked(name, symbol));
    }

    /**
     * @dev Mint new tokens
     * @param to Address to mint tokens to
     * @param amount Amount of tokens to mint
     */
    function mint(address to, uint256 amount) external onlyOwner {
        require(to != address(0), "TokenizedAsset: mint to zero address");
        _mint(to, amount);
        emit TokensMinted(to, amount);
    }

    /**
     * @dev Burn tokens
     * @param from Address to burn tokens from
     * @param amount Amount of tokens to burn
     */
    function burn(address from, uint256 amount) external onlyOwner {
        require(from != address(0), "TokenizedAsset: burn from zero address");
        _burn(from, amount);
        emit TokensBurned(from, amount);
    }

    /**
     * @dev Enable dividends for this token
     * @param distributorAddress Address of the dividend distributor contract
     */
    function enableDividends(address distributorAddress) external onlyOwner {
        require(
            distributorAddress != address(0),
            "TokenizedAsset: distributor cannot be zero address"
        );
        require(!dividendsEnabled, "TokenizedAsset: dividends already enabled");

        dividendsEnabled = true;
        dividendDistributor = distributorAddress;

        emit DividendsEnabled(distributorAddress);
    }

    /**
     * @dev Hook that is called before any transfer of tokens
     * This can be used for dividend distribution tracking if needed
     */
    function _update(
        address from,
        address to,
        uint256 amount
    ) internal override {
        super._update(from, to, amount);

        // This is a placeholder for future dividend functionality
        if (dividendsEnabled && dividendDistributor != address(0)) {}
    }
}
