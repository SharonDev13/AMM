// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./AMM.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./sec.sol";

contract AMMFactory is ReentrancyGuard {
    struct Pool {
        address token1;
        address token2;
        address poolAddress;
        uint256 feeRate; // Fee rate in basis points (e.g., 0.05% = 5 basis points)
    }

    struct LiquidityPosition {
        address poolAddress;
        uint256 token1Amount;
        uint256 token2Amount;
        uint256 liquidityShares;
    }

    // Array to store unique pools
    Pool[] public pools;

    // Mapping to check if a pool already exists
    mapping(address => bool) public poolExists;

    // Mapping to track user liquidity positions
    mapping(address => LiquidityPosition[]) public userPositions;

    event PoolCreated(address indexed poolAddress, address indexed token1, address indexed token2);
    event LiquidityAdded(address indexed poolAddress, address indexed user, uint256 token1Amount, uint256 token2Amount, uint256 liquidityShares);
    event LiquidityRemoved(address indexed poolAddress, address indexed user, uint256 token1Amount, uint256 token2Amount, uint256 liquidityShares);

    constructor() {}

    // Create a new pool
    function createPool(
        address token1,
        address token2,
        uint256 feeRate
    ) public returns (address) {
        require(token1 != token2, "Tokens must be different");
        require(token1 != address(0) && token2 != address(0), "Invalid token addresses");

        // Check if the pool already exists
        if (poolExists[token1] && poolExists[token2]) {
            revert("Pool already exists");
        }

        // Deploy the AMM contract
        AMM newPool = new AMM();

        // Initialize the pool with the token addresses and fee rate
        newPool.initialize(token1, token2, feeRate);

        // Add to the pool list
        pools.push(Pool({
            token1: token1,
            token2: token2,
            poolAddress: address(newPool),
            feeRate: feeRate
        }));

        // Mark the pool as existing
        poolExists[token1] = true;
        poolExists[token2] = true;

        emit PoolCreated(address(newPool), token1, token2);
        return address(newPool);
    }

    // Function to view a user's liquidity positions
    function getUserPositions(address user) public view returns (LiquidityPosition[] memory) {
        return userPositions[user];
    }

    // Function to filter positions by pool
    function getUserPositionsByPool(address user, address pool) public view returns (LiquidityPosition[] memory) {
        uint256 count = 0;
        
        // Count positions in the specified pool
        for (uint256 i = 0; i < userPositions[user].length; i++) {
            if (userPositions[user][i].poolAddress == pool) {
                count++;
            }
        }

        // Create filtered array
        LiquidityPosition[] memory filteredPositions = new LiquidityPosition[](count);
        uint256 index = 0;

        for (uint256 i = 0; i < userPositions[user].length; i++) {
            if (userPositions[user][i].poolAddress == pool) {
                filteredPositions[index] = userPositions[user][i];
                index++;
            }
        }

        return filteredPositions;
    }

    // Function to get pool details
    function getPoolDetails(address poolAddress) public view returns (
        address token1,
        address token2,
        uint256 feeRate
    ) {
        Pool storage pool = getPoolByAddress(poolAddress);
        return (
            pool.token1,
            pool.token2,
            pool.feeRate
        );
    }

    // Helper function to get the pool by address
    function getPoolByAddress(address poolAddress) internal view returns (Pool storage) {
        for (uint256 i = 0; i < pools.length; i++) {
            if (pools[i].poolAddress == poolAddress) {
                return pools[i];
            }
        }
        revert("Pool not found");
    }
}
