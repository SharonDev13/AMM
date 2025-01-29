// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./sec.sol";

contract AMM is ERC20, ReentrancyGuard {
    address public token1;
    address public token2;
    uint256 public feeRate; // Total fee in basis points (e.g., 50 = 0.5%)
    uint256 public token1Reserve;
    uint256 public token2Reserve;
    bool public initialized;
        uint256 public collectedFeesToken1;
    uint256 public collectedFeesToken2;

    struct LimitOrder {
        address user;
        address inputToken;
        address outputToken;
        uint256 inputAmount;
        uint256 minOutputAmount;
        uint256 expiration;
        bool active;
    }

    mapping(uint256 => LimitOrder) public limitOrders;
    uint256 public orderCounter;

    event LiquidityAdded(address indexed provider, uint256 token1Amount, uint256 token2Amount, uint256 liquidity);
    event LiquidityRemoved(address indexed provider, uint256 token1Amount, uint256 token2Amount, uint256 liquidity);
    event TokenSwap(address indexed swapper, address inputToken, address outputToken, uint256 inputAmount, uint256 outputAmount);
     event LimitOrderPlaced(uint256 orderId, address indexed user, address indexed inputToken, address indexed outputToken, uint256 inputAmount, uint256 minOutputAmount, uint256 expiration);
    event LimitOrderExecuted(uint256 orderId, address indexed user, uint256 outputAmount);
    error AlreadyInitialized();
    error InvalidInitializationParams();
    
    constructor() ERC20("RareBay-V2-AMM", "RARE-LP") {}

    function initialize(address _token1, address _token2, uint256 _feeRate) external {
        require(!initialized, "Already initialized");
        require(_feeRate <= 10000, "Fee rate too high");
        require(_token1 != _token2, "Tokens must be different");

        token1 = _token1;
        token2 = _token2;
        feeRate = _feeRate;
        initialized = true;
    }

    function getAmountOut(uint256 inputAmount, address inputToken, address outputToken) public view returns (uint256) {
        ERC20 input = ERC20(inputToken);
        ERC20 output = ERC20(outputToken);

        uint256 inputReserve = input.balanceOf(address(this));
        uint256 outputReserve = output.balanceOf(address(this));

        require(inputReserve > 0 && outputReserve > 0, "Insufficient liquidity");

        uint256 feeAmount = (inputAmount * feeRate) / 10000;
        uint256 inputAmountWithFee = inputAmount - feeAmount;

        uint256 numerator = inputAmountWithFee * outputReserve;
        uint256 denominator = inputReserve + inputAmountWithFee;

        return numerator / denominator;
    }
function placeLimitOrder(
    address inputToken,
    address outputToken,
    uint256 inputAmount,
    uint256 minOutputAmount,
    uint256 expiration
) external nonReentrant returns (uint256) {
    require(inputAmount > 0, "Invalid input amount");
    require(outputToken != address(0), "Invalid output token");
    require(block.timestamp < expiration, "Invalid expiration");

    // Calculate the fee (0.5%)
    uint256 feeAmount = (inputAmount * 5) / 1000;
    uint256 netInputAmount = inputAmount - feeAmount;

    // Calculate the expected output amount after fee deduction
    uint256 expectedOutputAmount = getAmountOut(netInputAmount, inputToken, outputToken);
    
    // Slippage protection: Ensure the expected output is not less than the minimum output
    require(expectedOutputAmount >= minOutputAmount, "Slippage protection: Output too low");

    // Collect fee
    if (inputToken == token1) {
        collectedFeesToken1 += feeAmount;
    } else if (inputToken == token2) {
        collectedFeesToken2 += feeAmount;
    } else {
        revert("Invalid input token");
    }

    // Transfer tokens from user to contract (only net amount is used in order)
    ERC20(inputToken).transferFrom(msg.sender, address(this), inputAmount);

    // Store the order with the net amount
    orderCounter++;
    limitOrders[orderCounter] = LimitOrder({
        user: msg.sender,
        inputToken: inputToken,
        outputToken: outputToken,
        inputAmount: netInputAmount, // Order is placed with the post-fee amount
        minOutputAmount: minOutputAmount,
        expiration: expiration,
        active: true
    });

    emit LimitOrderPlaced(orderCounter, msg.sender, inputToken, outputToken, netInputAmount, minOutputAmount, expiration);
    return orderCounter;
}


function executeLimitOrder(uint256 orderId) external nonReentrant {
    LimitOrder storage order = limitOrders[orderId];
    require(order.active, "Order not active");
    require(block.timestamp <= order.expiration, "Order expired");

    // Calculate output using the net amount (already fee deducted)
    uint256 outputAmount = getAmountOut(order.inputAmount, order.inputToken, order.outputToken);
    require(outputAmount >= order.minOutputAmount, "Output too low");

    // Mark order as executed
    order.active = false;

    // Send tokens to user
    ERC20(order.outputToken).transfer(order.user, outputAmount);

    emit LimitOrderExecuted(orderId, order.user, outputAmount);
}


    function swapTokens(
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 minOutputAmount
    ) public nonReentrant returns (uint256 outputAmount) {
        require(inputToken == token1 || inputToken == token2, "Invalid input token");
        require(outputToken == token1 || outputToken == token2, "Invalid output token");
        require(inputToken != outputToken, "Tokens must be different");

        uint256 feeAmount = (inputAmount * feeRate) / 10000;
        uint256 amountAfterFee = inputAmount - feeAmount;

        outputAmount = getAmountOut(amountAfterFee, inputToken, outputToken);
        require(outputAmount >= minOutputAmount, "Slippage protection failed");

        ERC20(inputToken).transferFrom(msg.sender, address(this), inputAmount);
        ERC20(outputToken).transfer(msg.sender, outputAmount);

        // Update reserves
        if (inputToken == token1) {
            token1Reserve += inputAmount;
            token2Reserve -= outputAmount;
        } else {
            token2Reserve += inputAmount;
            token1Reserve -= outputAmount;
        }

        emit TokenSwap(msg.sender, inputToken, outputToken, inputAmount, outputAmount);
    }

    function addLiquidity(uint256 token1Amount, uint256 token2Amount) public nonReentrant returns (uint256 liquidity) {
        require(token1Amount > 0 && token2Amount > 0, "Amounts must be greater than zero");

        ERC20(token1).transferFrom(msg.sender, address(this), token1Amount);
        ERC20(token2).transferFrom(msg.sender, address(this), token2Amount);

        if (token1Reserve == 0 && token2Reserve == 0) {
            liquidity = sqrt(token1Amount * token2Amount);
        } else {
            require(token1Reserve > 0 && token2Reserve > 0, "Reserves must be greater than zero");
            uint256 token1Required = (token2Amount * token1Reserve) / token2Reserve;
            uint256 token2Required = (token1Amount * token2Reserve) / token1Reserve;
            require(token1Amount >= token1Required && token2Amount >= token2Required, "Incorrect ratio");
            liquidity = (totalSupply() * token2Amount) / token2Reserve;
        }

        require(liquidity > 0, "Insufficient liquidity minted");
        _mint(msg.sender, liquidity);

        token1Reserve += token1Amount;
        token2Reserve += token2Amount;

        emit LiquidityAdded(msg.sender, token1Amount, token2Amount, liquidity);
    }

    function removeLiquidity(uint256 liquidity, uint256 minToken1Amount, uint256 minToken2Amount) public nonReentrant returns (uint256 token1Amount, uint256 token2Amount) {
        require(liquidity > 0, "Invalid liquidity amount");

        token1Amount = (token1Reserve * liquidity) / totalSupply();
        token2Amount = (token2Reserve * liquidity) / totalSupply();

        require(token1Amount >= minToken1Amount && token2Amount >= minToken2Amount, "Slippage protection failed");

        _burn(msg.sender, liquidity);

        token1Reserve -= token1Amount;
        token2Reserve -= token2Amount;

        ERC20(token1).transfer(msg.sender, token1Amount);
        ERC20(token2).transfer(msg.sender, token2Amount);

        emit LiquidityRemoved(msg.sender, token1Amount, token2Amount, liquidity);
    }

    function sqrt(uint256 x) internal pure returns (uint256 y) {
        uint256 z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        return y;
    }
}
