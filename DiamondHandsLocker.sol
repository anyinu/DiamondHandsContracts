// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DiamondHandsLocker {
    
    struct Lock {
        address user;
        IERC20 token;
        uint256 amount;
        uint256 releaseTime;
    }

    uint256 public lockIdCounter = 0;
    mapping(uint256 => Lock) public locks;
    mapping(address => uint256[]) public userLocks;

    // Events
    event Deposited(address indexed user, uint256 lockId, IERC20 token, uint256 amount, uint256 releaseTime);
    event Withdrawn(address indexed user, uint256 lockId, IERC20 token, uint256 amount);

    function deposit(IERC20 token, uint256 amount, uint256 time) public returns (uint256 lockId) {
        require(time > block.timestamp, "Release time is before current time");
        token.transferFrom(msg.sender, address(this), amount);

        lockId = lockIdCounter++;
        locks[lockId] = Lock({
            user: msg.sender,
            token: token,
            amount: amount,
            releaseTime: time
        });
        userLocks[msg.sender].push(lockId);

        emit Deposited(msg.sender, lockId, token, amount, time);
    }

    function withdraw(uint256 lockId) public {
        require(locks[lockId].user == msg.sender, "You do not own this lock");
        require(block.timestamp >= locks[lockId].releaseTime, "Current time is before release time");
        require(locks[lockId].amount > 0, "No tokens to withdraw");

        Lock memory userLock = locks[lockId];
        locks[lockId].amount = 0;
        require(userLock.token.transfer(msg.sender, userLock.amount), "Transfer failed");

        emit Withdrawn(msg.sender, lockId, userLock.token, userLock.amount);
    }

    // View function to get lock details by lockId
    function getLockDetails(uint256 lockId) public view returns (address, IERC20, uint256, uint256) {
        Lock memory lock = locks[lockId];
        return (lock.user, lock.token, lock.amount, lock.releaseTime);
    }

    // View function to get all lockIds for a user
    function getUserLocks(address user) public view returns (uint256[] memory) {
        return userLocks[user];
    }
}
