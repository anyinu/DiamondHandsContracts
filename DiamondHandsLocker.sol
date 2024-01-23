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

    uint256 private _lockIdCounter;
    mapping(uint256 => Lock) private _locks;
    mapping(address => uint256[]) private _userLocks;

    // Events
    event Deposited(address indexed user, uint256 lockId, IERC20 token, uint256 amount, uint256 releaseTime);
    event Withdrawn(address indexed user, uint256 lockId, IERC20 token, uint256 amount);

    function deposit(IERC20 token, uint256 amount, uint256 time) public returns (uint256 lockId) {
        require(time > block.timestamp, "Release time is before current time");
        require(token.transferFrom(msg.sender, address(this), amount), "Transfer failed");

        lockId = _lockIdCounter++;
        _locks[lockId] = Lock({
            user: msg.sender,
            token: token,
            amount: amount,
            releaseTime: time
        });
        _userLocks[msg.sender].push(lockId);

        emit Deposited(msg.sender, lockId, token, amount, time);
    }

    function withdraw(uint256 lockId) public {
        require(_locks[lockId].user == msg.sender, "You do not own this lock");
        require(block.timestamp >= _locks[lockId].releaseTime, "Current time is before release time");
        require(_locks[lockId].amount > 0, "No tokens to withdraw");

        uint256 amount_withdrawed = _locks[lockId].amount;
        // Lock memory userLock = _locks[lockId];
        //_locks[lockId].amount = 0; //<= set amount to 0 before transfer !
        require(userLock.token.transfer(msg.sender, amount_withdrawed), "Transfer failed");
        _locks[lockId].amount = 0; //< set amount to 0 when transfer succeed ! I dont konw lot of solidity but its better like this. no ?

        emit Withdrawn(msg.sender, lockId, _locks[lockId].token, amount_withdrawed);
    }

    // View function to get lock details by lockId
    function getLockDetails(uint256 lockId) public view returns (address, IERC20, uint256, uint256) {
        Lock memory lock = _locks[lockId];
        return (lock.user, lock.token, lock.amount, lock.releaseTime);
    }

    // View function to get all lockIds for a user
    function getUserLocks(address user) public view returns (uint256[] memory) {
        return _userLocks[user];
    }
}
