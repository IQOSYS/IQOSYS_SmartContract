// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

import "./ITokenManager.sol";
import "./IAccessControl.sol";

/// @title Token Manager Module
/// @notice Manages IQS and OST balances, supply, holders, minting, burning and controlled transfers.
contract TokenManager is
    ITokenManager,
    ReentrancyGuard,
    Pausable
{
    using EnumerableSet for EnumerableSet.AddressSet;

    IAccessControl public accessControl;

    // -------------------------------------------------------------------------
    // IQS Token
    // -------------------------------------------------------------------------

    string public constant override nameIQS =
        "IQOSYS Equity Token";

    string public constant override symbolIQS =
        "IQS";

    uint8 public constant override decimalsIQS =
        0;

    uint256 public constant override maxSupplyIQS =
        1_000_000;

    uint256 public override totalSupplyIQS;

    mapping(address => uint256) private _balancesIQS;
    EnumerableSet.AddressSet private tokenHoldersIQS;

    event TransferIQS(
        address indexed from,
        address indexed to,
        uint256 amount
    );

    event MintIQS(
        address indexed to,
        uint256 amount
    );

    event BurnIQS(
        address indexed from,
        uint256 amount
    );

    event WalletMigrated(
        address indexed oldWallet,
        address indexed newWallet,
        uint256 iqsAmount,
        uint256 ostAmount,
        bytes32 referenceHash
    );
    // -------------------------------------------------------------------------
    // OST Token
    // -------------------------------------------------------------------------

    string public constant override nameOST =
        "IQOSYS Ordinary Share Token";

    string public constant override symbolOST =
        "OST";

    uint256 public constant override initialSupplyOST =
        200_000;

    uint256 public totalSupplyOST;

    mapping(address => uint256) private _balancesOST;
    EnumerableSet.AddressSet private tokenHoldersOST;

    event TransferOST(
        address indexed from,
        address indexed to,
        uint256 amount
    );

    // -------------------------------------------------------------------------
    // Controlled token operators
    // -------------------------------------------------------------------------

    mapping(address => bool) private tokenOperators;
    mapping(bytes32 => bool) private usedWalletMigrationReferences;
    
    event TokenOperatorUpdated(
        address indexed operator,
        bool status
    );

    event TokenManagerPaused(
        address indexed admin,
        uint256 timestamp
    );

    event TokenManagerUnpaused(
        address indexed admin,
        uint256 timestamp
    );

    /// @param _accessControl Address of the AccessControl module.
    constructor(
        address _accessControl
    ) {
        require(
            _accessControl != address(0),
            "Invalid access control"
        );

        accessControl =
            IAccessControl(_accessControl);

        address treasury =
            accessControl.owner();

        _balancesOST[treasury] =
            initialSupplyOST;

        tokenHoldersOST.add(
            treasury
        );

        totalSupplyOST =
            initialSupplyOST;

        emit TransferOST(
            address(0),
            treasury,
            initialSupplyOST
        );
    }

    modifier onlyAdmin() {
        require(
            accessControl.isAdmin(msg.sender),
            "Caller is not an admin"
        );
        _;
    }

    modifier onlyTokenOperatorOrAdmin() {
        require(
            tokenOperators[msg.sender] ||
                accessControl.isAdmin(msg.sender),
            "Caller is not a token operator"
        );
        _;
    }

    // -------------------------------------------------------------------------
    // Pause
    // -------------------------------------------------------------------------

    function pause()
        external
        override
        onlyAdmin
    {
        _pause();

        emit TokenManagerPaused(
            msg.sender,
            block.timestamp
        );
    }

    function unpause()external override onlyAdmin
    {
        _unpause();

        emit TokenManagerUnpaused(
            msg.sender,
            block.timestamp
        );
    }
    function paused()
        public
        view
        override(ITokenManager, Pausable)
        returns (bool)
    {
        return super.paused();
    }
    // -------------------------------------------------------------------------
    // Token operator management
    // -------------------------------------------------------------------------

    function setTokenOperator(
        address operator,
        bool status
    )
        external
        override
        onlyAdmin
    {
        require(
            operator != address(0),
            "Invalid operator"
        );

        tokenOperators[operator] =
            status;

        emit TokenOperatorUpdated(
            operator,
            status
        );
    }

    function isTokenOperator(
        address operator
    )
        external
        view
        override
        returns (bool)
    {
        return tokenOperators[operator];
    }

    // -------------------------------------------------------------------------
    // IQS functions
    // -------------------------------------------------------------------------

    function balanceOfIQS(
        address account
    )
        external
        view
        override
        returns (uint256)
    {
        return _balancesIQS[account];
    }

    /// @notice Controlled IQS transfer between two addresses.
    /// @dev Only authorized modules/admin can call this. Users cannot transfer freely P2P.
    function transferIQSfromAtoB(
        address from,
        address to,
        uint256 amount
    )
        external
        override
        onlyTokenOperatorOrAdmin
        whenNotPaused
        nonReentrant
    {
        require(
            from != address(0),
            "Invalid from"
        );

        require(
            to != address(0),
            "Invalid to"
        );

        require(
            amount > 0,
            "Amount must be greater than zero"
        );

        require(
            _balancesIQS[from] >= amount,
            "Insufficient IQS balance"
        );

        _balancesIQS[from] -=
            amount;

        _balancesIQS[to] +=
            amount;

        _syncIQSHolder(from);
        _syncIQSHolder(to);

        emit TransferIQS(
            from,
            to,
            amount
        );
    }

    /// @notice Mints IQS to the IQOSYS treasury.
    /// @dev Initial deployment should mint 1,000,000 IQS once to treasury.
    function mintIQS(
        uint256 amount
    )
        external
        override
        onlyAdmin
        whenNotPaused
        nonReentrant
    {
        require(
            amount > 0,
            "Amount must be greater than zero"
        );

        require(
            totalSupplyIQS + amount <= maxSupplyIQS,
            "Exceeds max supply"
        );

        address treasury =
            accessControl.owner();

        _balancesIQS[treasury] +=
            amount;

        totalSupplyIQS +=
            amount;

        _syncIQSHolder(
            treasury
        );

        emit MintIQS(
            treasury,
            amount
        );

        emit TransferIQS(
            address(0),
            treasury,
            amount
        );
    }

    /// @notice Burns IQS from a holder.
    /// @dev Used by conversion/settlement modules after admin/backend approval.
    function burnIQS(
        uint256 amount,
        address account
    )
        external
        override
        onlyTokenOperatorOrAdmin
        whenNotPaused
        nonReentrant
    {
        require(
            account != address(0),
            "Invalid account"
        );

        require(
            amount > 0,
            "Amount must be greater than zero"
        );

        require(
            _balancesIQS[account] >= amount,
            "Insufficient IQS balance"
        );

        _balancesIQS[account] -=
            amount;

        totalSupplyIQS -=
            amount;

        _syncIQSHolder(
            account
        );

        emit BurnIQS(
            account,
            amount
        );

        emit TransferIQS(
            account,
            address(0),
            amount
        );
    }

    // -------------------------------------------------------------------------
    // OST functions
    // -------------------------------------------------------------------------

    function balanceOfOST(
        address account
    )
        external
        view
        override
        returns (uint256)
    {
        return _balancesOST[account];
    }

    function totalSupplyOSTf()
        external
        view
        override
        returns (uint256)
    {
        return totalSupplyOST;
    }

    function maxSupplyOSTf()
        external
        pure
        override
        returns (uint256)
    {
        return initialSupplyOST;
    }

    function transferOSTfromAtoB(
        address from,
        address to,
        uint256 amount
    )
        external
        override
        onlyTokenOperatorOrAdmin
        whenNotPaused
        nonReentrant
    {
        require(
            from != address(0),
            "Invalid from"
        );

        require(
            to != address(0),
            "Invalid to"
        );

        require(
            amount > 0,
            "Amount must be greater than zero"
        );

        require(
            _balancesOST[from] >= amount,
            "Insufficient OST balance"
        );

        _balancesOST[from] -=
            amount;

        _balancesOST[to] +=
            amount;

        _syncOSTHolder(from);
        _syncOSTHolder(to);

        emit TransferOST(
            from,
            to,
            amount
        );
    }

    // -------------------------------------------------------------------------
    // Holders
    // -------------------------------------------------------------------------

    function getIQSHolders()
        external
        view
        override
        returns (
            address[] memory,
            uint256[] memory
        )
    {
        uint256 count =
            tokenHoldersIQS.length();

        address[] memory addrs =
            new address[](count);

        uint256[] memory balances =
            new uint256[](count);

        for (
            uint256 i = 0;
            i < count;
            i++
        ) {
            address account =
                tokenHoldersIQS.at(i);

            addrs[i] =
                account;

            balances[i] =
                _balancesIQS[account];
        }

        return (
            addrs,
            balances
        );
    }

    function getOSTHolders()
        external
        view
        override
        returns (
            address[] memory,
            uint256[] memory
        )
    {
        uint256 count =
            tokenHoldersOST.length();

        address[] memory addrs =
            new address[](count);

        uint256[] memory balances =
            new uint256[](count);

        for (
            uint256 i = 0;
            i < count;
            i++
        ) {
            address account =
                tokenHoldersOST.at(i);

            addrs[i] =
                account;

            balances[i] =
                _balancesOST[account];
        }

        return (
            addrs,
            balances
        );
    }

    function _syncIQSHolder(
        address account
    )
        internal
    {
        if (
            _balancesIQS[account] > 0
        ) {
            tokenHoldersIQS.add(
                account
            );
        } else {
            tokenHoldersIQS.remove(
                account
            );
        }
    }

    function _syncOSTHolder(
        address account
    )
        internal
    {
        if (
            _balancesOST[account] > 0
        ) {
            tokenHoldersOST.add(
                account
            );
        } else {
            tokenHoldersOST.remove(
                account
            );
        }
    }
    function adminMigrateWallet(
        address oldWallet,
        address newWallet,
        bytes32 referenceHash)
        external
        override
        onlyAdmin
        whenNotPaused
        nonReentrant
        returns (
            uint256 iqsAmount,
            uint256 ostAmount
        )
        {
            require(oldWallet != address(0), "Invalid old wallet");
            require(newWallet != address(0), "Invalid new wallet");
            require(oldWallet != newWallet, "Wallets must be different");
            require(referenceHash != bytes32(0), "Invalid reference hash");
            require(!usedWalletMigrationReferences[referenceHash], "Reference already used");

            require(
                oldWallet != accessControl.owner(),
                "Cannot migrate owner wallet"
            );

            require(
                newWallet != accessControl.owner(),
                "New wallet cannot be owner"
            );

            require(
                !accessControl.isAdmin(oldWallet),
                "Cannot migrate admin wallet"
            );

            require(
                !accessControl.isAdmin(newWallet),
                "New wallet cannot be admin"
            );

            require(
                !accessControl.isFrozen(oldWallet),
                "Old wallet is frozen"
            );

            require(
                !accessControl.isFrozen(newWallet),
                "New wallet is frozen"
            );

            require(
                _balancesIQS[newWallet] == 0 &&
                    _balancesOST[newWallet] == 0,
                "New wallet already has funds"
            );

            iqsAmount = _balancesIQS[oldWallet];
            ostAmount = _balancesOST[oldWallet];

            require(
                iqsAmount > 0 || ostAmount > 0,
                "No funds to migrate"
            );

            usedWalletMigrationReferences[referenceHash] = true;

            if (!accessControl.isWhiteListed(newWallet)) {
                accessControl.addToWhiteList(newWallet);
            }

            if (iqsAmount > 0) {
                _balancesIQS[oldWallet] = 0;
                _balancesIQS[newWallet] = iqsAmount;

                _syncIQSHolder(oldWallet);
                _syncIQSHolder(newWallet);

                emit TransferIQS(
                    oldWallet,
                    newWallet,
                    iqsAmount
                );
            }

            if (ostAmount > 0) {
                _balancesOST[oldWallet] = 0;
                _balancesOST[newWallet] = ostAmount;

                _syncOSTHolder(oldWallet);
                _syncOSTHolder(newWallet);

                emit TransferOST(
                    oldWallet,
                    newWallet,
                    ostAmount
                );
            }

            if (accessControl.isAuthorized(oldWallet)) {
                accessControl.revokeAuthorization(oldWallet);
            }

            if (accessControl.isWhiteListed(oldWallet)) {
                accessControl.removeFromWhiteList(oldWallet);
            }

            if (!accessControl.isFrozen(oldWallet)) {
                accessControl.freezeAddress(oldWallet);
            }

            emit WalletMigrated(
                oldWallet,
                newWallet,
                iqsAmount,
                ostAmount,
                referenceHash
            );
        }
}