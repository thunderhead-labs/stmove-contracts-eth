pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import "../src/Lock.sol";
import "../src/token/fstMOVE.sol";
import "../src/mock/NativeBridge.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "forge-std/console.sol";

contract Move is ERC20 {
    constructor() ERC20("move", "move") {
        _mint(msg.sender, 1000 * 10 ** 18);
    }
}

function deployAll(address move, address bridge, address gov) returns (Lock lock, fstMOVE fstmove) {
    Lock lock_ = new Lock();
    lock = Lock(address(new TransparentUpgradeableProxy(address(lock_), gov, "")));

    fstMOVE fstmove_ = new fstMOVE();
    fstmove = fstMOVE(address(new TransparentUpgradeableProxy(address(fstmove_), gov, "")));

    lock.initialize(address(fstmove), address(move), address(bridge), gov);
    fstmove.initialize("Future Staked MOVE", "fstMOVE", address(lock), gov);
}

contract DeployScript is Script {
    NativeBridge bridge;
    Lock lock;
    fstMOVE fstmove;
    ERC20 move;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address gov = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        move = new Move();
        bridge = new NativeBridge(address(move));

        (Lock lock, fstMOVE fstmove) = deployAll(address(move), address(bridge), gov);

        console.log("Move: ", address(move));
        console.log("fstmove: ", address(fstmove));
        console.log("Bridge: ", address(bridge));
        console.log("Lock: ", address(lock));
        console.log("Gov: ", gov);

        fstmove.rebaseByShareRate(30 * (10 ** 18) / 10, block.timestamp + 365 days);

        move.approve(address(lock), 100 * 10 ** 18);
        lock.deposit(100 * 10 ** 18, bytes32(0));
    }
}
