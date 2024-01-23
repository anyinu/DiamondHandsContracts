//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract RewardPool {
    
    IERC20 public rewardToken;
    address public controller;

    // Modifier to restrict access to the controller
    modifier onlyController() {
        require(msg.sender == controller, "Only the controller can perform this action");
        _;
    }

    // Constructor to initialize the reward token and the controller
    constructor(address _rewardToken, address _controller) {
        rewardToken = IERC20(_rewardToken);
        controller = _controller;
    }

    // Function to deposit reward tokens into the pool
    function depositRewards(uint256 amount) external onlyController {
        require(amount > 0, "Amount must be greater than 0");
        rewardToken.transferFrom(msg.sender, address(this), amount);
    }

    // Function to distribute rewards
    function distributeReward(address to, uint256 amount) external onlyController {
        require(amount <= rewardToken.balanceOf(address(this)), "Insufficient balance in pool");
        rewardToken.transfer(to, amount);
    }

    // Function to check pool's reward token balance
    function getPoolBalance() external view returns (uint256) {
        return rewardToken.balanceOf(address(this));
    }

}
