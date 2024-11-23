pragma solidity ^0.8.20;

contract NativeBridge {
    mapping(bytes32 => uint256) public transfers;

    // MOCK OF https://github.com/movementlabsxyz/movement/blob/main/protocol-units/bridge/contracts/src/NativeBridge.sol#L43
    function initiateBridgeTransfer(bytes32 recipient, uint256 amount) public {
        transfers[recipient] += amount;
    }
}
