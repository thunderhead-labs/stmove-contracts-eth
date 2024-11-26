// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract NativeBridge {
    mapping(bytes32 => uint256) public transfers;

    IERC20 public move;

    constructor(address move_) {
        move = IERC20(move_);
    }

    // MOCK OF https://github.com/movementlabsxyz/movement/blob/main/protocol-units/bridge/contracts/src/NativeBridge.sol#L43
    function initiateBridgeTransfer(bytes32 recipient, uint256 amount) public {
        transfers[recipient] += amount;
        move.transferFrom(msg.sender, address(this), amount);
    }
}
