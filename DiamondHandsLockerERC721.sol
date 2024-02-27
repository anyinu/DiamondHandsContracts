// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract DiamondHandsLockerERC721 {
    
    struct Lock {
        address user;
        IERC721 token;
        uint256 tokenId;
        uint256 releaseTime;
    }

    uint256 public lockIdCounter = 0;
    mapping(uint256 => Lock) public locks;
    mapping(address => uint256[]) public userLocks;

    // Events
    event Deposited(address indexed user, uint256 lockId, IERC721 token, uint256 tokenId, uint256 releaseTime);
    event Withdrawn(address indexed user, uint256 lockId, IERC721 token, uint256 tokenId);

    function deposit(IERC721 token, uint256 tokenId, uint256 time) public returns (uint256 lockId) {
        require(time > block.timestamp, "Release time is before current time");
        token.transferFrom(msg.sender, address(this), tokenId); // Assuming the caller has approved the transfer

        lockId = lockIdCounter++;
        locks[lockId] = Lock({
            user: msg.sender,
            token: token,
            tokenId: tokenId,
            releaseTime: time
        });
        userLocks[msg.sender].push(lockId);

        emit Deposited(msg.sender, lockId, token, tokenId, time);
    }

    function withdraw(uint256 lockId) public {
        require(locks[lockId].user == msg.sender, "You do not own this lock");
        require(block.timestamp >= locks[lockId].releaseTime, "Current time is before release time");

        Lock memory userLock = locks[lockId];
        delete locks[lockId]; // Removing the lock after withdrawal
        userLock.token.transferFrom(address(this), msg.sender, userLock.tokenId); // Sending back the NFT

        emit Withdrawn(msg.sender, lockId, userLock.token, userLock.tokenId);
    }

    // View function to get lock details by lockId
    function getLockDetails(uint256 lockId) public view returns (address, IERC721, uint256, uint256) {
        Lock memory lock = locks[lockId];
        return (lock.user, lock.token, lock.tokenId, lock.releaseTime);
    }

    // View function to get all lockIds for a user
    function getUserLocks(address user) public view returns (uint256[] memory) {
        return userLocks[user];
    }
}
