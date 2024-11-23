pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract Lock is Initializable, OwnableUpgradeable{
	IERC20 public fstMOVE;
	IERC20 public move;
	NativeBridge public bridge;

	mapping(bytes32 => uint256) public deposits;

	function initialize(address fstMOVE_, address move_, address bridge_) {
		_Ownable_init(owner_);

		fstMOVE = IERC20(fstMOVE_);
		move = IERC20(move_);
		bridge = NativeBridge(bridge_);
	}

	function deposit(address to, uint256 amount, bytes32 moveAddress) external {
		move.transferFrom(msg.sender, address(this), amount);
		fstMOVE.mint(to, amount);

		deposits[moveAddress] += amount;

		emit Deposit(to, amount, moveAddress);
	}

	function bridge(bytes32 moveAddress, uint256 amount, bool max) external onlyOwner {
		if (max) {
			bridge.initiateBridgeTransfer(moveAddress, move.balanceOf(address(this)));
		} else {
			bridge.initiateBridgeTransfer(moveAddress, amount);
		}
	}
}
