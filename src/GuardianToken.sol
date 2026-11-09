// SPDX-License-Identifier: MIT

pragma solidity ^0.8.29;

/// @title Guardian Test Token (GTT)
/// @notice Minimal hand-rolled ERC-20 used as the asset protected by the GuardianVault.
/// @dev No external dependencies. The deployer is the owner and the only minter.
contract GuardianToken {
    string public constant name = "Guardian Test Token";
    string public constant symbol = "GTT";
    uint8 public constant decimals = 18;

    uint256 public totalSupply;
    address public immutable owner;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed tokenOwner, address indexed spender, uint256 value);

    error NotOwner();
    error ZeroAddress();
    error InsufficientBalance(uint256 available_, uint256 required_);
    error InsufficientAllowance(uint256 available_, uint256 required_);

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    /// @notice Creates new tokens for `to_`. Owner only.
    function mint(address to_, uint256 amount_) external onlyOwner {
        if (to_ == address(0)) revert ZeroAddress();
        totalSupply += amount_;
        balanceOf[to_] += amount_;
        emit Transfer(address(0), to_, amount_);
    }

    function transfer(address to_, uint256 amount_) external returns (bool) {
        _transfer(msg.sender, to_, amount_);
        return true;
    }

    function approve(address spender_, uint256 amount_) external returns (bool) {
        allowance[msg.sender][spender_] = amount_;
        emit Approval(msg.sender, spender_, amount_);
        return true;
    }

    function transferFrom(address from_, address to_, uint256 amount_) external returns (bool) {
        uint256 allowed = allowance[from_][msg.sender];
        if (allowed < amount_) revert InsufficientAllowance(allowed, amount_);
        if (allowed != type(uint256).max) {
            allowance[from_][msg.sender] = allowed - amount_;
        }
        _transfer(from_, to_, amount_);
        return true;
    }

    function _transfer(address from_, address to_, uint256 amount_) internal {
        if (to_ == address(0)) revert ZeroAddress();
        uint256 balance = balanceOf[from_];
        if (balance < amount_) revert InsufficientBalance(balance, amount_);
        balanceOf[from_] = balance - amount_;
        balanceOf[to_] += amount_;
        emit Transfer(from_, to_, amount_);
    }
}
