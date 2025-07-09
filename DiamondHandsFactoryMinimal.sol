//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./DiamondHandsLinear.sol";
import "./DiamondHandsConstant.sol";

/**
 * @title DiamondHandsFactoryMinimal
 * @notice A minimal factory contract that can be deployed within the 24KB limit
 * @dev This version removes extra features to fit within contract size limits
 */
contract DiamondHandsFactoryMinimal is Ownable {
    
    uint256 public feeAmount;
    address public feeToken;
    uint256 public contractsDeployed;
    
    mapping(uint256 => address) public indexToContract;
    mapping(address => address) public tokenToContract;
    
    event ContractCreated(
        uint256 indexed contractId,
        address indexed contractAddress,
        address indexed tokenAddress,
        bool isLinear
    );
    
    constructor(uint256 _feeAmount, address _feeToken) {
        feeAmount = _feeAmount;
        feeToken = _feeToken;
    }
    
    function createDiamondHandsLinear(
        address _token,
        uint256 _minLockDuration,
        uint256 _maxLockDuration,
        uint256 _maxMultiplier,
        string memory _receiptTokenName,
        string memory _receiptTokenSymbol
    ) external returns (address) {
        require(tokenToContract[_token] == address(0), "Contract already exists for this token");
        
        // Take fee if required
        if (feeAmount > 0 && feeToken != address(0)) {
            IERC20(feeToken).transferFrom(msg.sender, owner(), feeAmount);
        }
        
        DiamondHandsLinear newContract = new DiamondHandsLinear(
            _token,
            _minLockDuration,
            _maxLockDuration,
            _maxMultiplier,
            _receiptTokenName,
            _receiptTokenSymbol
        );
        
        uint256 contractId = contractsDeployed++;
        indexToContract[contractId] = address(newContract);
        tokenToContract[_token] = address(newContract);
        
        emit ContractCreated(contractId, address(newContract), _token, true);
        
        return address(newContract);
    }
    
    function createDiamondHandsConstant(
        address _token,
        uint256[] memory _lockDurations,
        uint256[] memory _multipliers,
        string memory _receiptTokenName,
        string memory _receiptTokenSymbol
    ) external returns (address) {
        require(tokenToContract[_token] == address(0), "Contract already exists for this token");
        
        // Take fee if required
        if (feeAmount > 0 && feeToken != address(0)) {
            IERC20(feeToken).transferFrom(msg.sender, owner(), feeAmount);
        }
        
        DiamondHandsConstant newContract = new DiamondHandsConstant(
            _token,
            _lockDurations,
            _multipliers,
            _receiptTokenName,
            _receiptTokenSymbol
        );
        
        uint256 contractId = contractsDeployed++;
        indexToContract[contractId] = address(newContract);
        tokenToContract[_token] = address(newContract);
        
        emit ContractCreated(contractId, address(newContract), _token, false);
        
        return address(newContract);
    }
    
    function updateFee(uint256 _feeAmount, address _feeToken) external onlyOwner {
        feeAmount = _feeAmount;
        feeToken = _feeToken;
    }
}