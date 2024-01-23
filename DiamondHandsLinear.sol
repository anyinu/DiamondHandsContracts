//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./ReceiptToken.sol";
import "./RewardPool.sol";

contract DiamondHandsLinear {

    IERC20 public token;
    ReceiptToken public receiptToken;
    uint256 public currentLockIndex;
    uint256 public currentRewardIndex;
    uint256 public minLockDuration;
    uint256 public maxLockDuration;
    uint256 public maxMultiplier;

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

    constructor(address _token, uint256 _minLockDuration, uint256 _maxLockDuration, uint256 _maxMultiplier, string memory _receiptTokenName, string memory _receiptTokenSymbol) {
        token = IERC20(_token);
        require(_maxLockDuration > _minLockDuration, "Max lock duration must be greater than min duration");
        require(maxMultiplier < 10**28 && maxMultiplier >= 10**18, "Max multiplier must be greater than or equal to 1 and less than 10 billion");
        minLockDuration = _minLockDuration;
        maxLockDuration = _maxLockDuration;
        maxMultiplier = _maxMultiplier;
        currentLockIndex = 0;
        currentRewardIndex = 0;
        receiptToken = new ReceiptToken(_receiptTokenName, _receiptTokenSymbol, address(this));
    }

    // Create a new lock
    function createLock(uint256 amount, uint256 duration) external {
        require(amount > 0, "Amount must be greater than 0");
        require(duration > minLockDuration && duration < maxLockDuration, "Duration is invalid");

        // Check if the contract has enough allowance to transfer tokens on behalf of the user
        require(token.allowance(msg.sender, address(this)) >= amount, "Token allowance too low");

        // Transfer tokens from the user to the contract
        token.transferFrom(msg.sender, address(this), amount);

        uint256 lockId = currentLockIndex++;
        lockers.push(lockId);
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + duration;
        uint256 multi = ((duration-minLockDuration) * (maxMultiplier-10**18)) / (maxLockDuration-minLockDuration) + 10**18;

        lockIDToLock[lockId] = Lock(startTime, endTime, amount, amount*multi, false);
        lockIDToUser[lockId] = msg.sender;
        userToLockIDs[msg.sender].push(lockId);

        receiptToken.mint(msg.sender, lockIDToLock[lockId].boostedAmount);

        emit LockCreated(lockId, msg.sender, amount, startTime, endTime);
    }

    // Unlock tokens
    function unlock(uint256 lockId) external {
        // Ensure the lock exists and belongs to the caller
        require(lockIDToLock[lockId].startTime != 0, "Lock does not exist");
        require(lockIDToUser[lockId] == msg.sender, "You do not own this lock");

        // Check if the lock period has ended
        require(block.timestamp >= lockIDToLock[lockId].endTime, "Lock period has not ended yet");

        // Ensure the tokens are not already claimed
        require(!lockIDToLock[lockId].claimed); 
        lockIDToLock[lockId].claimed = true;

        // Transfer the locked tokens back to the user
        receiptToken.burn(msg.sender, lockIDToLock[lockId].boostedAmount);
        token.transfer(msg.sender, lockIDToLock[lockId].amount);

        emit LockUnlocked(lockId, msg.sender, lockIDToLock[lockId].amount);
    }

    // Create reward for Diamond staker, starts at present
    function createReward(address rewardToken, uint256 amount, uint256 duration) external {
        require(amount > 0, "Amount must be greater than 0");
        require(duration < (5200 weeks), "Max reward duration of 100 years");
        IERC20 RT = IERC20(rewardToken);
        require(RT.allowance(msg.sender, address(this)) >= amount, "Token allowance too low");

        // Create Reward Pool and set reward info
        RewardPool RP = new RewardPool(rewardToken, address(this));
        uint256 rewardId = currentRewardIndex++;
        rewardIDToReward[rewardId] = Reward(block.timestamp, duration, rewardToken, amount, receiptToken.totalSupply(), RP);
        rewardIDToRewardOwner[rewardId] = msg.sender;
        rewards.push(rewardId);

        // Transfer tokens from the user to the contract
        RT.transferFrom(msg.sender, address(this), amount);
        RT.approve(address(RP), amount);
        RP.depositRewards(amount);

        emit RewardCreated(rewardId, amount, rewardToken);
    }

    // Claim reward for Diamond Stakers
    function claimReward(uint256 rewardId, uint256 lockId) external {
        if (rewardIDToReward[rewardId].duration == 0) {
            claimFixed(rewardId, lockId);
        } else {
            claimStream(rewardId, lockId);
        }
    }

    function lockRewardValid(uint256 rewardId, uint256 lockId) public view returns (bool) {
        return (lockIDToLock[lockId].startTime <= rewardIDToReward[rewardId].startTime) && (lockIDToLock[lockId].claimed == false) && ((rewardIDToReward[rewardId].startTime+rewardIDToReward[rewardId].duration) >= rewardIDToLockIDToLastClaim[rewardId][lockId]);
    }

    // Claim for fixed drop
    function claimFixed(uint256 rewardId, uint256 lockId) internal {
        require(lockRewardValid(rewardId, lockId), "Lock not valid for reward");
        require(rewardIDToReward[rewardId].startTime != 0, "Reward does not exist");
        require(lockIDToLock[lockId].startTime != 0, "Lock does not exist");
        require(lockIDToUser[lockId] == msg.sender, "You do not own this lock");
        require(rewardIDToReward[rewardId].duration == 0, "Not a fixed reward");

        uint256 lastClaim = rewardIDToLockIDToLastClaim[rewardId][lockId];
        require(lastClaim == 0, "Reward already claimed");

        // Calculate reward amount (implementation depends on your reward logic)
        uint256 rewardAmount = calculateFixedRewardAmount(rewardId, lockId);

        rewardIDToLockIDToLastClaim[rewardId][lockId] = block.timestamp;
        rewardIDToReward[rewardId].rewardPool.distributeReward(msg.sender, rewardAmount);

        emit RewardClaimed(lockId, rewardId, rewardAmount);
    }

    // Assumes valid lock
    function calculateFixedRewardAmount(uint256 rewardId, uint256 lockId) public view returns (uint256) {
        return (lockIDToLock[lockId].boostedAmount * rewardIDToReward[rewardId].amount) / rewardIDToReward[rewardId].receiptSupply;
    }

    // Claim for stream drop
    function claimStream(uint256 rewardId, uint256 lockId) internal {
        require(lockRewardValid(rewardId, lockId), "Lock not valid for reward");
        require(rewardIDToReward[rewardId].startTime != 0, "Reward does not exist");
        require(lockIDToLock[lockId].startTime != 0, "Lock does not exist");
        require(lockIDToUser[lockId] == msg.sender, "You do not own this lock");
        require(rewardIDToReward[rewardId].duration != 0, "Not a stream reward");

        uint256 lastClaim = rewardIDToLockIDToLastClaim[rewardId][lockId];
        require(block.timestamp > lastClaim, "Reward already claimed");

        // Calculate reward amount (implementation depends on your reward logic)
        uint256 rewardAmount = calculateStreamRewardAmount(rewardId, lockId);

        rewardIDToLockIDToLastClaim[rewardId][lockId] = block.timestamp;
        rewardIDToReward[rewardId].rewardPool.distributeReward(msg.sender, rewardAmount);

        emit RewardClaimed(lockId, rewardId, rewardAmount);
    }

    function minimum(uint256 a, uint256 b) pure public returns (uint256) {
        return a <= b ? a : b;
    }

    function maximum(uint256 a, uint256 b) pure public returns (uint256) {
        return a >= b ? a : b;
    }

    // Assumes valid lock
    function calculateStreamRewardAmount(uint256 rewardId, uint256 lockId) public view returns (uint256) {
        uint256 userElapsed = minimum(block.timestamp - maximum(rewardIDToReward[rewardId].startTime, rewardIDToLockIDToLastClaim[rewardId][lockId]), rewardIDToReward[rewardId].duration);
        uint256 totalRewardSupplyUnlocked = (rewardIDToReward[rewardId].amount*(userElapsed))/rewardIDToReward[rewardId].duration;
        return (lockIDToLock[lockId].boostedAmount*totalRewardSupplyUnlocked)/receiptToken.totalSupply();
    }  

    // Stream guaranteed to always have enough tokens, but ordering of locks&claims can leave remaining rewards
    // Anyone can call 1 day after stream has ended to refund the reward deployer
    function recoverStreamingReward(uint256 rewardId) external {
        require(rewardIDToReward[rewardId].duration > 0, "Only for streaming rewards");
        // Require 1 day after the rewards have ended streaming
        require(rewardIDToReward[rewardId].startTime+rewardIDToReward[rewardId].duration+(1 days) < block.timestamp, "Require 24 hours after the stream period has ended");
        // Send balance of contract to reward distributor
        rewardIDToReward[rewardId].rewardPool.distributeReward(rewardIDToRewardOwner[rewardId], rewardIDToReward[rewardId].rewardPool.getPoolBalance());
        emit StreamRewardRecovered(rewardId);
    }   

}