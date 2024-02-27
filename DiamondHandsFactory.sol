// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./DiamondHandsLinear.sol";
import "./DiamondHandsConstant.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DiamondHandsFactory is Ownable {

    uint256 public idCounter = 0;
    mapping(uint256 => address) public idToAddress;
    mapping(uint256 => bool) public isLinear;
    mapping(address => uint256[]) public tokenToIds;

    // Fee-related variables
    uint256 public feeAmount;
    IERC20 public feeToken; // The token in which fees are paid

    event DiamondHandsLinearCreated(uint256 indexed id, address indexed contractAddress);
    event DiamondHandsConstantCreated(uint256 indexed id, address indexed contractAddress);

    constructor(uint256 _feeAmount, address _feeTokenAddress) {
        feeAmount = _feeAmount;
        feeToken = IERC20(_feeTokenAddress);
    }

    // Allows the owner to adjust the fee
    function setFeeAmount(uint256 _newFeeAmount) public onlyOwner {
        feeAmount = _newFeeAmount;
    }

    // Allows the owner to change the fee token
    function setFeeToken(address _newFeeTokenAddress) public onlyOwner {
        feeToken = IERC20(_newFeeTokenAddress);
    }

    // Creation function with fee payment
    function createDiamondHandsLinear(
        address _token,
        uint256 _minLockDuration,
        uint256 _maxLockDuration,
        uint256 _maxMultiplier,
        string memory _receiptTokenName,
        string memory _receiptTokenSymbol
    ) public returns (uint256) {
        feeToken.transferFrom(msg.sender, address(this), feeAmount);
        
        DiamondHandsLinear newLinear = new DiamondHandsLinear(
            _token,
            _minLockDuration,
            _maxLockDuration,
            _maxMultiplier,
            _receiptTokenName,
            _receiptTokenSymbol
        );
        uint256 id = idCounter++;
        idToAddress[id] = address(newLinear);
        isLinear[id] = true;
        tokenToIds[_token].push(id);
        emit DiamondHandsLinearCreated(id, address(newLinear));
        return id;
    }

    // Creation function with fee payment
    function createDiamondHandsConstant(
        address _token,
        uint256[] memory _lockDurations,
        uint256[] memory _multipliers,
        string memory _receiptTokenName,
        string memory _receiptTokenSymbol
    ) public returns (uint256) {
        feeToken.transferFrom(msg.sender, address(this), feeAmount);
        
        DiamondHandsConstant newConstant = new DiamondHandsConstant(
            _token,
            _lockDurations,
            _multipliers,
            _receiptTokenName,
            _receiptTokenSymbol
        );
        uint256 id = idCounter++;
        idToAddress[id] = address(newConstant);
        isLinear[id] = false;
        tokenToIds[_token].push(id);
        emit DiamondHandsConstantCreated(id, address(newConstant));
        return id;
    }

    // Optionally, implement a function to withdraw collected fees to a wallet
    function withdrawFees(address _to) public onlyOwner {
        uint256 balance = feeToken.balanceOf(address(this));
        require(feeToken.transfer(_to, balance), "Withdrawal failed");
    }
}
