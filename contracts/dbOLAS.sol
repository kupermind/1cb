// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "../lib/solmate/src/tokens/ERC20.sol";

/// @dev Only `owner` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param owner Required sender address as an owner.
error OwnerOnly(address sender, address owner);

/// @title dOLAS - Smart contract for dOLAS token
/// @dev Derived Bonded OLAS token contract is owned by the bonding manager contract,
///      where dbOLAS token must be minted and burned solely by the bonding contract.
contract dbOLAS is ERC20 {
    // Token owner - bonding manager contract
    address public immutable owner;

    constructor() ERC20("Derived Bonded OLAS", "dbOLAS", 18) {
        owner = msg.sender;
    }

    /// @dev Mints bridged tokens.
    /// @param account Account address.
    /// @param amount Bridged token amount.
    function mint(address account, uint256 amount) external {
        // Only the contract owner is allowed to mint
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }
        
        _mint(account, amount);
    }

    /// @dev Burns bridged tokens.
    /// @param amount Bridged token amount to burn.
    function burn(uint256 amount) external {
        // Only the contract owner is allowed to burn
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        _burn(msg.sender, amount);
    }
}