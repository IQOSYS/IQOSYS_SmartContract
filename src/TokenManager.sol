// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

import "./ITokenManager.sol";
import "./IAccessControl.sol";

/// @dev OSTTransferModule exposes immutable escrowAddress() and tokenManager() getters.
///      Verifying both during bootstrap prevents accidentally excluding a real holder.
interface IOSTEscrowModuleBinding {
    function activeTransferCount(address wallet) external view returns (uint256);
    function openTransferCount() external view returns (uint256);
    function escrowAddress() external view returns (address);
    function tokenManager() external view returns (address);
    function paused() external view returns (bool);
}

/// @title Token Manager Module
/// @notice AMF production model: IQS are non-transferable BSA rights; OST are ordinary shares moved only by controlled modules.
contract TokenManager is
    ITokenManager,
    ReentrancyGuard,
    Pausable
{
    using EnumerableSet for EnumerableSet.AddressSet;

    IAccessControl public accessControl;

    // -------------------------------------------------------------------------
    // IQS Token / BSA rights
    // -------------------------------------------------------------------------

    string public constant override nameIQS =
        "IQOSYS Subscription Right";

    string public constant override symbolIQS =
        "IQS";

    uint8 public constant override decimalsIQS =
        0;

    /// @notice IQS issuance is unlimited in the AMF model.
    uint256 public constant override maxSupplyIQS =
        type(uint256).max;

    uint256 public override totalSupplyIQS;


    mapping(address => uint256) private _balancesIQS;
    EnumerableSet.AddressSet private tokenHoldersIQS;

    event TransferIQS(
        address indexed from,
        address indexed to,
        uint256 amount
    );

    event IQSAwarded(
        address indexed to,
        uint256 amount,
        bytes32 indexed referenceHash,
        uint256 timestamp
    );

    event BurnIQS(
        address indexed from,
        uint256 amount
    );

    // -------------------------------------------------------------------------
    // OST Token / ordinary shares
    // -------------------------------------------------------------------------

    string public constant override nameOST =
        "IQOSYS Ordinary Share Token";

    string public constant override symbolOST =
        "OST";

    /// @notice No automatic treasury OST mint in production AMF model.
    uint256 public constant override initialSupplyOST =
        0;

    uint256 public totalSupplyOST;

    mapping(address => uint256) private _balancesOST;
    EnumerableSet.AddressSet private tokenHoldersOST;

    // M-9: conservative, permanent holder-slot cap shared by IQS and OST.
    // The EU threshold is LESS THAN 150 persons: 149, not 150.
    // Each wallet ever credited consumes one slot; zeroing a balance does not
    // release it. An authorized holder-wallet migration moves that slot.
    // This is a wallet/ledger guard, NOT proof of how many people received
    // an off-chain offer or of the identity/country/qualification of a person.
    uint256 public constant MAX_REGISTERED_HOLDERS = 149;
    uint256 public registeredHolderCount;
    mapping(address => bool) public hasHolderSlot;
    mapping(address => bool) public retiredHolderWallet;

    event HolderSlotRegistered(address indexed wallet, uint256 totalSlots);
    event HolderSlotMigrated(address indexed oldWallet, address indexed newWallet);

    /// @notice The OSTTransferModule holds custody of escrowed OST, not beneficial ownership.
    /// @dev Configured once during deployment, after OSTTransferModule becomes a token operator.
    address public ostEscrowAddress;

    event OSTEscrowAddressConfigured(address indexed escrowAddress);

    event OSTEscrowAddressRotated(
        address indexed oldEscrow,
        address indexed newEscrow,
        uint256 timestamp
    );

    event TransferOST(
        address indexed from,
        address indexed to,
        uint256 amount
    );

    event MintOST(
        address indexed to,
        uint256 amount,
        bytes32 indexed referenceHash,
        uint256 timestamp
    );

    // -------------------------------------------------------------------------
    // Controlled token operators
    // -------------------------------------------------------------------------

    mapping(address => bool) private tokenOperators;
    mapping(bytes32 => bool) private usedWalletMigrationReferences;
    address public override walletMigrationController;
    address public override tokenOperatorController;
    event TokenOperatorUpdated(
        address indexed operator,
        bool status
    );

    event TokenManagerPaused(
        address indexed admin,
        uint256 timestamp
    );
    event TokenOperatorControllerUpdated(
        address indexed tokenOperatorController,
        uint256 timestamp
    );
    event TokenManagerUnpaused(
        address indexed admin,
        uint256 timestamp
    );

    event WalletMigrated(
        address indexed oldWallet,
        address indexed newWallet,
        uint256 iqsAmount,
        uint256 ostAmount,
        bytes32 referenceHash
    );
    event WalletMigrationControllerUpdated(
        address indexed walletMigrationController,
        uint256 timestamp
    );
    constructor(
        address _accessControl
    ) {
        require(
            _accessControl != address(0),
            "Invalid access control"
        );

        accessControl =
            IAccessControl(_accessControl);
    }

    modifier onlyAdmin() {
        require(
            accessControl.isAdmin(msg.sender),
            "Caller is not an admin"
        );
        _;
    }

    modifier onlyEmergency() {
        require(accessControl.hasRole(accessControl.ROLE_EMERGENCY(), msg.sender), "Caller is not emergency controller");
        _;
    }

    modifier onlyAdminOrEmergency() {
        require(accessControl.isAdmin(msg.sender) || accessControl.hasRole(accessControl.ROLE_EMERGENCY(), msg.sender), "Caller is not an admin or emergency controller");
        _;
    }
    modifier onlyTokenOperator() {
        require(
            tokenOperators[msg.sender],
            "Caller is not a token operator"
        );
        _;
    }
    modifier onlyTokenOperatorControllerOrBootstrapAdmin() {
        require(
            msg.sender == tokenOperatorController ||
                (
                    tokenOperatorController == address(0) &&
                    accessControl.isAdmin(msg.sender)
                ),
            "Caller is not token operator controller"
        );
        _;
    }
    modifier onlyWalletMigrationController() {
        require(
            msg.sender == walletMigrationController,
            "Caller is not wallet migration controller"
        );
        _;
    }
    // -------------------------------------------------------------------------
    // Pause
    // -------------------------------------------------------------------------

    function pause()
        external
        override
        onlyAdminOrEmergency
    {
        _pause();

        emit TokenManagerPaused(
            msg.sender,
            block.timestamp
        );
    }

    function unpause()
        external
        override
        onlyEmergency
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
        onlyTokenOperatorControllerOrBootstrapAdmin
    {
        require(
            operator != address(0),
            "Invalid operator"
        );

        // M-8: never revoke the only permission that can release assets
        // held in a token operator's custody (notably OSTTransferModule).
        // Applies to every operator, including a former escrow module.
        if (!status) {
            require(_balancesOST[operator] == 0, "Operator holds OST");
        }

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
    function setTokenOperatorController(
        address _tokenOperatorController
    )
        external
        override
        onlyAdmin
    {
        require(
            _tokenOperatorController != address(0),
            "Invalid token operator controller"
        );

        require(
            tokenOperatorController == address(0),
            "Token operator controller already set"
        );

        tokenOperatorController =
            _tokenOperatorController;

        emit TokenOperatorControllerUpdated(
            _tokenOperatorController,
            block.timestamp
        );
    }
    function setWalletMigrationController(
        address _walletMigrationController
    )
        external
        override
        onlyAdmin
    {
        require(
            _walletMigrationController != address(0),
            "Invalid wallet migration controller"
        );

        require(
            walletMigrationController == address(0),
            "Wallet migration controller already set"
        );

        walletMigrationController =
            _walletMigrationController;

        emit WalletMigrationControllerUpdated(
            _walletMigrationController,
            block.timestamp
        );
    }
    // -------------------------------------------------------------------------
    // Escrow / holder register setup (M-6)
    // -------------------------------------------------------------------------

    /// @notice One-time binding to the exact OSTTransferModule escrow address.
    /// @dev Does not move or burn OST. It excludes the custodial address from
    ///      getOSTHolders(), while balanceOfOST(escrow) remains the source of
    ///      truth for all OST temporarily in escrow.
    function setOSTEscrowAddress(address escrow) external onlyAdmin {
        require(ostEscrowAddress == address(0), "OST escrow already configured");
        require(escrow != address(0), "Invalid OST escrow");
        require(tokenOperators[escrow], "Escrow is not a token operator");
        require(escrow.code.length > 0, "Escrow must be a contract");
        require(
            IOSTEscrowModuleBinding(escrow).escrowAddress() == escrow,
            "Escrow address mismatch"
        );
        require(
            IOSTEscrowModuleBinding(escrow).tokenManager() == address(this),
            "Escrow token manager mismatch"
        );

        ostEscrowAddress = escrow;
        // Also cleans a pre-existing entry if configured after an escrow transfer.
        tokenHoldersOST.remove(escrow);

        emit OSTEscrowAddressConfigured(escrow);
    }

    /// @notice Safely change the custodial escrow after retiring the old module.
    /// @dev Drain old escrow via ordinary settlement / dispute / reclaim first.
    ///      Pause the old module to prevent a deposit race. Neither this
    ///      function nor operator revocation moves or burns any shares.
    function rotateOSTEscrowAddress(address newEscrow) external onlyAdmin {
        address oldEscrow = ostEscrowAddress;
        require(oldEscrow != address(0), "OST escrow not configured");
        require(newEscrow != address(0), "Invalid OST escrow");
        require(newEscrow != oldEscrow, "Escrow unchanged");
        require(_balancesOST[oldEscrow] == 0, "Old escrow not drained");
        require(IOSTEscrowModuleBinding(oldEscrow).openTransferCount() == 0, "Old escrow has open transfers");
        require(
            IOSTEscrowModuleBinding(oldEscrow).paused(),
            "Old escrow must be paused"
        );
        require(_balancesOST[newEscrow] == 0, "New escrow must be empty");
        require(tokenOperators[newEscrow], "Escrow is not a token operator");
        require(newEscrow.code.length > 0, "Escrow must be a contract");
        require(
            IOSTEscrowModuleBinding(newEscrow).escrowAddress() == newEscrow,
            "Escrow address mismatch"
        );
        require(
            IOSTEscrowModuleBinding(newEscrow).tokenManager() == address(this),
            "Escrow token manager mismatch"
        );

        ostEscrowAddress = newEscrow;
        tokenHoldersOST.remove(newEscrow);

        emit OSTEscrowAddressRotated(oldEscrow, newEscrow, block.timestamp);
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


    function transferIQSfromAtoB(
        address,
        address,
        uint256
    )
        external
        pure
        override
    {
        revert("IQS is non-transferable");
    }

    /// @notice Legacy treasury mint is disabled in AMF model.
    function mintIQS(
        uint256
    )
        external
        pure
        override
    {
        revert("Use mintIQSTo under BSA");
    }

    /// @notice Credits IQS/BSA rights directly to a whitelisted holder.
    /// @dev Called by BSA/distribution backend or future BSARegistry module.
    function mintIQSTo(
        address account,
        uint256 amount,
        bytes32 referenceHash
    )
        external
        override
        onlyTokenOperator
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
            referenceHash != bytes32(0),
            "Reference hash required"
        );

        accessControl.onlyValidSender(account);

        // IQS and OST share the SAME holder quota, with no double counting.
        _registerHolderSlot(account);

        _balancesIQS[account] +=
            amount;


        totalSupplyIQS +=
            amount;


        _syncIQSHolder(account);

        emit IQSAwarded(
            account,
            amount,
            referenceHash,
            block.timestamp
        );

        emit TransferIQS(
            address(0),
            account,
            amount
        );
    }

    /// @notice Burns IQS from holder during finalized IQS exercise into OST.
    function burnIQS(
        uint256 amount,
        address account
    )
        external
        override
        onlyTokenOperator
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


        _syncIQSHolder(account);

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
        return type(uint256).max;
    }

    /// @notice Mints OST, normally when IQS exercise is finalized.
    function mintOSTTo(
        address account,
        uint256 amount,
        bytes32 referenceHash
    )
        external
        override
        onlyTokenOperator
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
            referenceHash != bytes32(0),
            "Reference hash required"
        );

        accessControl.onlyValidSender(account);
        // An escrow address is a custodian, never a primary-issuance holder.
        require(account != ostEscrowAddress, "Cannot mint OST to escrow");
        _registerHolderSlot(account);

        _balancesOST[account] +=
            amount;

        totalSupplyOST +=
            amount;

        _syncOSTHolder(account);

        emit MintOST(
            account,
            amount,
            referenceHash,
            block.timestamp
        );

        emit TransferOST(
            address(0),
            account,
            amount
        );
    }

    /// @notice Controlled OST transfer. Users cannot call this directly unless they are an authorized token operator/admin.
    function transferOSTfromAtoB(
        address from,
        address to,
        uint256 amount
    )
        external
        override
        onlyTokenOperator
        whenNotPaused
        nonReentrant
    {
        _transferOST(
            from,
            to,
            amount
        );
    }

    function _transferOST(
        address from,
        address to,
        uint256 amount
    )
        internal
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

        // Fail closed: reporting and transferring OST without identifying the
        // custodial escrow would silently pollute the shareholder register.
        require(ostEscrowAddress != address(0), "OST escrow not configured");

        // Include SECONDARY recipients, or mint-only checks are bypassable.
        // Escrow itself consumes no holder slot; its seller retains the slot
        // even while all their OST is in custody, so reclaim cannot deadlock.
        if (to != ostEscrowAddress) {
            _registerHolderSlot(to);
        }

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
        require(ostEscrowAddress != address(0), "OST escrow not configured");

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

    // -------------------------------------------------------------------------
    // Wallet migration
    // -------------------------------------------------------------------------

    function adminMigrateWallet(
        address oldWallet,
        address newWallet,
        bytes32 referenceHash
    )
        external
        override
        onlyWalletMigrationController
        whenNotPaused
        nonReentrant
        returns (
            uint256 iqsAmount,
            uint256 ostAmount
        )
    {
        require(
            oldWallet != address(0),
            "Invalid old wallet"
        );

        require(
            newWallet != address(0),
            "Invalid new wallet"
        );

        require(
            oldWallet != newWallet,
            "Wallets must be different"
        );

        require(
            referenceHash != bytes32(0),
            "Invalid reference hash"
        );

        require(
            !usedWalletMigrationReferences[referenceHash],
            "Reference already used"
        );

        require(
            !tokenOperators[oldWallet] && !tokenOperators[newWallet] &&
                oldWallet != ostEscrowAddress && newWallet != ostEscrowAddress,
            "Cannot migrate token operator wallet"
        );

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
        require(!hasHolderSlot[newWallet], "New wallet already has holder slot");
        require(!retiredHolderWallet[newWallet], "New wallet was retired");
        require(hasHolderSlot[oldWallet], "Old wallet has no holder slot");
        require(ostEscrowAddress != address(0), "OST escrow not configured");
        require(
            IOSTEscrowModuleBinding(ostEscrowAddress).activeTransferCount(oldWallet) == 0 &&
            IOSTEscrowModuleBinding(ostEscrowAddress).activeTransferCount(newWallet) == 0,
            "Wallet has open OST transfers"
        );

        iqsAmount =
            _balancesIQS[oldWallet];

        ostAmount =
            _balancesOST[oldWallet];

        require(
            iqsAmount > 0 || ostAmount > 0,
            "No funds to migrate"
        );

        // Reassign the same beneficial-holder slot to the replacement wallet.
        // Never consume a 150th slot simply because a holder lost their key.
        hasHolderSlot[oldWallet] = false;
        hasHolderSlot[newWallet] = true;
        retiredHolderWallet[oldWallet] = true;
        emit HolderSlotMigrated(oldWallet, newWallet);

        usedWalletMigrationReferences[referenceHash] =
            true;

        if (!accessControl.isWhiteListed(newWallet)) {
            accessControl.addToWhiteList(newWallet);
        }

        if (!accessControl.isAuthorized(newWallet)) {
            accessControl.authorizeAddress(newWallet);
        }

        if (iqsAmount > 0) {
            _balancesIQS[oldWallet] =
                0;

            _balancesIQS[newWallet] =
                iqsAmount;


            _syncIQSHolder(oldWallet);
            _syncIQSHolder(newWallet);

            emit TransferIQS(
                oldWallet,
                newWallet,
                iqsAmount
            );
        }

        if (ostAmount > 0) {
            _balancesOST[oldWallet] =
                0;

            _balancesOST[newWallet] =
                ostAmount;

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

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------

    function _registerHolderSlot(address account) internal {
        require(account != address(0), "Invalid holder");
        require(!retiredHolderWallet[account], "Retired holder wallet");
        if (hasHolderSlot[account]) return;
        require(registeredHolderCount < MAX_REGISTERED_HOLDERS, "Holder cap reached");
        hasHolderSlot[account] = true;
        registeredHolderCount++;
        emit HolderSlotRegistered(account, registeredHolderCount);
    }

    function _syncIQSHolder(
        address account
    )
        internal
    {
        if (_balancesIQS[account] > 0) {
            tokenHoldersIQS.add(account);
        } else {
            tokenHoldersIQS.remove(account);
        }
    }

    function _syncOSTHolder(
        address account
    )
        internal
    {
        // Escrow is a custodial system account, never a registered shareholder.
        // Its actual token balance is intentionally retained in _balancesOST.
        if (account == ostEscrowAddress) {
            tokenHoldersOST.remove(account);
        } else if (_balancesOST[account] > 0) {
            tokenHoldersOST.add(account);
        } else {
            tokenHoldersOST.remove(account);
        }
    }
}
