// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./IBSARegistry.sol";
import "./IAdminMultisig.sol";
import "./IAccessControl.sol";
import "./ITokenManager.sol";
import "./IConversionModule.sol";
/// @title BSA Registry
/// @notice AMF production model: records BSA terms, immutable strike price, maximum IQS, and controls IQS awards under each BSA.
/// @dev Only hashes/references are stored. Do not store names, emails, IBANs, company names, PDF contents or any personal data on-chain.
contract BSARegistry is
    IBSARegistry,
    ReentrancyGuard,
    Pausable
{
    IAccessControl public accessControl;
    ITokenManager public tokenManager;
    IAdminMultisig public adminMultisig;
    uint256 private nextBSAId;
    mapping(uint256 => BSARecord) private bsas;
    mapping(address => uint256) public override activeBSAOf;
    mapping(address => uint256[]) private holderBSAIds;
    mapping(uint256 => uint256) public override expiredIQSBurnedOf;
    address public override holderMigrationController;
    address public conversionModule;
    event BSARecorded(
        uint256 indexed bsaId,
        address indexed holder,
        bytes32 indexed bsaReferenceHash,
        bytes32 termsHash,
        uint256 strikePrice,
        uint256 maxIQS,
        uint256 expiryDate,
        uint256 premiumPaid,
        uint256 timestamp
    );
    event IQSCreditedUnderBSA(
        uint256 indexed bsaId,
        address indexed holder,
        uint256 amount,
        uint256 totalAwarded,
        bytes32 indexed awardReferenceHash,
        uint256 timestamp
    );
    event IQSConvertedUnderBSA(
        uint256 indexed bsaId,
        address indexed holder,
        uint256 amount,
        uint256 totalConverted,
        bytes32 indexed conversionReferenceHash,
        uint256 timestamp
    );
    event BSAStatusUpdated(
        uint256 indexed bsaId,
        BSAStatus status,
        uint256 timestamp
    );
    event BSACancelled(
        uint256 indexed bsaId,
        address indexed holder,
        bytes32 indexed reasonHash,
        uint256 timestamp
    );
    /// @notice Tracks how many unexercised IQS were burned upon cancellation.
    /// @dev Historical awardedIQS and convertedIQS remain unchanged in the BSA record.
    event UnexercisedIQSBurnedOnCancellation(
        uint256 indexed bsaId,
        address indexed holder,
        uint256 amount,
        bytes32 indexed reasonHash,
        uint256 timestamp
    );
    event UnexercisedIQSBurnedOnExpiry(
        uint256 indexed bsaId,
        address indexed holder,
        uint256 amount,
        uint256 totalExpiredBurned,
        uint256 timestamp
    );
    event ConversionModuleUpdated(
        address indexed conversionModule,
        uint256 timestamp
    );
    event BSARegistryPaused(
        address indexed admin,
        uint256 timestamp
    );
    event BSARegistryUnpaused(
        address indexed admin,
        uint256 timestamp
    );
    constructor(
        address _accessControl,
        address _tokenManager,
        address _adminMultisig
    ) {
        require(
            _accessControl != address(0),
            "Invalid access control"
        );
        require(
            _tokenManager != address(0),
            "Invalid token manager"
        );
        require(_adminMultisig != address(0), "Invalid admin multisig");
        adminMultisig = IAdminMultisig(_adminMultisig);
        accessControl = IAccessControl(_accessControl);
        tokenManager = ITokenManager(_tokenManager);
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
    modifier onlyConversionModule() {
        require(
            msg.sender == conversionModule,
            "Caller is not conversion module"
        );
        _;
    }
    modifier onlyHolderMigrationController() {
        require(msg.sender == holderMigrationController, "Caller is not holder migration controller");
        _;
    }
    modifier bsaExists(uint256 bsaId) {
        require(
            bsas[bsaId].holder != address(0),
            "BSA not found"
        );
        _;
    }
    function pause() external onlyAdminOrEmergency {
        _pause();
        emit BSARegistryPaused(
            msg.sender,
            block.timestamp
        );
    }
    function unpause() external onlyEmergency {
        _unpause();
        emit BSARegistryUnpaused(
            msg.sender,
            block.timestamp
        );
    }
function setConversionModule(address _conversionModule)
    external
    override
    onlyAdmin
{
    require(_conversionModule != address(0), "Invalid conversion module");
    require(conversionModule == address(0), "Conversion module already set");
    require(_conversionModule.code.length > 0, "Conversion module must be contract");

    conversionModule = _conversionModule;
    emit ConversionModuleUpdated(_conversionModule, block.timestamp);
}
    function setHolderMigrationController(address _holderMigrationController) external override onlyAdmin {
        require(_holderMigrationController != address(0), "Invalid holder migration controller");
        require(holderMigrationController == address(0), "Holder migration controller already set");
        holderMigrationController = _holderMigrationController;
        emit HolderMigrationControllerUpdated(_holderMigrationController, block.timestamp);
    }
    function getRecordBSAActionHash(
        address holder,
        bytes32 bsaReferenceHash,
        bytes32 termsHash,
        uint256 strikePrice,
        uint256 maxIQS,
        uint256 expiryDate,
        uint256 premiumPaid
    )
        public
        view
        override
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                address(this),
                block.chainid,
                "RECORD_BSA",
                holder,
                bsaReferenceHash,
                termsHash,
                strikePrice,
                maxIQS,
                expiryDate,
                premiumPaid
            )
        );
    }
    event HolderMigrationControllerUpdated(address indexed controller, uint256 timestamp);
    event BSAHolderMigrated(
        uint256 indexed bsaId,
        address indexed oldWallet,
        address indexed newWallet,
        uint256 timestamp
    );
    function recordBSA(
        address holder,
        bytes32 bsaReferenceHash,
        bytes32 termsHash,
        uint256 strikePrice,
        uint256 maxIQS,
        uint256 expiryDate,
        uint256 premiumPaid
    )
        external
        override
        onlyAdmin
        whenNotPaused
        nonReentrant
        returns (uint256)
    {
        require(holder != address(0), "Invalid holder");
        require(
            bsaReferenceHash != bytes32(0),
            "BSA reference hash required"
        );
        require(
            termsHash != bytes32(0),
            "Terms hash required"
        );
        require(
            strikePrice > 0,
            "Strike price required"
        );
        require(
            maxIQS > 0,
            "Max IQS required"
        );
        require(
            expiryDate > block.timestamp,
            "Invalid expiry date"
        );
        accessControl.onlyValidSender(holder);
        uint256 currentActiveId = activeBSAOf[holder];
        if (currentActiveId != 0) {
            _syncBSAStatus(currentActiveId);
            require(
                bsas[currentActiveId].status != BSAStatus.Active,
                "Holder already has active BSA"
            );
        }
        adminMultisig.consumeApprovedAction(getRecordBSAActionHash(
            holder, bsaReferenceHash, termsHash, strikePrice, maxIQS, expiryDate, premiumPaid
        ));
        uint256 bsaId = ++nextBSAId;
        bsas[bsaId] = BSARecord({
            id: bsaId,
            holder: holder,
            bsaReferenceHash: bsaReferenceHash,
            termsHash: termsHash,
            strikePrice: strikePrice,
            maxIQS: maxIQS,
            awardedIQS: 0,
            convertedIQS: 0,
            premiumPaid: premiumPaid,
            expiryDate: expiryDate,
            createdAt: block.timestamp,
            status: BSAStatus.Active
        });
        activeBSAOf[holder] = bsaId;
        holderBSAIds[holder].push(bsaId);
        emit BSARecorded(
            bsaId,
            holder,
            bsaReferenceHash,
            termsHash,
            strikePrice,
            maxIQS,
            expiryDate,
            premiumPaid,
            block.timestamp
        );
        emit BSAStatusUpdated(
            bsaId,
            BSAStatus.Active,
            block.timestamp
        );
        return bsaId;
    }
    function getCreditIQSActionHash(uint256 bsaId, uint256 amount, bytes32 awardReferenceHash)
        public view override bsaExists(bsaId) returns (bytes32)
    {
        BSARecord storage bsa = bsas[bsaId];
        return keccak256(abi.encode(
            address(this), block.chainid, "CREDIT_IQS", bsaId,
            bsa.holder, bsa.bsaReferenceHash, bsa.termsHash, amount, awardReferenceHash
        ));
    }
    function creditIQS(
        uint256 bsaId,
        uint256 amount,
        bytes32 awardReferenceHash
    )
        external
        override
        onlyAdmin
        bsaExists(bsaId)
        whenNotPaused
        nonReentrant
    {
        require(
            amount > 0,
            "Amount must be greater than zero"
        );
        require(
            awardReferenceHash != bytes32(0),
            "Award reference hash required"
        );
        _syncBSAStatus(bsaId);
        BSARecord storage bsa = bsas[bsaId];
        require(
            bsa.status == BSAStatus.Active,
            "BSA is not active"
        );
        require(
            bsa.awardedIQS + amount <= bsa.maxIQS,
            "BSA max IQS exceeded"
        );
        adminMultisig.consumeApprovedAction(getCreditIQSActionHash(bsaId, amount, awardReferenceHash));
        bsa.awardedIQS += amount;
        tokenManager.mintIQSTo(
            bsa.holder,
            amount,
            awardReferenceHash
        );
        emit IQSCreditedUnderBSA(
            bsaId,
            bsa.holder,
            amount,
            bsa.awardedIQS,
            awardReferenceHash,
            block.timestamp
        );
        if (bsa.awardedIQS == bsa.maxIQS) {
            bsa.status = BSAStatus.Exhausted;
            if (activeBSAOf[bsa.holder] == bsaId) {
                activeBSAOf[bsa.holder] = 0;
            }
            emit BSAStatusUpdated(
                bsaId,
                BSAStatus.Exhausted,
                block.timestamp
            );
        }
    }
    function recordIQSConverted(
        uint256 bsaId,
        uint256 amount,
        bytes32 conversionReferenceHash
    )
        external
        override
        onlyConversionModule
        bsaExists(bsaId)
        whenNotPaused
    {
        require(
            amount > 0,
            "Amount must be greater than zero"
        );
        require(
            conversionReferenceHash != bytes32(0),
            "Conversion reference hash required"
        );
        BSARecord storage bsa = bsas[bsaId];
        // An Expired BSA may settle ONLY through the designated ConversionModule.
        // ConversionModule creates requests before expiry, checks the BSA holder,
        // and passes that already-recorded request through multisig finalization.
        // This preserves settlement of rights exercised before the cutoff.
        require(
            bsa.status == BSAStatus.Active ||
                bsa.status == BSAStatus.Exhausted ||
                bsa.status == BSAStatus.Expired,
            "BSA cannot be converted"
        );
        require(
            bsa.convertedIQS + amount <= bsa.awardedIQS,
            "Insufficient BSA IQS"
        );
        bsa.convertedIQS += amount;
        emit IQSConvertedUnderBSA(
            bsaId,
            bsa.holder,
            amount,
            bsa.convertedIQS,
            conversionReferenceHash,
            block.timestamp
        );
    }
    /// @notice Cancels an active BSA and burns its remaining unexercised IQS atomically.
    /// @dev The historical award/conversion counters are preserved for auditability.
function cancelBSA(uint256 bsaId, bytes32 reasonHash)
    external
    override
    onlyAdmin
    bsaExists(bsaId)
    whenNotPaused
    nonReentrant
{
    require(reasonHash != bytes32(0), "Reason hash required");

    BSARecord storage bsa = bsas[bsaId];

    require(
        bsa.status == BSAStatus.Active || bsa.status == BSAStatus.Exhausted,
        "BSA cannot be cancelled"
    );
    require(block.timestamp < bsa.expiryDate, "BSA expired");
    require(_pendingExerciseIQS(bsaId) == 0, "BSA has pending exercise");

    uint256 unexercisedIQS = bsa.awardedIQS - bsa.convertedIQS;

    bsa.status = BSAStatus.Cancelled;

    if (activeBSAOf[bsa.holder] == bsaId) {
        activeBSAOf[bsa.holder] = 0;
    }

    if (unexercisedIQS > 0) {
        tokenManager.burnIQS(unexercisedIQS, bsa.holder);

        emit UnexercisedIQSBurnedOnCancellation(
            bsaId,
            bsa.holder,
            unexercisedIQS,
            reasonHash,
            block.timestamp
        );
    }

    emit BSACancelled(bsaId, bsa.holder, reasonHash, block.timestamp);
    emit BSAStatusUpdated(bsaId, BSAStatus.Cancelled, block.timestamp);
}
function syncBSAStatus(uint256 bsaId)
    external
    override
    bsaExists(bsaId)
    nonReentrant
{
    _syncBSAStatus(bsaId);
}
function _syncBSAStatus(uint256 bsaId) internal {
    BSARecord storage bsa = bsas[bsaId];

    if (
        block.timestamp >= bsa.expiryDate &&
        (bsa.status == BSAStatus.Active || bsa.status == BSAStatus.Exhausted)
    ) {
        bsa.status = BSAStatus.Expired;

        if (activeBSAOf[bsa.holder] == bsaId) {
            activeBSAOf[bsa.holder] = 0;
        }

        emit BSAStatusUpdated(bsaId, BSAStatus.Expired, block.timestamp);
    }

    if (bsa.status == BSAStatus.Expired) {
        _burnExpiredUnreservedIQS(bsaId, bsa);
    }
}
    function bsasf(
        uint256 bsaId
    )
        external
        view
        override
        returns (BSARecord memory)
    {
        return bsas[bsaId];
    }
    function bsaCount()
        external
        view
        override
        returns (uint256)
    {
        return nextBSAId;
    }
    function remainingIQSToAward(
        uint256 bsaId
    )
        public
        view
        override
        bsaExists(bsaId)
        returns (uint256)
    {
        BSARecord memory bsa = bsas[bsaId];
        if (
            bsa.status != BSAStatus.Active ||
            block.timestamp >= bsa.expiryDate ||
            bsa.awardedIQS >= bsa.maxIQS
        ) {
            return 0;
        }
        return bsa.maxIQS - bsa.awardedIQS;
    }
function availableIQSToExercise(uint256 bsaId)
    external
    view
    override
    bsaExists(bsaId)
    returns (uint256)
{
    BSARecord memory bsa = bsas[bsaId];

    if (
        bsa.status == BSAStatus.Cancelled ||
        bsa.status == BSAStatus.Expired ||
        block.timestamp >= bsa.expiryDate ||
        bsa.awardedIQS <= bsa.convertedIQS
    ) {
        return 0;
    }

    uint256 grossAvailable = bsa.awardedIQS - bsa.convertedIQS;
    uint256 pending = _pendingExerciseIQS(bsaId);

    if (pending >= grossAvailable) {
        return 0;
    }

    return grossAvailable - pending;
}
function _pendingExerciseIQS(uint256 bsaId) internal view returns (uint256) {
        if (conversionModule == address(0)) {
            return 0;
        }

        return IConversionModule(conversionModule).pendingExerciseIQSForBSA(bsaId);
    }

    function _burnExpiredUnreservedIQS(
        uint256 bsaId,
        BSARecord storage bsa
    ) internal {
        uint256 pending = _pendingExerciseIQS(bsaId);
        uint256 alreadyExpiredBurned = expiredIQSBurnedOf[bsaId];

        require(
            bsa.convertedIQS + pending + alreadyExpiredBurned <= bsa.awardedIQS,
            "BSA accounting invariant"
        );

        uint256 burnable =
            bsa.awardedIQS -
            bsa.convertedIQS -
            pending -
            alreadyExpiredBurned;

        if (burnable == 0) {
            return;
        }

        expiredIQSBurnedOf[bsaId] = alreadyExpiredBurned + burnable;
        tokenManager.burnIQS(burnable, bsa.holder);

        emit UnexercisedIQSBurnedOnExpiry(
            bsaId,
            bsa.holder,
            burnable,
            expiredIQSBurnedOf[bsaId],
            block.timestamp
        );
    }
function migrateHolderBSA(address oldWallet, address newWallet)
    external
    override
    onlyHolderMigrationController
    whenNotPaused
    returns (uint256 migratedCount)
{
    require(oldWallet != address(0), "Invalid old wallet");
    require(newWallet != address(0), "Invalid new wallet");
    require(oldWallet != newWallet, "Wallets must differ");
    require(holderBSAIds[newWallet].length == 0, "New wallet already has BSA history");

    uint256[] storage oldBSAIds = holderBSAIds[oldWallet];
    uint256 count = oldBSAIds.length;

    for (uint256 i = 0; i < count; i++) {
        require(
            _pendingExerciseIQS(oldBSAIds[i]) == 0,
            "BSA has pending exercise"
        );
    }

    for (uint256 i = 0; i < count; i++) {
        uint256 bsaId = oldBSAIds[i];
        BSARecord storage bsa = bsas[bsaId];

        require(bsa.holder == oldWallet, "BSA holder mismatch");

        bsa.holder = newWallet;
        holderBSAIds[newWallet].push(bsaId);

        emit BSAHolderMigrated(bsaId, oldWallet, newWallet, block.timestamp);
        migratedCount++;
    }

    uint256 activeId = activeBSAOf[oldWallet];

    if (activeId != 0) {
        activeBSAOf[newWallet] = activeId;
        activeBSAOf[oldWallet] = 0;
    }

    delete holderBSAIds[oldWallet];
    return migratedCount;
}
    function getBSAIdsOf(address holder) external view override returns (uint256[] memory) {
        return holderBSAIds[holder];
    }
}
