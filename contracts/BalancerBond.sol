// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IVault, IERC20, IAsset} from "@balancer-labs/v2-interfaces/contracts/vault/IVault.sol";

/// @dev Only `owner` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param owner Required sender address as an owner.
error OwnerOnly(address sender, address owner);

/// @dev Provided zero address.
error ZeroAddress();

/// @dev Provided zero value.
error ZeroValue();

/// @title BalancerBond - Smart contract for one click bonding
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
contract BalancerBond {
    event Joined(address indexed sender, uint256 olasAmount);

    enum WeightedPoolJoinKind {
        INIT,
        EXACT_TOKENS_IN_FOR_BPT_OUT,
        TOKEN_IN_FOR_EXACT_BPT_OUT,
        ALL_TOKENS_IN_FOR_EXACT_BPT_OUT
    }

    // Balancer Pool Id
    bytes32 public immutable balancerPoolId;
    // OLAS index in pool
    uint256 public olasIndexInPool;
    // OLAS token contract address
    address public immutable olas;
    // Balancer Vault address
    address public immutable balancerVault;

    // Pool tokens
    IERC20[] public poolTokens;
    // Also pool tokens
    IAsset[] public assets;

    /// @dev BalancerBond constructor.
    constructor(address _olas, address _balancerVault, bytes32 _balancerPoolId) {
        olas = _olas;
        balancerVault = _balancerVault;
        balancerPoolId = _balancerPoolId;

        // Get pool tokens
        (poolTokens, , ) = IVault(_balancerVault).getPoolTokens(_balancerPoolId);
        if (address(poolTokens[1]) == olas) {
            olasIndexInPool = 1;
        }

        assets[0] = IAsset(address(poolTokens[0]));
        assets[1] = IAsset(address(poolTokens[1]));
    }

    function joinPoolIterative(uint256 olasAmount, uint256 maxPartAmount, uint256 limit) external {
        require(olasAmount > 0, ZeroValue());

        uint256 numJoins = olasAmount / maxPartAmount + 1;
        for (uint256 i = 0; i < numJoins; ++i) {
            // Get OLAS amount to join
            uint256 olasAmountJoin = maxPartAmount > olasAmount ? maxPartAmount : olasAmount;

            uint256[] memory amountsIn = new uint256[](2);
            amountsIn[olasIndexInPool] = olasAmountJoin;

            // Encode the userData
            bytes memory userData = abi.encode(WeightedPoolJoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT, amountsIn, limit);
            IVault.JoinPoolRequest memory joinPoolRequest = IVault.JoinPoolRequest(assets, amountsIn, userData, false);

            IVault(balancerVault).joinPool(balancerPoolId, msg.sender, msg.sender, joinPoolRequest);

            // Adjust current OLAS amount
            olasAmount -= olasAmountJoin;

            emit Joined(msg.sender, olasAmountJoin);
        }
    }
}
