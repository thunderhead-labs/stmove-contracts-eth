// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

/**
 * @dev Non-transferable and rebasing read-only ERC20 token
 *
 * This contract has a permissioned mintAssets function available to the designated lock contract (see ../Lock.sol)
 *
 * This contract has the ability to mint users a placeholder ERC20 token (that is read-only; non-transferable; non-approval; non-burnable) representing their deposit from the Lock contract.
 * In order to increase user balances to reflect depositer APY, there is a share rate that is linearly increased to reach a target threshold at a certain time.
 *
 * The ability to rebase this contract or change the share rate to a different function is permissioned to the _gov address, defined when the contract is deployed.
 */
contract fstMOVE is Context, IERC20, IERC20Metadata, IERC20Errors {
    mapping(address account => uint256) private _shares;

    uint256 public BASE = 10 ** 18;

    // Variables uesd for increasing user balances linearly over time
    uint256 public lastShareRate = 10 ** 18;
    uint256 public lastUpdateTime;

    uint256 public nextShareRate;
    uint256 public nextUpdateTime;

    uint256 private _totalSupply;

    string private _name;
    string private _symbol;

    address public _lock;
    address public _gov;

    bool destructed = false;

    /**
     * @dev Sets the values for {name} and {symbol}.
     *
     * All two of these values are immutable: they can only be set once during
     * construction.
     */
    constructor(string memory name_, string memory symbol_, address lock_, address gov_) {
        _name = name_;
        _symbol = symbol_;
        _lock = lock_;
        _gov = gov_;

        lastUpdateTime = block.timestamp;
        nextUpdateTime = block.timestamp + 1;
        nextShareRate = BASE;
    }

    /**
     * @dev Returns the current share rate based on the nextShareRate and the current progress of reaching nextUpdateTime
     *
     */
    function shareRate() public view virtual returns (uint256) {
        if (block.timestamp < nextUpdateTime && lastUpdateTime <= block.timestamp) {
            uint256 m = (nextShareRate - lastShareRate) * BASE / (nextUpdateTime - lastUpdateTime);
            uint256 b = lastShareRate;

            return m * (block.timestamp - lastUpdateTime) / BASE + b;
        } else {
            return nextShareRate;
        }
    }

    /**
     * @dev convert base shares to assets (shares -> fstMOVE balance).
     *
     */
    function sharesToAssets(uint256 shares) public view virtual returns (uint256) {
        return shares * shareRate() / BASE;
    }

    /**
     * @dev convert assets (fstMOVE) to underlying shares
     *
     */
    function assetsToShares(uint256 assets) public view virtual returns (uint256) {
        return assets * BASE / shareRate();
    }

    /**
     * @dev Returns the name of the token.
     */
    function name() public view virtual returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() public view virtual returns (string memory) {
        return _symbol;
    }

    /**
     * @dev Returns the number of decimals used to get its user representation.
     * For example, if `decimals` equals `2`, a balance of `505` tokens should
     * be displayed to a user as `5.05` (`505 / 10 ** 2`).
     *
     * Tokens usually opt for a value of 18, imitating the relationship between
     * Ether and Wei. This is the default value returned by this function, unless
     * it's overridden.
     *
     * NOTE: This information is only used for _display_ purposes: it in
     * no way affects any of the arithmetic of the contract, including
     * {IERC20-balanceOf} and {IERC20-transfer}.
     */
    function decimals() public view virtual returns (uint8) {
        return 18;
    }

    /**
     * @dev See {IERC20-totalSupply}.
     */
    function totalSupply() public view virtual returns (uint256) {
        return _totalSupply * shareRate() / BASE;
    }

    /**
     * @dev Return the total number of shares ~ assetsToShares(totalSupply())
     */
    function totalShares() public view virtual returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev See {IERC20-balanceOf}.
     */
    function balanceOf(address account) public view virtual returns (uint256) {
        if (destructed) {
            return 0;
        }

        return _shares[account] * shareRate() / BASE;
    }

    function sharesOf(address account) public view virtual returns (uint256) {
        return _shares[account];
    }

    /**
     * @dev Transfers a `value` amount of tokens from `from` to `to`, or alternatively mints (or burns) if `from`
     * (or `to`) is the zero address. All customizations to transfers, mints, and burns should be done by overriding
     * this function.
     *
     * Emits a {Transfer} event.
     */
    function _update(address from, address to, uint256 value) internal virtual {
        if (from == address(0)) {
            // Overflow check required: The rest of the code assumes that totalSupply never overflows
            _totalSupply += value;
        } else {
            uint256 fromBalance = _shares[from];
            if (fromBalance < value) {
                revert ERC20InsufficientBalance(from, fromBalance, value);
            }
            unchecked {
                // Overflow not possible: value <= fromBalance <= totalSupply.
                _shares[from] = fromBalance - value;
            }
        }

        if (to == address(0)) {
            unchecked {
                // Overflow not possible: value <= totalSupply or value <= fromBalance <= totalSupply.
                _totalSupply -= value;
            }
        } else {
            unchecked {
                // Overflow not possible: balance + value is at most totalSupply, which we know fits into a uint256.
                _shares[to] += value;
            }
        }

        emit Transfer(from, to, value);
    }

    /**
     * @dev Creates a `value` amount of tokens and assigns them to `account`, by transferring it from address(0).
     * Relies on the `_update` mechanism
     *
     * Emits a {Transfer} event with `from` set to the zero address.
     *
     * NOTE: This function is not virtual, {_update} should be overridden instead.
     */
    function _mint(address account, uint256 value) internal {
        if (account == address(0)) {
            revert ERC20InvalidReceiver(address(0));
        }
        _update(address(0), account, value);
    }

    /**
     * @dev Mint assets worth of shares to account
     */
    function mintAssets(address account, uint256 value) external {
        require(msg.sender == _lock, "mints can only be executed from lock contract");

        _mint(account, assetsToShares(value));
    }

    event Rebase(uint256 shareRate, uint256 updateTime);

    /**
     * @dev Update next share rate
     */
    function rebase(uint256 nextShareRate_, uint256 nextUpdateTime_) external {
        require(msg.sender == _gov, "rebases must be executed by gov");
        require(nextShareRate_ >= lastShareRate, "cannot negatively rebase");
        require(nextUpdateTime_ >= lastUpdateTime, "update must be in the future");

        if (nextUpdateTime > block.timestamp) {
            lastUpdateTime = block.timestamp;
        } else {
            lastUpdateTime = nextUpdateTime;
        }

        lastShareRate = nextShareRate;
        nextShareRate = nextShareRate_;
        nextUpdateTime = nextUpdateTime_;

        emit Rebase(nextShareRate, nextUpdateTime);
    }

    /**
     * @dev Destruct sets all balanceOf() calls to return 0 to prevent user wallet cloggage
     */
    function destruct(bool x) external {
        require(msg.sender == _gov);

        destructed = x;
    }

    /**
     * @dev Change gov role
     */
    function _changeGov(address newGov) external {
        require(msg.sender == _gov);

        _gov = newGov;
    }

    /**
     * Fulfill IERC20 interface
     *
     */
    function transferFrom(address, address, uint256) public virtual returns (bool) {
        revert("transferFrom not supported");
    }

    function transfer(address, uint256) public virtual returns (bool) {
        revert("transferring not supported");
    }

    function allowance(address, address) public view virtual returns (uint256) {
        return 0;
    }

    function approve(address, uint256) public virtual returns (bool) {
        revert("approvals not supported");
    }
}
