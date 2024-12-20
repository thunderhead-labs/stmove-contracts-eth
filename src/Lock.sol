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
 * This token does not have any value and is just a placeholder for users to see their APY increasing in their wallets, and the ledger that will be uploaded
 * to the corresponding receiver contract on movement will accept the *designated* mapping in tandem with fstMOVE balances as the ledger.
 *
 * Controlled by the owner of this contract, this contract can be frozen and all movement tokens can be bridged to any address on movement through their native bridge
 */
contract Lock is Initializable, OwnableUpgradeable {
    fstMOVE public fstmove;
    IERC20 public move;
    NativeBridge public movementBridge;
    bool public frozen;
    bool public redemptions;

    /**
     * @dev ledger of deposits for different move address (movement l2 address -> future stmove balance)
     */
    mapping(address => bytes32) public designated;

    event Deposit(address eth, uint256 amount, bytes32 moveAddress);
    event Redesignation(bytes32 oldAddress, bytes32 newAddress);

    error LockPeriodEnded();
    error InvalidRedemptionPeriod();

    constructor() {
        _disableInitializers();
    }
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
        if (frozen) {
            revert LockPeriodEnded();
        }

        move.transferFrom(msg.sender, address(this), amount);
        fstmove.mintAssets(msg.sender, amount);

        designated[msg.sender] = moveAddress;

        emit Deposit(msg.sender, amount, moveAddress);
    }

    /**
     * @dev Redesignate movement L2 address to receive the stMOVE
     */
    function redesignate(bytes32 moveAddress) public {
        if (frozen) {
            revert LockPeriodEnded();
        }

        emit Redesignation(designated[msg.sender], moveAddress);

        designated[msg.sender] = moveAddress;
    }

    /**
     * @dev gov function to bridge amount (or max) of tokens to a move address
     */
    function bridge(bytes32 moveAddress, uint256 amount, bool max) public onlyOwner {
        if (max) {
            move.approve(address(movementBridge), move.balanceOf(address(this)));
            movementBridge.initiateBridgeTransfer(moveAddress, move.balanceOf(address(this)));
        } else {
            move.approve(address(movementBridge), amount);
            movementBridge.initiateBridgeTransfer(moveAddress, amount);
        }
    }

    /**
     * @dev disable deposits
     */
    function setFreeze(bool status) public onlyOwner {
        frozen = status;
    }

    function setMoveBridge(address bridge_) public onlyOwner {
        movementBridge = NativeBridge(bridge_);
    }

    /**
     * @dev set redemptions
     */
    function setRedemptions(bool x) public onlyOwner {
        redemptions = x;
    }

    /**
     * @dev redeem fstMOVE for its corresponding amount of move
     */
    function redeem(address to, uint256 amount) public {
        if (!redemptions) {
            revert InvalidRedemptionPeriod();
        }

        fstmove.burnAssets(msg.sender, amount);
        move.transfer(to, fstmove.sharesToAssets(fstmove.assetsToShares(amount))); // must do this weird function inverse composition to avoid rounding problems
    }
}
