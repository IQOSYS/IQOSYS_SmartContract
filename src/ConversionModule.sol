// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./IConversionModule.sol";
import "./IAccessControl.sol";
import "./ITokenManager.sol";
import "./IAdminMultisig.sol";
import "./IBSARegistry.sol";
/// @title IQS Exercise Module
/// @notice AMF production model: IQS can only be exercised into OST through a recorded BSA.
/// @dev No personal data must be stored on-chain. Only addresses, amounts, timestamps and hashes.
contract ConversionModule is
    IConversionModule,
    ReentrancyGuard,
    Pausable
{
    IAccessControl public accessControl;
    ITokenManager public tokenManager;
    IAdminMultisig public adminMultisig;
    IBSARegistry public bsaRegistry;
    uint256 private nextRequestId;
    mapping(uint256 => IQSExerciseRequest) private exerciseRequests;
    mapping(uint256 => uint256) public override pendingExerciseIQSForBSA;
    event ExerciseRequested(
        uint256 indexed requestId,
        uint256 indexed bsaId,
        address indexed requester,
        uint256 amount,
        uint256 strikePrice,
        uint256 capitalDue,
        bytes32 bsaReferenceHash,
        bytes32 referenceHash,
        uint256 timestamp
    );
    event ExerciseReservationUpdated(
        uint256 indexed bsaId,
        uint256 indexed requestId,
        uint256 amount,
        uint256 totalPendingForBSA,
        bool reserved,
        uint256 timestamp
    );
    event ExerciseStatusChanged(
        uint256 indexed requestId,
        ExerciseStatus status,
        uint256 timestamp
    );
    event ExerciseApproved(
        uint256 indexed requestId,
        address indexed admin,
        uint256 timestamp
    );
    event ExerciseRejected(
        uint256 indexed requestId,
        address indexed admin,
        bytes32 indexed reasonHash,
        uint256 timestamp
    );
    event ExerciseCancelled(
        uint256 indexed requestId,
        address indexed cancelledBy,
        uint256 timestamp
    );
    event CapitalReceivedConfirmed(
        uint256 indexed requestId,
        address indexed admin,
        bytes32 indexed capitalPaymentHash,
        uint256 timestamp
    );
    event ExerciseFinalized(
        uint256 indexed requestId,
        uint256 indexed bsaId,
        address indexed requester,
        uint256 iqsBurned,
        uint256 ostIssued,
        uint256 strikePrice,
        uint256 capitalDue,
        bytes32 receiptHash,
        uint256 timestamp
    );
    event ExerciseReceiptHashRecorded(
        uint256 indexed requestId,
        bytes32 indexed receiptHash,
        uint256 timestamp
    );
    event ConversionModulePaused(
        address indexed admin,
        uint256 timestamp
    );
    event ConversionModuleUnpaused(
        address indexed admin,
        uint256 timestamp
    );
    constructor(
        address _accessControl,
        address _tokenManager,
        address _adminMultisig,
        address _bsaRegistry
    ) {
        require(
            _accessControl != address(0),
            "Invalid access control"
        );
        require(
            _tokenManager != address(0),
            "Invalid token manager"
        );
        require(
            _adminMultisig != address(0),
            "Invalid admin multisig"
        );
        require(
            _bsaRegistry != address(0),
            "Invalid BSA registry"
        );
        accessControl = IAccessControl(_accessControl);
        tokenManager = ITokenManager(_tokenManager);
        adminMultisig = IAdminMultisig(_adminMultisig);
        bsaRegistry = IBSARegistry(_bsaRegistry);
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
    modifier requestExists(uint256 requestId) {
        require(
            exerciseRequests[requestId].requester != address(0),
            "Exercise request not found"
        );
        _;
    }
    function pause()
        external
        onlyAdminOrEmergency
    {
        _pause();
        emit ConversionModulePaused(
            msg.sender,
            block.timestamp
        );
    }
    function unpause()
        external
        onlyEmergency
    {
        _unpause();
        emit ConversionModuleUnpaused(
            msg.sender,
            block.timestamp
        );
    }
function requestExercise(
    uint256 bsaId,
    uint256 amount,
    bytes32 referenceHash
)
    external
    override
    whenNotPaused
    nonReentrant
    returns (uint256)
{
    require(amount > 0, "Amount must be greater than zero");
    require(referenceHash != bytes32(0), "Reference hash required");

    IBSARegistry.BSARecord memory bsa = bsaRegistry.bsasf(bsaId);

    require(bsa.holder != address(0), "BSA not found");
    require(block.timestamp < bsa.expiryDate, "BSA expired");
    require(
        bsa.status == IBSARegistry.BSAStatus.Active ||
            bsa.status == IBSARegistry.BSAStatus.Exhausted,
        "BSA cannot be exercised"
    );
    require(
        msg.sender == bsa.holder || accessControl.isAdmin(msg.sender),
        "Caller is not BSA holder or admin"
    );

    accessControl.onlyValidSender(bsa.holder);

    uint256 availableIQS = bsaRegistry.availableIQSToExercise(bsaId);

    require(amount <= availableIQS, "Insufficient unreserved BSA IQS");
    require(
        tokenManager.balanceOfIQS(bsa.holder) >= amount,
        "Insufficient IQS balance"
    );

    uint256 capitalDue = amount * bsa.strikePrice;
    uint256 requestId = nextRequestId++;

    pendingExerciseIQSForBSA[bsaId] += amount;

    exerciseRequests[requestId] = IQSExerciseRequest({
        id: requestId,
        bsaId: bsaId,
        requester: bsa.holder,
        amount: amount,
        strikePrice: bsa.strikePrice,
        capitalDue: capitalDue,
        bsaReferenceHash: bsa.bsaReferenceHash,
        referenceHash: referenceHash,
        capitalPaymentHash: bytes32(0),
        receiptHash: bytes32(0),
        rejectionReasonHash: bytes32(0),
        status: ExerciseStatus.Requested,
        requestedAt: block.timestamp,
        approvedAt: 0,
        capitalConfirmedAt: 0,
        settledAt: 0,
        rejectedAt: 0,
        cancelledAt: 0
    });

    emit ExerciseReservationUpdated(
        bsaId,
        requestId,
        amount,
        pendingExerciseIQSForBSA[bsaId],
        true,
        block.timestamp
    );

    emit ExerciseRequested(
        requestId,
        bsaId,
        bsa.holder,
        amount,
        bsa.strikePrice,
        capitalDue,
        bsa.bsaReferenceHash,
        referenceHash,
        block.timestamp
    );

    emit ExerciseStatusChanged(
        requestId,
        ExerciseStatus.Requested,
        block.timestamp
    );

    return requestId;
}
    function approveExercise(
        uint256 requestId
    )
        public
        override
        onlyAdmin
        requestExists(requestId)
        whenNotPaused
    {
        IQSExerciseRequest storage request =
            exerciseRequests[requestId];
        require(
            request.status == ExerciseStatus.Requested,
            "Invalid status"
        );
        request.status =
            ExerciseStatus.Approved;
        request.approvedAt =
            block.timestamp;
        emit ExerciseApproved(
            requestId,
            msg.sender,
            block.timestamp
        );
        emit ExerciseStatusChanged(
            requestId,
            ExerciseStatus.Approved,
            block.timestamp
        );
    }
    function getRejectCapitalReceivedExerciseActionHash(uint256 requestId, bytes32 reasonHash)
        public view override requestExists(requestId) returns (bytes32)
    {
        IQSExerciseRequest storage request = exerciseRequests[requestId];
        return keccak256(abi.encode(address(this), block.chainid, "REJECT_CAPITAL_RECEIVED_EXERCISE",
            requestId, request.bsaId, request.requester, request.amount,
            request.capitalDue, request.capitalPaymentHash, reasonHash));
    }

function rejectExercise(
    uint256 requestId,
    bytes32 reasonHash
)
    public
    override
    onlyAdmin
    requestExists(requestId)
    whenNotPaused
{
    require(reasonHash != bytes32(0), "Reason hash required");

    IQSExerciseRequest storage request = exerciseRequests[requestId];

    require(
        request.status == ExerciseStatus.Requested ||
            request.status == ExerciseStatus.Approved ||
            request.status == ExerciseStatus.CapitalReceived,
        "Invalid status"
    );

    if (request.status == ExerciseStatus.CapitalReceived) {
        adminMultisig.consumeApprovedAction(getRejectCapitalReceivedExerciseActionHash(requestId, reasonHash));
    }
    request.status = ExerciseStatus.Rejected;
    request.rejectionReasonHash = reasonHash;
    request.rejectedAt = block.timestamp;

    _releaseExerciseReservation(requestId, request);
    _syncExpiredBSAIfNeeded(request.bsaId);

    emit ExerciseRejected(requestId, msg.sender, reasonHash, block.timestamp);
    emit ExerciseStatusChanged(requestId, ExerciseStatus.Rejected, block.timestamp);
}
function cancelExercise(uint256 requestId)
    public
    override
    requestExists(requestId)
    whenNotPaused
{
    IQSExerciseRequest storage request = exerciseRequests[requestId];

    require(
        msg.sender == request.requester || accessControl.isAdmin(msg.sender),
        "Caller cannot cancel"
    );
    require(
        request.status == ExerciseStatus.Requested ||
            request.status == ExerciseStatus.Approved,
        "Invalid status"
    );

    request.status = ExerciseStatus.Cancelled;
    request.cancelledAt = block.timestamp;

    _releaseExerciseReservation(requestId, request);
    _syncExpiredBSAIfNeeded(request.bsaId);

    emit ExerciseCancelled(requestId, msg.sender, block.timestamp);
    emit ExerciseStatusChanged(requestId, ExerciseStatus.Cancelled, block.timestamp);
}
    function confirmCapitalReceived(
        uint256 requestId,
        bytes32 capitalPaymentHash
    )
        external
        override
        onlyAdmin
        requestExists(requestId)
        whenNotPaused
    {
        require(
            capitalPaymentHash != bytes32(0),
            "Capital payment hash required"
        );
        IQSExerciseRequest storage request =
            exerciseRequests[requestId];
        require(
            request.status == ExerciseStatus.Approved,
            "Invalid status"
        );
        request.status =
            ExerciseStatus.CapitalReceived;
        request.capitalPaymentHash =
            capitalPaymentHash;
        request.capitalConfirmedAt =
            block.timestamp;
        emit CapitalReceivedConfirmed(
            requestId,
            msg.sender,
            capitalPaymentHash,
            block.timestamp
        );
        emit ExerciseStatusChanged(
            requestId,
            ExerciseStatus.CapitalReceived,
            block.timestamp
        );
    }
    function getFinalizeExerciseActionHash(
        uint256 requestId,
        bytes32 receiptHash
    )
        public
        view
        override
        requestExists(requestId)
        returns (bytes32)
    {
        IQSExerciseRequest memory request =
            exerciseRequests[requestId];
        return keccak256(
            abi.encode(
                address(this),
                block.chainid,
                "FINALIZE_IQS_EXERCISE",
                requestId,
                request.bsaId,
                request.requester,
                request.amount,
                request.strikePrice,
                request.capitalDue,
                request.capitalPaymentHash,
                receiptHash
            )
        );
    }
function finalizeExercise(
    uint256 requestId,
    bytes32 receiptHash
)
    external
    override
    onlyAdmin
    requestExists(requestId)
    whenNotPaused
    nonReentrant
{
    require(receiptHash != bytes32(0), "Receipt hash required");

    IQSExerciseRequest storage request = exerciseRequests[requestId];

    require(
        request.status == ExerciseStatus.CapitalReceived,
        "Invalid status"
    );

    bytes32 actionHash = getFinalizeExerciseActionHash(
        requestId,
        receiptHash
    );

    adminMultisig.consumeApprovedAction(actionHash);

    bsaRegistry.recordIQSConverted(
        request.bsaId,
        request.amount,
        request.referenceHash
    );

    tokenManager.burnIQS(request.amount, request.requester);
    tokenManager.mintOSTTo(request.requester, request.amount, receiptHash);

    request.status = ExerciseStatus.Settled;
    request.receiptHash = receiptHash;
    request.settledAt = block.timestamp;

    _releaseExerciseReservation(requestId, request);
    _syncExpiredBSAIfNeeded(request.bsaId);

    emit ExerciseFinalized(
        requestId,
        request.bsaId,
        request.requester,
        request.amount,
        request.amount,
        request.strikePrice,
        request.capitalDue,
        receiptHash,
        block.timestamp
    );

    emit ExerciseStatusChanged(requestId, ExerciseStatus.Settled, block.timestamp);
}
    function recordExerciseReceiptHash(
        uint256 requestId,
        bytes32 receiptHash
    )
        public
        override
        onlyAdmin
        requestExists(requestId)
    {
        require(
            receiptHash != bytes32(0),
            "Receipt hash required"
        );
        IQSExerciseRequest storage request =
            exerciseRequests[requestId];
        require(
            request.status == ExerciseStatus.Settled,
            "Exercise not settled"
        );
        request.receiptHash =
            receiptHash;
        emit ExerciseReceiptHashRecorded(
            requestId,
            receiptHash,
            block.timestamp
        );
    }
function _releaseExerciseReservation(
        uint256 requestId,
        IQSExerciseRequest storage request
    ) internal {
        uint256 pending = pendingExerciseIQSForBSA[request.bsaId];

        require(pending >= request.amount, "Exercise reservation invariant");

        pendingExerciseIQSForBSA[request.bsaId] = pending - request.amount;

        emit ExerciseReservationUpdated(
            request.bsaId,
            requestId,
            request.amount,
            pendingExerciseIQSForBSA[request.bsaId],
            false,
            block.timestamp
        );
    }

    function _syncExpiredBSAIfNeeded(uint256 bsaId) internal {
        IBSARegistry.BSARecord memory bsa = bsaRegistry.bsasf(bsaId);

        if (bsa.holder != address(0) && block.timestamp >= bsa.expiryDate) {
            bsaRegistry.syncBSAStatus(bsaId);
        }
    }
    function getExerciseRequest(
        uint256 requestId
    )
        external
        view
        override
        returns (IQSExerciseRequest memory)
    {
        return exerciseRequests[requestId];
    }
    function exerciseRequestCount()
        external
        view
        override
        returns (uint256)
    {
        return nextRequestId;
    }
    // -------------------------------------------------------------------------
    // Legacy compatibility wrappers
    // -------------------------------------------------------------------------
    function adminCreateIQSToOSTConversionRequest(
        address,
        uint256,
        bytes32
    )
        external
        pure
        override
        returns (uint256)
    {
        revert(
            "Use BSA-based exercise"
        );
    }
    function approveIQSToOSTConversion(
        uint256 requestId
    )
        external
        override
    {
        approveExercise(
            requestId
        );
    }
    function rejectIQSToOSTConversion(
        uint256 requestId
    )
        external
        override
    {
        rejectExercise(
            requestId,
            keccak256("legacy-reject")
        );
    }
    function adminCancelIQSToOSTConversion(
        uint256 requestId
    )
        external
        override
    {
        cancelExercise(
            requestId
        );
    }
    function adminRecordIQSToOSTConversionReceiptHash(
        uint256 requestId,
        bytes32 receiptHash
    )
        external
        override
    {
        recordExerciseReceiptHash(
            requestId,
            receiptHash
        );
    }
    function getIQSToOSTConversion(
        uint256 requestId
    )
        external
        view
        override
        returns (IQSExerciseRequest memory)
    {
        return exerciseRequests[requestId];
    }
    /*
     * Old raw exercise API intentionally disabled:
     * strike price and BSA reference must come from BSARegistry.
     */
    function requestExercise(
        address,
        uint256,
        uint256,
        bytes32,
        bytes32
    )
        external
        pure
        returns (uint256)
    {
        revert(
            "Use BSA-based exercise"
        );
    }
}
