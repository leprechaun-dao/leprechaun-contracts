// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title SyntheticAsset
 * @dev An ERC20 token representing a synthetic asset
 */
contract SyntheticAsset is ERC20 {
    // The address of the position manager that can mint and burn tokens
    address public positionManager;

    // Event emitted when the token is deactivated
    event TokenDeactivated();

    /**
     * @dev Constructor
     * @param name_ The name of the token
     * @param symbol_ The symbol of the token
     * @param _positionManager The initial position manager that can mint and burn tokens
     */
    constructor(
        string memory name_,
        string memory symbol_,
        address _positionManager
    ) ERC20(name_, symbol_) {
        require(
            _positionManager != address(0),
            "Invalid position manager address"
        );
        positionManager = _positionManager;
    }

    /**
     * @dev Mint new tokens
     * @param to The address to mint tokens to
     * @param amount The amount of tokens to mint
     */
    function mint(address to, uint256 amount) external {
        require(
            msg.sender == positionManager,
            "Only position manager can mint"
        );

        _mint(to, amount);
    }

    /**
     * @dev Burn tokens
     * @param from The address to burn tokens from
     * @param amount The amount of tokens to burn
     */
    function burn(address from, uint256 amount) external {
        require(
            msg.sender == positionManager,
            "Only position manager can burn"
        );

        _burn(from, amount);
    }
}
