// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./interfaces/IPositionRouter.sol";

contract PositionRouter is BasePosotionManager, IPositionRouter {

    function createIncreasePosition(
        address[] memroy _path,
        address _indexToken,
        uint256 _sizeDelta,
        uint256 _minOut,
        bool _isLong,
        uint256 _acceptablePrice,
        uint256 _executionFee,
        address _callbackTarget
    ) external payable nonReentrant returns (bytes32) {
        require(_executionFee >= minExecutionFee, "PositionRouter: execution fee too low");
        require(msg.value == _executionFee, "PositionRouter: execution fee not sent");
        require(_path.length == 1 || _path.length == 2, "PositionRouter: invalid path length");
        
        _transferInETH();
    }
}