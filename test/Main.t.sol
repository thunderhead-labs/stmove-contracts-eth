pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Lock.sol";
import "../src/token/fstMOVE.sol";
import "../src/mock/NativeBridge.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Move is ERC20 {
    constructor() ERC20("move", "move") {
        _mint(msg.sender, type(uint256).max);
    }
}

contract LockTest is Test {
    NativeBridge bridge;
    Lock lock;
    fstMOVE fstmove;
    ERC20 move;

    function setUp() public {
        move = new Move();
        bridge = new NativeBridge();

        Lock lock_ = new Lock();
        lock = Lock(address(new TransparentUpgradeableProxy(address(lock_), address(this), "")));

        fstmove = new fstMOVE("future staked move", "fstmove", address(lock), address(this));

        lock.initialize(address(fstmove), address(move), address(bridge));
    }

    function testFuzz_Deposit(uint256 a, bytes32 b) public {
        a = bound(a, 0, 10 ** 40);

        move.approve(address(lock), a);
        lock.deposit(address(1), a, b);

        assertEq(move.balanceOf(address(lock)), a);
        assertEq(fstmove.balanceOf(address(1)), a);
        assertEq(lock.deposits(b), a);
    }

    function testFuzz_Rebase(uint256 a, uint256 f, uint256 t1, uint256 t2) public {
        f = bound(f, 10 ** 18, 10 ** 24);
        a = bound(a, 0, 10 ** 40);
        t1 = bound(t1, 10, 10 ** 8);
        t2 = bound(t2, 10, 10 ** 8);

        testFuzz_Deposit(a, bytes32(0));

        fstmove.rebase(f, t2);
        uint256 t0 = block.timestamp + 1;

        vm.warp(t1);

        if (t1 >= t2) {
            assertEq(fstmove.shareRate(), f, "wrong share rate; a");
            assertEq(fstmove.balanceOf(address(1)), a * f / 10 ** 18, "wrong fstmove balance; a");
        } else {
            uint256 m = (f - 10 ** 18) * 10 ** 18 / (t2 - t0);
            uint256 b = 10 ** 18;
            uint256 y = (m * t1 / 10 ** 18) + b;
            console.log("ALT SHARE RATE CALC");
            console.log(f, t1, t2, t0);

            assertEq(fstmove.shareRate(), y, "wrong share rate; b");
            assertEq(fstmove.balanceOf(address(1)), a * y / 10 ** 18, "wrong fstmove balance; b");
        }
    }
}
