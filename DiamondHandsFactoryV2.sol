// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./DiamondHandsLinear.sol";
import "./DiamondHandsConstant.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DiamondHandsFactoryV2 is Ownable {
    
    uint256 public idCounter = 0;
    mapping(uint256 => address) public idToAddress;
    mapping(uint256 => bool) public isLinear;
    mapping(address => uint256[]) public tokenToIds;
    mapping(bytes32 => bool) public saltUsed;

    // Fee-related variables
    uint256 public feeAmount;
    IERC20 public feeToken;

    // Events
    event DiamondHandsLinearCreated(uint256 indexed id, address indexed contractAddress, bytes32 salt);
    event DiamondHandsConstantCreated(uint256 indexed id, address indexed contractAddress, bytes32 salt);

    constructor(uint256 _feeAmount, address _feeTokenAddress) {
        feeAmount = _feeAmount;
        feeToken = IERC20(_feeTokenAddress);
    }

    function setFeeAmount(uint256 _newFeeAmount) public onlyOwner {
        feeAmount = _newFeeAmount;
    }

    function setFeeToken(address _newFeeTokenAddress) public onlyOwner {
        feeToken = IERC20(_newFeeTokenAddress);
    }

    // CREATE2 deployment for DiamondHandsLinear
    function createDiamondHandsLinear(
        address _token,
        uint256 _minLockDuration,
        uint256 _maxLockDuration,
        uint256 _maxMultiplier,
        string memory _receiptTokenName,
        string memory _receiptTokenSymbol,
        bytes32 _salt
    ) public returns (uint256) {
        require(!saltUsed[_salt], "Salt already used");
        saltUsed[_salt] = true;
        
        feeToken.transferFrom(msg.sender, address(this), feeAmount);
        
        bytes memory bytecode = abi.encodePacked(
            type(DiamondHandsLinear).creationCode,
            abi.encode(
                _token,
                _minLockDuration,
                _maxLockDuration,
                _maxMultiplier,
                _receiptTokenName,
                _receiptTokenSymbol
            )
        );
        
        address newLinear = deploy(bytecode, _salt);
        
        uint256 id = idCounter++;
        idToAddress[id] = newLinear;
        isLinear[id] = true;
        tokenToIds[_token].push(id);
        
        emit DiamondHandsLinearCreated(id, newLinear, _salt);
        return id;
    }

    // CREATE2 deployment for DiamondHandsConstant
    function createDiamondHandsConstant(
        address _token,
        uint256[] memory _lockDurations,
        uint256[] memory _multipliers,
        string memory _receiptTokenName,
        string memory _receiptTokenSymbol,
        bytes32 _salt
    ) public returns (uint256) {
        require(!saltUsed[_salt], "Salt already used");
        saltUsed[_salt] = true;
        
        feeToken.transferFrom(msg.sender, address(this), feeAmount);
        
        bytes memory bytecode = abi.encodePacked(
            type(DiamondHandsConstant).creationCode,
            abi.encode(
                _token,
                _lockDurations,
                _multipliers,
                _receiptTokenName,
                _receiptTokenSymbol
            )
        );
        
        address newConstant = deploy(bytecode, _salt);
        
        uint256 id = idCounter++;
        idToAddress[id] = address(newConstant);
        isLinear[id] = false;
        tokenToIds[_token].push(id);
        
        emit DiamondHandsConstantCreated(id, address(newConstant), _salt);
        return id;
    }

    // Internal CREATE2 deployment function
    function deploy(bytes memory bytecode, bytes32 salt) internal returns (address) {
        address addr;
        assembly {
            addr := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
            if iszero(extcodesize(addr)) {
                revert(0, 0)
            }
        }
        return addr;
    }

    // Compute CREATE2 address for DiamondHandsLinear
    function computeLinearAddress(
        address _token,
        uint256 _minLockDuration,
        uint256 _maxLockDuration,
        uint256 _maxMultiplier,
        string memory _receiptTokenName,
        string memory _receiptTokenSymbol,
        bytes32 _salt
    ) public view returns (address) {
        bytes memory bytecode = abi.encodePacked(
            type(DiamondHandsLinear).creationCode,
            abi.encode(
                _token,
                _minLockDuration,
                _maxLockDuration,
                _maxMultiplier,
                _receiptTokenName,
                _receiptTokenSymbol
            )
        );
        
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                address(this),
                _salt,
                keccak256(bytecode)
            )
        );
        
        return address(uint160(uint256(hash)));
    }

    // Compute CREATE2 address for DiamondHandsConstant
    function computeConstantAddress(
        address _token,
        uint256[] memory _lockDurations,
        uint256[] memory _multipliers,
        string memory _receiptTokenName,
        string memory _receiptTokenSymbol,
        bytes32 _salt
    ) public view returns (address) {
        bytes memory bytecode = abi.encodePacked(
            type(DiamondHandsConstant).creationCode,
            abi.encode(
                _token,
                _lockDurations,
                _multipliers,
                _receiptTokenName,
                _receiptTokenSymbol
            )
        );
        
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                address(this),
                _salt,
                keccak256(bytecode)
            )
        );
        
        return address(uint160(uint256(hash)));
    }

    function withdrawFees(address _to) public onlyOwner {
        uint256 balance = feeToken.balanceOf(address(this));
        require(feeToken.transfer(_to, balance), "Withdrawal failed");
    }
}