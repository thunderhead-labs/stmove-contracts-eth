// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {fstMOVE} from "./token/fstMOVE.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./mock/NativeBridge.sol";

/**
 * @dev Lock and mint contract for the stMOVE incentivization program pre-movement TGE
 *
 * This contract will receive assets from users and mint them a corresponding fstMOVE token (future-staked-move).
 *
 * This token does not have any value and is just a placeholder for users to see their APY increasing in their wallets, and the ledger that will be uploaded to the corresponding receiver contract on movement will accept the *deposits* mapping as the ledger.
 *
 * Controlled by the owner of this contract, this contract can be frozen and all movement tokens can be bridged to any address on movement through their native bridge
 */
contract Lock is Initializable, OwnableUpgradeable {
    fstMOVE public fstmove;
    IERC20 public move;
    NativeBridge public movementBridge;
    bool public frozen;

    /**
     * @dev ledger of deposits for different move address (movement l2 address -> future stmove balance)
     */
    mapping(address => bytes32) public designated;

    event Deposit(address eth, uint256 amount, bytes32 moveAddress);
    event Redesignation(bytes32 oldAddress, bytes32 newAddress);

    /**
     * @dev initialize contract variables and make gov_ the owner of this contract
     */
    function initialize(address fstMOVE_, address move_, address bridge_, address gov_) public initializer {
        __Ownable_init(gov_);

        fstmove = fstMOVE(fstMOVE_);
        move = IERC20(move_);
        movementBridge = NativeBridge(bridge_);
    }

    /**
     * @dev deposit function for any user to deposit move -> fstMOVE
     */
    function deposit(uint256 amount, bytes32 moveAddress) public {
        require(!frozen, "lock period has ended");

        move.transferFrom(msg.sender, address(this), amount);
        fstmove.mintAssets(msg.sender, amount);

        designated[msg.sender] = moveAddress;

        emit Deposit(msg.sender, amount, moveAddress);
    }

    /**
     * @dev Redesignate movement L2 address to receive the stMOVE
     */
    function redesignate(bytes32 moveAddress) public {
        require(!frozen, "lock period has ended");

        emit Redesignation(designated[msg.sender], moveAddress);

        designated[msg.sender] = moveAddress;
    }

    /**
     * @dev gov function to bridge amount (or max) of tokens to a move address
     */
    function bridge(bytes32 moveAddress, uint256 amount, bool max) public onlyOwner {
        if (max) {
            movementBridge.initiateBridgeTransfer(moveAddress, move.balanceOf(address(this)));
        } else {
            movementBridge.initiateBridgeTransfer(moveAddress, amount);
        }
    }

    /**
     * @dev disable deposits
     */
    function freeze() public onlyOwner {
        frozen = true;
    }

    /**
     * @dev briege tokens and freeze contract atomically
     */
    function bridgeAndFreeze(bytes32 moveAddress, uint256 amount, bool max) public onlyOwner {
        freeze();
        bridge(moveAddress, amount, max);
    }
}
