// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {AccessControlDefaultAdminRulesUpgradeable} from
    "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";

/**
 * @dev Non-transferable and rebasing read-only ERC20 token
 *
 * This contract has a permissioned mintAssets function available to the designated lock contract (see ../Lock.sol)
 *
 * This contract has the ability to mint users a placeholder ERC20 token (that is read-only; non-transferable; non-approval; non-burnable) representing their deposit from the Lock contract.
 * In order to increase user balances to reflect depositer APY, there is a share rate that is linearly increased to reach a target threshold at a certain time.
 */
contract fstMOVE is IERC20, IERC20Metadata, IERC20Errors, AccessControlDefaultAdminRulesUpgradeable {
    bytes32 public constant LOCK_ROLE = keccak256("LOCK_ROLE");

    mapping(address account => uint256) private _shares;
    mapping(address account => mapping(address spender => uint256)) private _allowances;
    mapping(address account => bool) private _whitelisted;

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

    error TransferNotSupported();
    error NegativeRebaseNotAllowed();
    error UpdateMustBeInFuture();
    error NotWhitelisted();
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
     * @dev See {IERC20-approve}.
     *
     * NOTE: If `value` is the maximum `uint256`, the allowance is not updated on
     * `transferFrom`. This is semantically equivalent to an infinite approval.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function approve(address spender, uint256 value) public virtual returns (bool) {
        if (!_whitelisted[spender]) {
            revert NotWhitelisted();
        }

        address owner = _msgSender();
        _approve(owner, spender, value);
        return true;
    }

    /**
     * @dev Sets `value` as the allowance of `spender` over the `owner` s tokens.
     *
     * This internal function is equivalent to `approve`, and can be used to
     * e.g. set automatic allowances for certain subsystems, etc.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `owner` cannot be the zero address.
     * - `spender` cannot be the zero address.
     *
     * Overrides to this logic should be done to the variant with an additional `bool emitEvent` argument.
     */
    function _approve(address owner, address spender, uint256 value) internal {
        _approve(owner, spender, value, true);
    }

    /**
     * @dev Variant of {_approve} with an optional flag to enable or disable the {Approval} event.
     *
     * By default (when calling {_approve}) the flag is set to true. On the other hand, approval changes made by
     * `_spendAllowance` during the `transferFrom` operation set the flag to false. This saves gas by not emitting any
     * `Approval` event during `transferFrom` operations.
     *
     * Anyone who wishes to continue emitting `Approval` events on the`transferFrom` operation can force the flag to
     * true using the following override:
     *
     * Requirements are the same as {_approve}.
     */
    function _approve(address owner, address spender, uint256 value, bool emitEvent) internal virtual {
        if (owner == address(0)) {
            revert ERC20InvalidApprover(address(0));
        }
        if (spender == address(0)) {
            revert ERC20InvalidSpender(address(0));
        }
        _allowances[owner][spender] = value;
        if (emitEvent) {
            emit Approval(owner, spender, value);
        }
    }

    /**
     * @dev Updates `owner` s allowance for `spender` based on spent `value`.
     *
     * Does not update the allowance value in case of infinite allowance.
     * Revert if not enough allowance is available.
     *
     * Does not emit an {Approval} event.
     */
    function _spendAllowance(address owner, address spender, uint256 value) internal virtual {
        uint256 currentAllowance = allowance(owner, spender);

        if (currentAllowance < type(uint256).max) {
            if (currentAllowance < value) {
                revert ERC20InsufficientAllowance(spender, currentAllowance, value);
            }
            unchecked {
                _approve(owner, spender, currentAllowance - value, false);
            }
        }
    }

    /**
     * @dev Moves a `value` amount of tokens from `from` to `to`.
     *
     * This internal function is equivalent to {transfer}, and can be used to
     * e.g. implement automatic token fees, slashing mechanisms, etc.
     *
     * Emits a {Transfer} event.
     *
     * NOTE: This function is not virtual, {_update} should be overridden instead.
     */
    function _transfer(address from, address to, uint256 value) internal {
        if (from == address(0)) {
            revert ERC20InvalidSender(address(0));
        }
        if (to == address(0)) {
            revert ERC20InvalidReceiver(address(0));
        }
        _update(from, to, value);
    }

    /**
     * @dev See {IERC20-transferFrom}.
     *
     * Skips emitting an {Approval} event indicating an allowance update. This is not
     * required by the ERC. See {xref-ERC20-_approve-address-address-uint256-bool-}[_approve].
     *
     * NOTE: Does not update the allowance if the current allowance
     * is the maximum `uint256`.
     *
     * Requirements:
     *
     * - `from` and `to` cannot be the zero address.
     * - `from` must have a balance of at least `value`.
     * - the caller must have allowance for ``from``'s tokens of at least
     * `value`.
     */
    function transferFrom(address from, address to, uint256 value) public virtual returns (bool) {
        if (!_whitelisted[to]) {
            revert NotWhitelisted();
        }

        address spender = _msgSender();
        _spendAllowance(from, spender, value);
        _transfer(from, to, value);
        return true;
    }

    /**
     * @dev See {IERC20-allowance}.
     */
    function allowance(address owner, address spender) public view virtual returns (uint256) {
        return _allowances[owner][spender];
    }

    /**
     * Fulfill IERC20 interface
     * Token not transferable
     */
    function transfer(address, uint256) public virtual returns (bool) {
        revert TransferNotSupported();
    }

    /**
     * @dev whitelist a recipient that tokens can be transferred to
     */
    function whitelist(address recipient) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _whitelisted[recipient] = true;
    }

    /**
     * @dev blacklist a recipient
     */
    function blacklist(address recipient) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _whitelisted[recipient] = false;
    }

    /**
     * @dev See if an address is whitelisted
     */
    function whitelisted(address recipient) public view virtual returns (bool) {
        return _whitelisted[recipient];
    }
}
