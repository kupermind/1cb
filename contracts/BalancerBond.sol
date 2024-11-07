// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IVault {
    /// @dev Returns a Pool's registered tokens, the total balance for each, and the latest block when/// any* of
    /// the tokens' `balances` changed.
    /// 
    /// The order of the `tokens` array is the same order that will be used in `joinPool`, `exitPool`, as well as in all
    /// Pool hooks (where applicable). Calls to `registerTokens` and `deregisterTokens` may change this order.
    /// 
    /// If a Pool only registers tokens once, and these are sorted in ascending order, they will be stored in the same
    /// order as passed to `registerTokens`.
    /// 
    /// Total balances include both tokens held by the Vault and those withdrawn by the Pool's Asset Managers. These are
    /// the amounts used by joins, exits and swaps. For a detailed breakdown of token balances, use `getPoolTokenInfo`
    /// instead.
    function getPoolTokens(bytes32 poolId) external view returns (address[] memory tokens, uint256[] memory balances,
        uint256 lastChangeBlock);

    struct JoinPoolRequest {
        address[] assets;
        uint256[] maxAmountsIn;
        bytes userData;
        bool fromInternalBalance;
    }
    
    /// @dev Called by users to join a Pool, which transfers tokens from `sender` into the Pool's balance. This will
    /// trigger custom Pool behavior, which will typically grant something in return to `recipient` - often tokenized
    /// Pool shares.
    /// 
    /// If the caller is not `sender`, it must be an authorized relayer for them.
    /// 
    /// The `assets` and `maxAmountsIn` arrays must have the same length, and each entry indicates the maximum amount
    /// to send for each asset. The amounts to send are decided by the Pool and not the Vault: it just enforces
    /// these maximums.
    /// 
    /// If joining a Pool that holds WETH, it is possible to send ETH directly: the Vault will do the wrapping. To enable
    /// this mechanism, the IAsset sentinel value (the zero address) must be passed in the `assets` array instead of the
    /// WETH address. Note that it is not possible to combine ETH and WETH in the same join. Any excess ETH will be sent
    /// back to the caller (not the sender, which is important for relayers).
    /// 
    /// `assets` must have the same length and order as the array returned by `getPoolTokens`. This prevents issues when
    /// interacting with Pools that register and deregister tokens frequently. If sending ETH however, the array must be
    /// sorted/// before* replacing the WETH address with the ETH sentinel value (the zero address), which means the final
    /// `assets` array might not be sorted. Pools with no registered tokens cannot be joined.
    /// 
    /// If `fromInternalBalance` is true, the caller's Internal Balance will be preferred: ERC20 transfers will only
    /// be made for the difference between the requested amount and Internal Balance (if any). Note that ETH cannot be
    /// withdrawn from Internal Balance: attempting to do so will trigger a revert.
    /// 
    /// This causes the Vault to call the `IBasePool.onJoinPool` hook on the Pool's contract, where Pools implement
    /// their own custom logic. This typically requires additional information from the user (such as the expected number
    /// of Pool shares). This can be encoded in the `userData` argument, which is ignored by the Vault and passed
    /// directly to the Pool's contract, as is `recipient`.
    /// 
    /// Emits a `PoolBalanceChanged` event.
    function joinPool(bytes32 poolId, address sender, address recipient, JoinPoolRequest memory request) external payable;
}

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
    address[] public poolTokens;

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
            IVault.JoinPoolRequest memory joinPoolRequest = IVault.JoinPoolRequest(poolTokens, amountsIn, userData, false);

            IVault(balancerVault).joinPool(balancerPoolId, msg.sender, msg.sender, joinPoolRequest);

            // Adjust current OLAS amount
            olasAmount -= olasAmountJoin;

            emit Joined(msg.sender, olasAmountJoin);
        }
    }
}
