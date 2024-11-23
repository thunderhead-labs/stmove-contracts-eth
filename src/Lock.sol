pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {fstMOVE} from "./token/fstMOVE.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./mock/NativeBridge.sol";

contract Lock is Initializable, OwnableUpgradeable {
	fstMOVE public fstmove;
	IERC20 public move;
	NativeBridge public movementBridge;

	mapping(bytes32 => uint256) public deposits;

	event Deposit(address eth, uint256 amount, bytes32 moveAddress);

	function initialize(address fstMOVE_, address move_, address bridge_) public initializer {
		__Ownable_init(msg.sender);

		fstmove = fstMOVE(fstMOVE_);
		move = IERC20(move_);
		movementBridge = NativeBridge(bridge_);
	}

	function deposit(address to, uint256 amount, bytes32 moveAddress) external {
		move.transferFrom(msg.sender, address(this), amount);
		fstmove.mintAssets(to, amount);

		deposits[moveAddress] += amount;

		emit Deposit(to, amount, moveAddress);
	}

	function bridge(bytes32 moveAddress, uint256 amount, bool max) external onlyOwner {
		if (max) {
			movementBridge.initiateBridgeTransfer(moveAddress, move.balanceOf(address(this)));
		} else {
			movementBridge.initiateBridgeTransfer(moveAddress, amount);
		}
	}
}
