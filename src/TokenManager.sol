// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/metatx/ERC2771Context.sol";
import "./ITokenManager.sol";
import "./IAccessControl.sol";

/// @title Token Manager Module
/// @notice Gère les tokens IQS et OST, les soldes, les transferts, les holders, les frais et le taux de conversion

contract TokenManager is ITokenManager, ERC2771Context {
    using EnumerableSet for EnumerableSet.AddressSet;

    IAccessControl public accessControl;
    
    uint256 public iqosysTreasuryShareLimit = maxSupplyIQS / 10; // Limite de 10% pour la trésorerie IQS.

    // --- IQS Token ---
    string public constant override nameIQS = "IQOSYS Equity Token";
    string public constant override symbolIQS = "IQS";
    uint8  public constant override decimalsIQS = 0;
    uint256 public constant override maxSupplyIQS = 800_000;
    uint256 public override totalSupplyIQS;
    mapping(address => uint256) private _balancesIQS;
    EnumerableSet.AddressSet private tokenHoldersIQS; 
    event TransferIQS(address indexed from, address indexed to, uint256 amount);

    // --- OST Token ---
    string public constant override nameOST = "IQOSYS Ordinary Share Token";
    string public constant override symbolOST = "OST";
    uint256 public constant override initialSupplyOST = 200_000;
    uint256 public totalSupplyOST;
    mapping(address => uint256) private _balancesOST;
    EnumerableSet.AddressSet private tokenHoldersOST;
    event TransferOST(address indexed from, address indexed to, uint256 amount);


    /// @param _accessControl Address du module de contrôle d'accès
    /// @param forwarder Address du Trusted Forwarder

    constructor(address _accessControl, address forwarder) ERC2771Context(forwarder) {
        accessControl = IAccessControl(_accessControl);

        address owner = accessControl.owner();
        _balancesOST[owner] = initialSupplyOST;
        tokenHoldersOST.add(owner);
        totalSupplyOST = initialSupplyOST;
    }                           
                        
    // --- IQS Functions ---
    function balanceOfIQS(address account) external view override returns (uint256) {
        return _balancesIQS[account];
    }

    function transferIQSfromAtoB(address from, address to, uint256 amount) external {
  
        require(_balancesIQS[from] >= amount, "Insufficient IQS balance");

        _balancesIQS[from] -= amount;
        _balancesIQS[to] += amount;
        this._addIQSHolder(from);
        this._addIQSHolder(to);
        emit TransferIQS(from, to, amount);
    }

    function transferIQStoIQS(address to, uint256 amount) external {

        address sender = _msgSender();

        require(accessControl.isWhiteListed(sender), "Sender not whitelisted");
        require(accessControl.isAuthorized(sender), "Sender not authorized");
        require(!accessControl.isFrozen(sender), "Sender is frozen");
        require(_balancesIQS[sender] >= amount, "Insufficient IQS balance");

        _balancesIQS[sender] -= amount;
        _balancesIQS[to] += amount;
        this._addIQSHolder(sender);
        this._addIQSHolder(to);
        emit TransferIQS(sender, to, amount);
    }

    function mintIQS(uint256 amount) external override {

        address sender = _msgSender();
        require(sender == accessControl.owner(), "Only owner");
        require(amount > 0, "Amount must be greater than zero");
        require(totalSupplyIQS + amount <= maxSupplyIQS, "Exceeds max supply");
        require( _balancesIQS[sender] + amount <= iqosysTreasuryShareLimit, "Exceeds treasury limit");

        _balancesIQS[sender] += amount;
        totalSupplyIQS += amount;
    }

    function burnIQS(uint256 amount, address acc) external {
        require(accessControl.isAdmin(_msgSender()), "Caller is not an admin");
        require(amount > 0, "Amount must be greater than zero");
        require(_balancesIQS[acc] >= amount, "Insufficient IQS balance");

        _balancesIQS[acc] -= amount;
        totalSupplyIQS -= amount;
    }



    // --- OST Functions ---
    function balanceOfOST(address account) external view override returns (uint256) {
        return _balancesOST[account];
    }

    function totalSupplyOSTf() external view returns (uint256) {
        return totalSupplyOST;
    }

    function maxSupplyOSTf() external pure returns (uint256) {
        return initialSupplyOST;
    }

    function transferOSTfromAtoB(address from, address to, uint256 amount) external {
        require(_balancesOST[from] >= amount, "Insufficient OST balance");

        _balancesOST[from] -= amount;
        _balancesOST[to] += amount;
        this._addOSTHolder(from);
        this._addOSTHolder(to);
        emit TransferOST(from, to, amount);
    }

    function transferOSTtoOST(address to, uint256 amount) external {

        address sender = _msgSender();

        require(accessControl.isWhiteListed(sender), "Sender not white-listed");
        require(accessControl.isAuthorized(sender), "Sender not authorized");
        require(!accessControl.isFrozen(sender), "Sender is frozen");
        require(_balancesOST[sender] >= amount, "Insufficient OST balance");

        _balancesOST[sender] -= amount;
        _balancesOST[to] += amount;
        this._addOSTHolder(sender);
        this._addOSTHolder(to);
        emit TransferOST(sender, to, amount);
    }

    // --- Holders ---
    function getIQSHolders() external view override returns (address[] memory, uint256[] memory) {
        uint256 count = tokenHoldersIQS.length();
        address[] memory addrs = new address[](count);
        uint256[] memory bals = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            address acc = tokenHoldersIQS.at(i);
            addrs[i] = acc;
            bals[i]  = _balancesIQS[acc];
        }
        return (addrs, bals);
    }

    function getOSTHolders() external view override returns (address[] memory, uint256[] memory) {
        uint256 count = tokenHoldersOST.length();
        address[] memory addrs = new address[](count);
        uint256[] memory bals = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            address acc = tokenHoldersOST.at(i);
            addrs[i] = acc;
            bals[i]  = _balancesOST[acc];
        }
        return (addrs, bals);
    }

    

    function _addIQSHolder(address account) external {
        if (_balancesIQS[account] > 0 && !tokenHoldersIQS.contains(account)) {
            tokenHoldersIQS.add(account);
        }
    }

    function _addOSTHolder(address account) external {
        if (_balancesOST[account] > 0 && !tokenHoldersOST.contains(account)) {
            tokenHoldersOST.add(account);
        }
    }


    // For testing purposes
    function setBalanceForTesting(
        address account,
        uint256 iqosBalance,
        uint256 ostBalance
    ) external {
        require(_msgSender() == accessControl.owner(), "Only owner can set balances");
        _balancesIQS[account] = iqosBalance;
        _balancesOST[account] = ostBalance;
        
        if (iqosBalance > 0) {
            this._addIQSHolder(account);
        }
        if (ostBalance > 0) {
            this._addOSTHolder(account);
        }
    }

    function setTotalSupplyForTesting(
        uint256 iqosSupply,
        uint256 ostSupply
    ) external {
        require(_msgSender() == accessControl.owner(), "Only owner can set total supply");
        totalSupplyIQS = iqosSupply;
        totalSupplyOST = ostSupply;
    }

    function getBalancesForTesting(address account) external view override returns (uint256 iqosBalance, uint256 ostBalance) {
        iqosBalance = _balancesIQS[account];
        ostBalance = _balancesOST[account];
    }



    function _msgSender() internal view override(ERC2771Context) returns (address) {
        return ERC2771Context._msgSender();
    }

    function _msgData() internal view override(ERC2771Context) returns (bytes calldata) {
        return ERC2771Context._msgData();
    }

    function _contextSuffixLength() internal view override(ERC2771Context) returns (uint256) {
        return ERC2771Context._contextSuffixLength();
    }
}