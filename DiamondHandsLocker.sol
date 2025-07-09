// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract DiamondHandsLocker is ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    struct Lock {
        address user;
        IERC20 token;
        uint256 amount;
        uint256 releaseTime;
        bool withdrawn;
    }

    uint256 public lockIdCounter = 1; // Start from 1 to avoid 0 lockId
    mapping(uint256 => Lock) public locks;
    mapping(address => uint256[]) public userLocks;
    
    // Stats
    uint256 public totalLocks;
    uint256 public activeLocks;
    mapping(address => uint256) public userActiveLocks;
    mapping(address => mapping(address => uint256)) public userTokenBalances; // user => token => total locked amount
    mapping(address => uint256) public totalValueLocked; // token => total amount locked

    // Events
    event Deposited(address indexed user, uint256 indexed lockId, address indexed token, uint256 amount, uint256 releaseTime);
    event Withdrawn(address indexed user, uint256 indexed lockId, address indexed token, uint256 amount);

    function deposit(IERC20 token, uint256 amount, uint256 duration) public nonReentrant returns (uint256 lockId) {
        require(amount > 0, "Amount must be positive");
        require(duration > 0, "Duration must be positive");
        require(duration <= 365 days, "Duration too long");
        
        uint256 releaseTime = block.timestamp + duration;
        
        // Transfer tokens to this contract
        token.safeTransferFrom(msg.sender, address(this), amount);

        lockId = lockIdCounter++;
        locks[lockId] = Lock({
            user: msg.sender,
            token: token,
            amount: amount,
            releaseTime: releaseTime,
            withdrawn: false
        });
        
        userLocks[msg.sender].push(lockId);
        userTokenBalances[msg.sender][address(token)] += amount;
        totalValueLocked[address(token)] += amount;
        
        totalLocks++;
        activeLocks++;
        userActiveLocks[msg.sender]++;

        emit Deposited(msg.sender, lockId, address(token), amount, releaseTime);
    }

    function withdraw(uint256 lockId) public nonReentrant {
        Lock storage lock = locks[lockId];
        require(lock.user == msg.sender, "Not lock owner");
        require(!lock.withdrawn, "Already withdrawn");
        require(block.timestamp >= lock.releaseTime, "Still locked");
        require(lock.amount > 0, "No tokens to withdraw");

        uint256 amount = lock.amount;
        lock.withdrawn = true;
        
        userTokenBalances[msg.sender][address(lock.token)] -= amount;
        totalValueLocked[address(lock.token)] -= amount;
        activeLocks--;
        userActiveLocks[msg.sender]--;
        
        // Transfer tokens back to user
        lock.token.safeTransfer(msg.sender, amount);

        emit Withdrawn(msg.sender, lockId, address(lock.token), amount);
    }

    // Emergency withdraw for stuck tokens (only after 30 days past release time)
    function emergencyWithdraw(uint256 lockId) public nonReentrant {
        Lock storage lock = locks[lockId];
        require(lock.user == msg.sender, "Not lock owner");
        require(!lock.withdrawn, "Already withdrawn");
        require(block.timestamp >= lock.releaseTime + 30 days, "Emergency period not reached");
        require(lock.amount > 0, "No tokens to withdraw");

        uint256 amount = lock.amount;
        lock.withdrawn = true;
        
        userTokenBalances[msg.sender][address(lock.token)] -= amount;
        totalValueLocked[address(lock.token)] -= amount;
        activeLocks--;
        userActiveLocks[msg.sender]--;
        
        // Transfer tokens back to user
        lock.token.safeTransfer(msg.sender, amount);

        emit Withdrawn(msg.sender, lockId, address(lock.token), amount);
    }

    // View functions
    function getLockDetails(uint256 lockId) public view returns (
        address user,
        address token,
        uint256 amount,
        uint256 releaseTime,
        bool withdrawn,
        bool unlocked
    ) {
        Lock memory lock = locks[lockId];
        return (
            lock.user,
            address(lock.token),
            lock.amount,
            lock.releaseTime,
            lock.withdrawn,
            block.timestamp >= lock.releaseTime
        );
    }

    function getUserLocks(address user) public view returns (uint256[] memory) {
        return userLocks[user];
    }
    
    function getUserActiveLockCount(address user) public view returns (uint256) {
        return userActiveLocks[user];
    }
    
    function getUserTokenBalance(address user, address token) public view returns (uint256) {
        return userTokenBalances[user][token];
    }

    // Get active locks with pagination
    function getActiveLocks(uint256 offset, uint256 limit) public view returns (uint256[] memory lockIds, uint256 total) {
        uint256[] memory activeLockIds = new uint256[](limit);
        uint256 count = 0;
        uint256 scanned = 0;
        
        for (uint256 i = 1; i < lockIdCounter && count < limit; i++) {
            if (!locks[i].withdrawn) {
                if (scanned >= offset) {
                    activeLockIds[count] = i;
                    count++;
                }
                scanned++;
            }
        }
        
        // Resize array to actual count
        uint256[] memory result = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = activeLockIds[i];
        }
        
        return (result, activeLocks);
    }
    
    // Get user's active locks for a specific token
    function getUserTokenLocks(address user, address token) public view returns (uint256[] memory) {
        uint256[] memory allUserLocks = userLocks[user];
        uint256[] memory tokenLocks = new uint256[](allUserLocks.length);
        uint256 count = 0;
        
        for (uint256 i = 0; i < allUserLocks.length; i++) {
            Lock memory lock = locks[allUserLocks[i]];
            if (address(lock.token) == token && !lock.withdrawn) {
                tokenLocks[count] = allUserLocks[i];
                count++;
            }
        }
        
        // Resize array to actual count
        uint256[] memory result = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = tokenLocks[i];
        }
        
        return result;
    }
}
