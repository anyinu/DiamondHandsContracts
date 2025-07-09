//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "./DiamondHandsLinearV2.sol";
import "./DiamondHandsConstantV2.sol";

/**
 * @title DiamondHandsFactoryClone
 * @notice Optimized factory using minimal proxy pattern (EIP-1167) to deploy gas-efficient clones
 * @dev This dramatically reduces deployment costs and stays within contract size limits
 */
contract DiamondHandsFactoryClone is Ownable {
    using Clones for address;
    
    // Implementation contracts (deployed once)
    address public immutable linearImplementation;
    address public immutable constantImplementation;
    
    // Fee configuration
    uint256 public feeAmount;
    address public feeToken;
    
    // Tracking
    uint256 public contractsDeployed;
    mapping(uint256 => address) public indexToContract;
    mapping(address => address[]) public tokenToContracts; // Multiple contracts per token allowed
    mapping(address => bool) public isValidContract;
    
    // Events
    event ContractCreated(
        uint256 indexed contractId,
        address indexed contractAddress,
        address indexed tokenAddress,
        bool isLinear,
        address creator
    );
    
    event ImplementationsDeployed(
        address linearImplementation,
        address constantImplementation
    );
    
    event FeeUpdated(uint256 newFeeAmount, address newFeeToken);
    
    constructor(uint256 _feeAmount, address _feeToken) {
        feeAmount = _feeAmount;
        feeToken = _feeToken;
        
        // Deploy implementation contracts
        linearImplementation = address(new DiamondHandsLinearV2());
        constantImplementation = address(new DiamondHandsConstantV2());
        
        emit ImplementationsDeployed(linearImplementation, constantImplementation);
    }
    
    /**
     * @notice Create a new DiamondHandsLinear contract for a token
     * @param _token The token to lock
     * @param _minLockDuration Minimum lock duration in seconds
     * @param _maxLockDuration Maximum lock duration in seconds
     * @param _maxMultiplier Maximum multiplier (in 18 decimals, e.g., 5e18 = 5x)
     * @param _receiptTokenName Name for the receipt token
     * @param _receiptTokenSymbol Symbol for the receipt token
     */
    function createDiamondHandsLinear(
        address _token,
        uint256 _minLockDuration,
        uint256 _maxLockDuration,
        uint256 _maxMultiplier,
        string memory _receiptTokenName,
        string memory _receiptTokenSymbol
    ) external returns (address) {
        // Take fee if required
        _takeFee();
        
        // Deploy clone
        address clone = linearImplementation.clone();
        
        // Initialize clone
        DiamondHandsLinearV2(clone).initialize(
            _token,
            _minLockDuration,
            _maxLockDuration,
            _maxMultiplier,
            _receiptTokenName,
            _receiptTokenSymbol
        );
        
        // Track deployment
        uint256 contractId = contractsDeployed++;
        indexToContract[contractId] = clone;
        tokenToContracts[_token].push(clone);
        isValidContract[clone] = true;
        
        emit ContractCreated(contractId, clone, _token, true, msg.sender);
        
        return clone;
    }
    
    /**
     * @notice Create a new DiamondHandsConstant contract for a token
     * @param _token The token to lock
     * @param _lockDurations Array of lock durations (must be sorted)
     * @param _multipliers Array of multipliers for each duration (must be sorted)
     * @param _receiptTokenName Name for the receipt token
     * @param _receiptTokenSymbol Symbol for the receipt token
     */
    function createDiamondHandsConstant(
        address _token,
        uint256[] memory _lockDurations,
        uint256[] memory _multipliers,
        string memory _receiptTokenName,
        string memory _receiptTokenSymbol
    ) external returns (address) {
        require(_lockDurations.length == _multipliers.length, "Array length mismatch");
        require(_lockDurations.length > 0, "Must have at least one duration");
        
        // Take fee if required
        _takeFee();
        
        // Deploy clone
        address clone = constantImplementation.clone();
        
        // Initialize clone
        DiamondHandsConstantV2(clone).initialize(
            _token,
            _lockDurations,
            _multipliers,
            _receiptTokenName,
            _receiptTokenSymbol
        );
        
        // Track deployment
        uint256 contractId = contractsDeployed++;
        indexToContract[contractId] = clone;
        tokenToContracts[_token].push(clone);
        isValidContract[clone] = true;
        
        emit ContractCreated(contractId, clone, _token, false, msg.sender);
        
        return clone;
    }
    
    /**
     * @notice Get all contracts for a specific token
     */
    function getContractsForToken(address _token) external view returns (address[] memory) {
        return tokenToContracts[_token];
    }
    
    /**
     * @notice Update fee configuration (owner only)
     */
    function updateFee(uint256 _feeAmount, address _feeToken) external onlyOwner {
        feeAmount = _feeAmount;
        feeToken = _feeToken;
        emit FeeUpdated(_feeAmount, _feeToken);
    }
    
    /**
     * @notice Take fee from user if configured
     */
    function _takeFee() private {
        if (feeAmount > 0 && feeToken != address(0)) {
            IERC20(feeToken).transferFrom(msg.sender, owner(), feeAmount);
        }
    }
    
    /**
     * @notice Predict the address of a linear clone
     */
    function predictLinearCloneAddress(bytes32 salt) external view returns (address) {
        return linearImplementation.predictDeterministicAddress(salt);
    }
    
    /**
     * @notice Predict the address of a constant clone
     */
    function predictConstantCloneAddress(bytes32 salt) external view returns (address) {
        return constantImplementation.predictDeterministicAddress(salt);
    }
}