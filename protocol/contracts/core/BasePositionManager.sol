// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../tokens/interfaces/IWETH.sol";

import "./interfaces/IPositionRouter.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract PositionRouter is IBasePosotionManager, ReentrancyGuard, AccessControl {

    bytes32 constant public OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    IVault public immutable vault;
    IRouter public immutable router;
    IShortsTracker public immutable shortsTracker;

    IWETH public immutable weth;

    constructor(
        address _vault,
        address _router,
        address _shortsTracker,
        address _weth,
        uint256 _depositFee
    ) public {
        vault = IVault(_vault);
        router = IRouter(_router);
        shortsTracker = IShortsTracker(_shortsTracker);
        weth = IWETH(_weth);
        depositFee = _depositFee;

        grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        grantRole(OPERATOR_ROLE, msg.sender);
    }

    function _transferInETH() internal {
        if (msg.value != 0) {
            weth.deposit{value: msg.value}();
        }
    }
}