// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./DiamondHandsLinear.sol";
import "./DiamondHandsConstant.sol";

contract DiamondHandsFactory {

    uint256 public linearIdCounter = 0;
    uint256 public constantIdCounter = 0;

    mapping(uint256 => address) public linearContracts;
    mapping(uint256 => address) public constantContracts;

    mapping(address => uint256[]) public tokenToLinearIds;
    mapping(address => uint256[]) public tokenToConstantIds;

    mapping(address => address[]) public tokenToLinearAddresses;
    mapping(address => address[]) public tokenToConstantAddresses;

    event DiamondHandsLinearCreated(uint256 indexed id, DiamondHandsLinear indexed contractAddress);
    event DiamondHandsConstantCreated(uint256 indexed id, DiamondHandsConstant indexed contractAddress);

    // New Linear Diamond Hands, boost from 1x to max starting at minDuration
    function createDiamondHandsLinear(
        address _token,
        uint256 _minLockDuration,
        uint256 _maxLockDuration,
        uint256 _maxMultiplier,
        string memory _receiptTokenName,
        string memory _receiptTokenSymbol
    ) public returns (uint256) {
        DiamondHandsLinear newLinear = new DiamondHandsLinear(
            _token,
            _minLockDuration,
            _maxLockDuration,
            _maxMultiplier,
            _receiptTokenName,
            _receiptTokenSymbol
        );
        uint256 id = linearIdCounter++;
        linearContracts[id] = address(newLinear);
        tokenToLinearIds[_token].push(id);
        tokenToLinearAddresses[_token].push(address(newLinear));
        emit DiamondHandsLinearCreated(id, newLinear);
        return id;
    }

    // New Constant Diamond Hands, use a list to set custom durations and multipliers. 
    function createDiamondHandsConstant(
        address _token,
        uint256[] memory _lockDurations,
        uint256[] memory _multipliers,
        string memory _receiptTokenName,
        string memory _receiptTokenSymbol
    ) public returns (uint256) {
        DiamondHandsConstant newConstant = new DiamondHandsConstant(
            _token,
            _lockDurations,
            _multipliers,
            _receiptTokenName,
            _receiptTokenSymbol
        );
        uint256 id = constantIdCounter++;
        constantContracts[id] = address(newConstant);
        tokenToConstantIds[_token].push(id);
        tokenToConstantAddresses[_token].push(address(newConstant));
        emit DiamondHandsConstantCreated(id, newConstant);
        return id;
    }

}
