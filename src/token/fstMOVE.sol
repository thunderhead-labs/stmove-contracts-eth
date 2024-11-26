// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {AccessControlDefaultAdminRulesUpgradeable} from
    "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import "forge-std/console.sol";

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
contract fstMOVE is IERC20, IERC20Metadata, IERC20Errors, AccessControlDefaultAdminRulesUpgradeable {
    bytes32 public constant LOCK_ROLE = keccak256("LOCK_ROLE");

    mapping(address account => uint256) private _shares;

    uint256 public BASE;

    // Variables uesd for increasing user balances linearly over time
    uint256 public lastShareRate;
    uint256 public updateStart;

    uint256 public nextShareRate;
    uint256 public updateEnd;

    uint256 public maxAprThreshold;

    uint256 private _totalSupply;

    string private _name;
    string private _symbol;

    bool destructed = false;

    error TransferFromNotSupported();
    error TransferNotSupported();
    error ApprovalsNotSupported();
    error NegativeRebaseNotAllowed();
    error UpdateMustBeInFuture();
    error AprTooHigh();

    /**
     * @dev Sets the values for {name} and {symbol}.
     *
     * All two of these values are immutable: they can only be set once during
     * construction.
     */
    constructor() {
        _disableInitializers();
    }

    function initialize(string memory name_, string memory symbol_, address lock_, address gov_) public initializer {
        _name = name_;
        _symbol = symbol_;

        __AccessControlDefaultAdminRules_init(0, gov_);
        _grantRole(LOCK_ROLE, lock_);

        updateStart = block.timestamp;
        updateEnd = block.timestamp;
        BASE = 10 ** 8;
        lastShareRate = BASE;
        nextShareRate = BASE;

        maxAprThreshold = 35 * 10 ** 6;
    }

    /**
     * @dev Returns the current share rate based on the nextShareRate and the current progress of reaching updateEnd
     */
    function shareRate() public view returns (uint256) {
        uint256 updateEnd_ = updateEnd;
        uint256 updateStart_ = updateStart;
        uint256 nextShareRate_ = nextShareRate;
        uint256 lastShareRate_ = lastShareRate;

        if (block.timestamp >= updateEnd_) {
            return nextShareRate_;
        }

        if (block.timestamp <= updateStart_) {
            return lastShareRate_;
        }

        uint256 rate = (nextShareRate_ - lastShareRate_) * (block.timestamp - updateStart_)
            / (updateEnd_ - updateStart_) + lastShareRate_;

        return rate;
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
        return 8;
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
    function mintAssets(address account, uint256 value) external onlyRole(LOCK_ROLE) {
        _mint(account, assetsToShares(value));
    }

    event Rebase(uint256 shareRate, uint256 updateTime);

    /**
     * @dev Update share rate by static share rate
     */
    function rebaseByShareRate(uint256 nextShareRate_, uint256 updateEnd_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (nextShareRate_ < lastShareRate) revert NegativeRebaseNotAllowed();
        if (updateEnd_ < block.timestamp) revert UpdateMustBeInFuture();

        lastShareRate = shareRate();
        updateStart = block.timestamp;

        updateEnd = updateEnd_;
        nextShareRate = nextShareRate_;

        emit Rebase(nextShareRate_, updateEnd_);
    }

    /**
     * @dev Increase share rate by APR
     */
    function rebaseByApr(uint256 apr, uint256 updateEnd_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (updateEnd_ < block.timestamp) revert UpdateMustBeInFuture();
        if (apr > maxAprThreshold) revert AprTooHigh();

        uint256 shareRateIncrease = apr * (updateEnd_ - block.timestamp) / 365 days;
        uint256 currentShareRate_ = shareRate();

        lastShareRate = currentShareRate_;
        updateStart = block.timestamp;

        updateEnd = updateEnd_;
        nextShareRate = currentShareRate_ + shareRateIncrease;

        emit Rebase(nextShareRate, updateEnd_);
    }

    /**
     * @dev Destruct sets all balanceOf() calls to return 0 to prevent user wallet cloggage
     */
    function setDestruct(bool status) external onlyRole(DEFAULT_ADMIN_ROLE) {
        destructed = status;
    }

    /**
     * Fulfill IERC20 interface
     * Token not transferable
     */
    function transferFrom(address, address, uint256) public virtual returns (bool) {
        revert TransferFromNotSupported();
    }

    /**
     * Fulfill IERC20 interface
     * Token not transferable
     */
    function transfer(address, uint256) public virtual returns (bool) {
        revert TransferNotSupported();
    }

    /**
     * Fulfill IERC20 interface
     * Token not transferable
     */
    function allowance(address, address) public view virtual returns (uint256) {
        return 0;
    }

    /**
     * Fulfill IERC20 interface
     * Token not transferable
     */
    function approve(address, uint256) public virtual returns (bool) {
        revert ApprovalsNotSupported();
    }
}
