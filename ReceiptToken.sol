//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ReceiptToken is ERC20 {
    
    address public controller;

    constructor(string memory name, string memory symbol, address _controller) ERC20(name, symbol) {
        require(_controller != address(0), "Controller cannot be the zero address");
        controller = _controller;
    }

    modifier onlyController() {
        require(msg.sender == controller, "Only the controller can perform this action");
        _;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        revert("Soulbound tokens cannot be transferred");
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        revert("Soulbound tokens cannot be transferred");
    }

    function mint(address to, uint256 amount) external onlyController {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyController {
        _burn(from, amount);
    }
}
