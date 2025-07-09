// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract DiamondHandsLockerERC721 is IERC721Receiver, ReentrancyGuard {
    
    struct Lock {
        address user;
        IERC721 token;
        uint256 tokenId;
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
    mapping(address => mapping(address => uint256[])) public userTokenLocks; // user => token => lockIds

    // Events
    event Deposited(address indexed user, uint256 indexed lockId, address indexed token, uint256 tokenId, uint256 releaseTime);
    event Withdrawn(address indexed user, uint256 indexed lockId, address indexed token, uint256 tokenId);

    function deposit(IERC721 token, uint256 tokenId, uint256 duration) public nonReentrant returns (uint256 lockId) {
        require(duration > 0, "Duration must be positive");
        require(duration <= 365 days, "Duration too long");
        
        uint256 releaseTime = block.timestamp + duration;
        
        // Transfer NFT to this contract
        token.safeTransferFrom(msg.sender, address(this), tokenId);

        lockId = lockIdCounter++;
        locks[lockId] = Lock({
            user: msg.sender,
            token: token,
            tokenId: tokenId,
            releaseTime: releaseTime,
            withdrawn: false
        });
        
        userLocks[msg.sender].push(lockId);
        userTokenLocks[msg.sender][address(token)].push(lockId);
        
        totalLocks++;
        activeLocks++;
        userActiveLocks[msg.sender]++;

        emit Deposited(msg.sender, lockId, address(token), tokenId, releaseTime);
    }

    function withdraw(uint256 lockId) public nonReentrant {
        Lock storage lock = locks[lockId];
        require(lock.user == msg.sender, "Not lock owner");
        require(!lock.withdrawn, "Already withdrawn");
        require(block.timestamp >= lock.releaseTime, "Still locked");

        lock.withdrawn = true;
        activeLocks--;
        userActiveLocks[msg.sender]--;
        
        // Transfer NFT back to user
        lock.token.safeTransferFrom(address(this), msg.sender, lock.tokenId);

        emit Withdrawn(msg.sender, lockId, address(lock.token), lock.tokenId);
    }

    // Emergency withdraw for stuck NFTs (only after 30 days past release time)
    function emergencyWithdraw(uint256 lockId) public nonReentrant {
        Lock storage lock = locks[lockId];
        require(lock.user == msg.sender, "Not lock owner");
        require(!lock.withdrawn, "Already withdrawn");
        require(block.timestamp >= lock.releaseTime + 30 days, "Emergency period not reached");

        lock.withdrawn = true;
        activeLocks--;
        userActiveLocks[msg.sender]--;
        
        // Transfer NFT back to user
        lock.token.safeTransferFrom(address(this), msg.sender, lock.tokenId);

        emit Withdrawn(msg.sender, lockId, address(lock.token), lock.tokenId);
    }

    // View functions
    function getLockDetails(uint256 lockId) public view returns (
        address user,
        address token,
        uint256 tokenId,
        uint256 releaseTime,
        bool withdrawn,
        bool unlocked
    ) {
        Lock memory lock = locks[lockId];
        return (
            lock.user,
            address(lock.token),
            lock.tokenId,
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
    
    function getUserTokenLocks(address user, address token) public view returns (uint256[] memory) {
        return userTokenLocks[user][token];
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

    // Required for receiving NFTs
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}
