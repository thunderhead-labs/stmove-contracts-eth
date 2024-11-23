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
        bridge = new NativeBridge();

        Lock lock_ = new Lock();
        lock = Lock(address(new TransparentUpgradeableProxy(address(lock_), gov, "")));

        fstmove = new fstMOVE("future staked move", "fstmove", address(lock), gov);

        lock.initialize(address(fstmove), address(move), address(bridge), gov);

        console.log("Move: ", address(move));
        console.log("fstmove: ", address(fstmove));
        console.log("Bridge: ", address(bridge));
        console.log("Lock: ", address(lock));
        console.log("Gov: ", gov);
    }
}
