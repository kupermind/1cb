// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IToken {
    /// @dev Gets the amount of tokens owned by a specified account.
    /// @param account Account address.
    /// @return Amount of tokens owned.
    function balanceOf(address account) external view returns (uint256);

    /// @dev Transfers the token amount.
    /// @param to Address to transfer to.
    /// @param amount The amount to transfer.
    /// @return True if the function execution is successful.
    function transfer(address to, uint256 amount) external returns (bool);

    /// @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
    /// @param spender Account address that will be able to transfer tokens on behalf of the caller.
    /// @param amount Token amount.
    /// @return True if the function execution is successful.
    function approve(address spender, uint256 amount) external returns (bool);

    /// @dev Transfers the token amount that was previously approved up until the maximum allowance.
    /// @param from Account address to transfer from.
    /// @param to Account address to transfer to.
    /// @param amount Amount to transfer to.
    /// @return True if the function execution is successful.
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IWETH {
    function deposit(uint256 amount) external;
}

// UniswapV2 router interface
interface IUniswapV2Router {
    /// @dev Swap exact tokens A for tokens B.
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    /// @dev Add liquidity to the pool.
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);
}

interface IPair {
    // Gets pair reserves
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 tsLast);
}

// Depository interface
interface IDepository {
    /// @dev Deposits tokens in exchange for a bond from a specified product.
    /// @param productId Product Id.
    /// @param tokenAmount Token amount to deposit for the bond.
    /// @return payout The amount of OLAS tokens due.
    /// @return maturity Timestamp for payout redemption.
    /// @return bondId Id of a newly created bond.
    function deposit(uint256 productId, uint256 tokenAmount) external
        returns (uint256 payout, uint256 maturity, uint256 bondId);

    /// @dev Redeems account bonds.
    /// @param bondIds Bond Ids to redeem.
    /// @return payout Total payout sent in OLAS tokens.
    function redeem(uint256[] memory bondIds) external returns (uint256 payout);
}

/// @dev Only `owner` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param owner Required sender address as an owner.
error OwnerOnly(address sender, address owner);

/// @dev Provided zero address.
error ZeroAddress();

/// @dev Provided zero value.
error ZeroValue();

/// @title 1cb - Smart contract for one click bonding
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
contract OneClickBond {
    event OwnerUpdated(address indexed owner);
    event Deposit(address indexed owner, uint256 olasAmount, uint256 wethAmount, uint256 liquidity, uint256 wethLeft);
    event Withdraw(address indexed owner, uint256 olasAmount);

    // Owner address
    address public owner;

    // OLAS token contract address
    address public constant OLAS = 0x0001A500A6B18995B03f44bb040A5fFc28E45CB0;
    // Treasury contract address
    address public constant TREASURY = 0xa0DA53447C0f6C4987964d8463da7e6628B30f82;
    // Depository contract address
    address public constant DEPOSITORY = 0xfF8697d8d2998d6AA2e09B405795C6F4BEeB0C81;
    // UniswapV2 router address
    address public constant ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    // WETH token address
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    // LP token address
    address public constant PAIR = 0x09D1d767eDF8Fa23A64C51fa559E0688E526812F;
    // Reserves limit for a swap (% * 100)
    uint256 public constant SWAP_LIMIT = 200;
    // Reserves limit denominator
    uint256 public constant SWAP_DENOMINATOR = 10000;

    /// @dev OneClickBond constructor.
    constructor() {
        owner = msg.sender;
    }

    /// @dev Changes the owner address.
    /// @param newOwner Address of a new owner.
    function changeOwner(address newOwner) external {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for the zero address
        if (newOwner == address(0)) {
            revert ZeroAddress();
        }

        owner = newOwner;
        emit OwnerUpdated(newOwner);
    }

    /// @dev Deposit ETH and/or WETH to create OLAS-WETH LP and bond.
    /// @param amount WETH amount.
    /// @param productId Bonding product Id.
    function depositETH(uint256 amount, uint256 productId) external payable {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for the amount value
        if (amount == 0 && msg.value == 0) {
            revert ZeroValue();
        }

        // Get LP reserves
        (, uint112 reserve1, uint32 tsLast) = IPair(PAIR).getReserves();

        // Check that the last block timestamp is not the current block timestamp
        if (block.timestamp == tsLast) {
            revert();
        }

        // Check if ETH to WETH is needed
        if (msg.value > 0) {
            IWETH(WETH).deposit(msg.value);
        }

        // Transfer tokens from the owner to this contract
        if (amount > 0) {
            IToken(WETH).transferFrom(msg.sender, address(this), amount);
        }

        // Combine ETH and WETH amounts
        amount += msg.value;

        // Get the WETH amount that is a half of the overall amount
        uint256 wethAmount = amount / 2;

        // Swap amount must not be bigger than 2%, otherwise it might hurt the pool price significantly
        if (wethAmount > reserve1 * SWAP_LIMIT / SWAP_DENOMINATOR) {
            revert();
        }

        // Approve OLAS for the router
        IToken(WETH).approve(ROUTER, amount);

        // Get the token path
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = OLAS;

        // Swap WETH to OLAS
        uint256[] memory swapAmounts = IUniswapV2Router(ROUTER).swapExactTokensForTokens(
            wethAmount,
            1,
            path,
            address(this),
            block.timestamp + 1000
        );

        // Get the amount of OLAS received
        uint256 olasAmount = swapAmounts[1];

        // Approve OLAS to the router
        IToken(OLAS).approve(ROUTER, olasAmount);

        // Add liquidity
        (uint256 olasAmountLP, uint256 wethAmountLP, uint256 liquidity) = IUniswapV2Router(ROUTER).addLiquidity(
            OLAS,
            WETH,
            olasAmount,
            wethAmount,
            1,
            1,
            address(this),
            block.timestamp + 1000
        );

        // Check the liquidity amount
        if (liquidity == 0) {
            revert ZeroValue();
        }

        // Approve LP tokens for treasury
        IToken(PAIR).approve(TREASURY, liquidity);

        // Deposit liquidity into the bonding product
        IDepository(DEPOSITORY).deposit(productId, liquidity);

        // Transfer WETH leftovers back to the owner
        wethAmount -= wethAmountLP;
        if (wethAmount > 0) {
            IToken(WETH).transfer(msg.sender, wethAmount);
        }

        emit Deposit(msg.sender, olasAmountLP, wethAmountLP, liquidity, wethAmount);
    }

    /// @dev Deposit OLAS to create OLAS-WETH LP and bond.
    /// @param amount OLAS amount.
    /// @param productId Bonding product Id.
    function depositOLAS(uint256 amount, uint256 productId) external {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for the amount value
        if (amount == 0) {
            revert ZeroValue();
        }

        // Get LP reserves
        (uint112 reserve0, , uint32 tsLast) = IPair(PAIR).getReserves();

        // Check that the last block timestamp is not the current block timestamp
        if (block.timestamp == tsLast) {
            revert();
        }

        // Transfer tokens from the owner to this contract
        IToken(OLAS).transferFrom(msg.sender, address(this), amount);

        // Get the OLAS amount that is a half of the overall amount
        uint256 olasAmount = amount / 2;

        // Swap amount must not be bigger than 2%, otherwise it might hurt the pool price significantly
        if (olasAmount > reserve0 * SWAP_LIMIT / SWAP_DENOMINATOR) {
            revert();
        }

        // Approve OLAS for the router
        IToken(OLAS).approve(ROUTER, amount);

        // Get the token path
        address[] memory path = new address[](2);
        path[0] = OLAS;
        path[1] = WETH;

        // Swap OLAS to WETH
        uint256[] memory swapAmounts = IUniswapV2Router(ROUTER).swapExactTokensForTokens(
            olasAmount,
            1,
            path,
            address(this),
            block.timestamp + 1000
        );

        // Get the amount of WETH received
        uint256 wethAmount = swapAmounts[1];

        // Approve WETH to the router
        IToken(WETH).approve(ROUTER, wethAmount);

        // Add liquidity
        (uint256 olasAmountLP, uint256 wethAmountLP, uint256 liquidity) = IUniswapV2Router(ROUTER).addLiquidity(
            OLAS,
            WETH,
            olasAmount,
            wethAmount,
            1,
            1,
            address(this),
            block.timestamp + 1000
        );


        if (liquidity == 0) {
            revert ZeroValue();
        }

        // Approve LP tokens for treasury
        IToken(PAIR).approve(TREASURY, liquidity);

        // Deposit liquidity into the bonding product
        IDepository(DEPOSITORY).deposit(productId, liquidity);

        // Transfer WETH leftovers back to the owner
        wethAmount -= wethAmountLP;
        if (wethAmount > 0) {
            IToken(WETH).transfer(msg.sender, wethAmount);
        }

        emit Deposit(msg.sender, olasAmountLP, wethAmountLP, liquidity, wethAmount);
    }

    /// @dev Withdraw OLAS (and WETH) from redeemed bonds.
    /// @param bondIds Bond Ids.
    function withdraw(uint256[] memory bondIds) external {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Redeem bonds
        IDepository(DEPOSITORY).redeem(bondIds);

        // Get OLAS balance
        uint256 olasAmount = IToken(OLAS).balanceOf(address(this));

        // Transfer OLAS back to the owner
        IToken(OLAS).transfer(msg.sender, olasAmount);

        emit Withdraw(msg.sender, olasAmount);
    }

    function getMaxSwapResevres() external view returns (uint256 olasAmount, uint256 wethAmount) {
        // Get LP reserves
        (uint112 reserve0, uint112 reserve1, ) = IPair(PAIR).getReserves();
        olasAmount = 2 * reserve0 * SWAP_LIMIT / SWAP_DENOMINATOR;
        wethAmount = 2 * reserve1 * SWAP_LIMIT / SWAP_DENOMINATOR;
    }
}
