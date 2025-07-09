//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./ReceiptToken.sol";
import "./RewardPool.sol";

/**
 * @title DiamondHandsLinearV2
 * @notice Version 2 with initialize function for clone pattern
 * @dev Linear multiplier based on lock duration
 */
contract DiamondHandsLinearV2 {
    // State variables
    IERC20 public token;
    ReceiptToken public receiptToken;
    uint256 public currentLockIndex;
    uint256 public currentRewardIndex;
    uint256 public minLockDuration;
    uint256 public maxLockDuration;
    uint256 public maxMultiplier;
    bool private initialized;

    uint256[] public lockers;
    uint256[] public rewards;

    mapping(uint256 => Lock) public lockIDToLock;
    mapping(uint256 => Reward) public rewardIDToReward;
    mapping(uint256 => address) public rewardIDToRewardOwner;
    mapping(uint256 => address) public lockIDToUser;
    mapping(address => uint256[]) public userToLockIDs;
    mapping(uint256 => mapping(uint256 => uint256)) public rewardIDToLockIDToLastClaim;

    struct Lock {
        uint256 startTime;
        uint256 endTime;
        uint256 amount;
        uint256 boostedAmount;
        bool claimed;
    }

    struct Reward {
        uint256 startTime;
        uint256 duration;
        address token;
        uint256 amount;
        uint256 receiptSupply;
        RewardPool rewardPool;
    }

    // Events
    event LockCreated(uint256 lockId, address user, uint256 amount, uint256 startTime, uint256 endTime);
    event LockUnlocked(uint256 lockId, address user, uint256 amount);
    event RewardCreated(uint256 rewardId, uint256 amount, address token);
    event RewardClaimed(uint256 lockId, uint256 rewardId, uint256 amount);
    event StreamRewardRecovered(uint256 rewardId);

    modifier onlyInitialized() {
        require(initialized, "Not initialized");
        _;
    }

    /**
     * @notice Initialize the contract (for clone pattern)
     * @dev Can only be called once
     */
    function initialize(
        address _token,
        uint256 _minLockDuration,
        uint256 _maxLockDuration,
        uint256 _maxMultiplier,
        string memory _receiptTokenName,
        string memory _receiptTokenSymbol
    ) external {
        require(!initialized, "Already initialized");
        require(_maxLockDuration > _minLockDuration, "Max lock duration must be greater than min duration");
        require(_maxMultiplier < 10**28 && _maxMultiplier >= 10**18, "Max multiplier must be between 1 and 10 billion");
        
        token = IERC20(_token);
        minLockDuration = _minLockDuration;
        maxLockDuration = _maxLockDuration;
        maxMultiplier = _maxMultiplier;
        currentLockIndex = 0;
        currentRewardIndex = 0;
        receiptToken = new ReceiptToken(_receiptTokenName, _receiptTokenSymbol, address(this));
        
        initialized = true;
    }

    /**
     * @notice Lock tokens for a specific duration
     */
    function lockTokens(uint256 amount, uint256 lockDuration) external onlyInitialized {
        require(lockDuration >= minLockDuration && lockDuration <= maxLockDuration, "Lock duration out of range");
        require(amount > 0, "Amount must be greater than 0");
        
        // Calculate multiplier linearly based on duration
        uint256 multiplier = 10**18 + ((maxMultiplier - 10**18) * (lockDuration - minLockDuration)) / (maxLockDuration - minLockDuration);
        uint256 boostedAmount = (amount * multiplier) / 10**18;
        
        uint256 lockId = currentLockIndex++;
        uint256 endTime = block.timestamp + lockDuration;
        
        lockIDToLock[lockId] = Lock({
            startTime: block.timestamp,
            endTime: endTime,
            amount: amount,
            boostedAmount: boostedAmount,
            claimed: false
        });
        
        lockIDToUser[lockId] = msg.sender;
        userToLockIDs[msg.sender].push(lockId);
        lockers.push(lockId);
        
        // Transfer tokens and mint receipt tokens
        token.transferFrom(msg.sender, address(this), amount);
        receiptToken.mint(msg.sender, boostedAmount);
        
        emit LockCreated(lockId, msg.sender, amount, block.timestamp, endTime);
    }

    /**
     * @notice Unlock tokens after lock period
     */
    function unlockTokens(uint256 lockId) external onlyInitialized {
        require(lockIDToUser[lockId] == msg.sender, "Not the owner of this lock");
        require(!lockIDToLock[lockId].claimed, "Lock already claimed");
        require(block.timestamp >= lockIDToLock[lockId].endTime, "Lock period not ended");
        
        Lock storage lock = lockIDToLock[lockId];
        lock.claimed = true;
        
        // Burn receipt tokens and transfer locked tokens back
        receiptToken.burn(msg.sender, lock.boostedAmount);
        token.transfer(msg.sender, lock.amount);
        
        emit LockUnlocked(lockId, msg.sender, lock.amount);
    }

    /**
     * @notice Create a reward pool for locked token holders
     */
    function createReward(address rewardToken, uint256 amount, uint256 duration) external onlyInitialized {
        require(amount > 0, "Amount must be greater than 0");
        require(duration < (5200 weeks), "Max reward duration of 100 years");
        
        IERC20 RT = IERC20(rewardToken);
        require(RT.allowance(msg.sender, address(this)) >= amount, "Token allowance too low");
        
        // Create Reward Pool
        RewardPool RP = new RewardPool(rewardToken, address(this));
        uint256 rewardId = currentRewardIndex++;
        
        rewardIDToReward[rewardId] = Reward({
            startTime: block.timestamp,
            duration: duration,
            token: rewardToken,
            amount: amount,
            receiptSupply: receiptToken.totalSupply(),
            rewardPool: RP
        });
        
        rewardIDToRewardOwner[rewardId] = msg.sender;
        rewards.push(rewardId);
        
        // Transfer and deposit rewards
        RT.transferFrom(msg.sender, address(this), amount);
        RT.approve(address(RP), amount);
        RP.depositRewards(amount);
        
        emit RewardCreated(rewardId, amount, rewardToken);
    }

    /**
     * @notice Claim rewards for a lock
     */
    function claimReward(uint256 rewardId, uint256 lockId) external onlyInitialized {
        require(lockIDToUser[lockId] == msg.sender, "Not the owner of this lock");
        require(!lockIDToLock[lockId].claimed, "Lock already claimed");
        
        Reward storage reward = rewardIDToReward[rewardId];
        require(lockIDToLock[lockId].startTime <= reward.startTime, "Lock created after reward");
        
        uint256 claimable;
        if (reward.duration == 0) {
            // Fixed reward
            claimable = (lockIDToLock[lockId].boostedAmount * reward.amount) / reward.receiptSupply;
        } else {
            // Streaming reward
            uint256 elapsed = block.timestamp - reward.startTime;
            if (elapsed > reward.duration) elapsed = reward.duration;
            
            uint256 totalUnlocked = (reward.amount * elapsed) / reward.duration;
            claimable = (lockIDToLock[lockId].boostedAmount * totalUnlocked) / receiptToken.totalSupply();
            
            uint256 lastClaim = rewardIDToLockIDToLastClaim[rewardId][lockId];
            if (lastClaim > 0) {
                uint256 alreadyClaimed = (lockIDToLock[lockId].boostedAmount * lastClaim) / receiptToken.totalSupply();
                claimable = claimable > alreadyClaimed ? claimable - alreadyClaimed : 0;
            }
            
            rewardIDToLockIDToLastClaim[rewardId][lockId] = totalUnlocked;
        }
        
        if (claimable > 0) {
            reward.rewardPool.distributeReward(msg.sender, claimable);
            emit RewardClaimed(lockId, rewardId, claimable);
        }
    }

    /**
     * @notice Get user's lock IDs
     */
    function getUserLockIDs(address user) external view returns (uint256[] memory) {
        return userToLockIDs[user];
    }

    /**
     * @notice Calculate current multiplier for a duration
     */
    function calculateMultiplier(uint256 lockDuration) external view returns (uint256) {
        require(lockDuration >= minLockDuration && lockDuration <= maxLockDuration, "Duration out of range");
        return 10**18 + ((maxMultiplier - 10**18) * (lockDuration - minLockDuration)) / (maxLockDuration - minLockDuration);
    }
}