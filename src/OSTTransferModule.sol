// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

import "./IOSTTransferModule.sol";
import "./IAccessControl.sol";
import "./ITokenManager.sol";
import "./IAdminMultisig.sol";

/// @title OST Transfer Module
/// @notice AMF production model: whitelisted P2P OST transfers with registrar/admin validation and no IQS transfer logic.
contract OSTTransferModule is
    IOSTTransferModule,
    ReentrancyGuard,
    Pausable
{
    uint256 public constant override ESCROW_TIMEOUT = 7 days;

    IAccessControl public accessControl;
    ITokenManager public tokenManager;
    IAdminMultisig public adminMultisig;

    address public immutable override escrowAddress;

    uint256 private nextTransferId;


    mapping(uint256 => OSTTransfer) private transfers;
    mapping(address => uint256) public override activeTransferCount;
    uint256 public override openTransferCount;
    uint256 public constant override PAYMENT_VALIDATION_TIMEOUT = 7 days;
    mapping(uint256 => uint256) public override paymentValidationDeadline;


    event OSTTransferRequested(
        uint256 indexed id,
        TransferType indexed transferType,
        address indexed proposer,
        address seller,
        address buyer,
        uint256 amount,
        uint256 pricePerOST,
        bytes32 referenceHash,
        uint256 timestamp
    );

    event OSTTransferCountered(
        uint256 indexed id,
        address indexed counterparty,
        uint256 amount,
        uint256 pricePerOST,
        bytes32 indexed counterOfferHash,
        uint256 timestamp
    );

    event OSTTransferEscrowed(
        uint256 indexed id,
        address indexed seller,
        address indexed buyer,
        uint256 amount,
        uint256 pricePerOST,
        bytes32 agreementHash,
        uint256 timestamp
    );

    event BuyerPaymentProofRegistered(
        uint256 indexed id,
        address indexed buyer,
        bytes32 indexed paymentProofHash,
        uint256 timestamp
    );

    event SellerPaymentReceiptValidated(
        uint256 indexed id,
        address indexed seller,
        bytes32 indexed sellerReceiptHash,
        uint256 timestamp
    );

    event OSTTransferDisputed(
        uint256 indexed id,
        address indexed raisedBy,
        bytes32 indexed disputeHash,
        uint256 timestamp
    );

    event OSTTransferReleased(
        uint256 indexed id,
        address indexed seller,
        address indexed buyer,
        uint256 amount,
        bytes32 receiptHash,
        uint256 timestamp
    );

    event OSTTransferReturned(
        uint256 indexed id,
        address indexed seller,
        address indexed buyer,
        uint256 amount,
        bytes32 resolutionHash,
        bytes32 receiptHash,
        uint256 timestamp
    );

    event ExpiredEscrowReclaimed(
        uint256 indexed id,
        address indexed seller,
        address indexed triggeredBy,
        uint256 amount,
        uint256 escrowDeadline,
        uint256 timestamp
    );

    event OSTTransferCancelled(
        uint256 indexed id,
        address indexed cancelledBy,
        uint256 timestamp
    );

    event OSTTransferRejected(
        uint256 indexed id,
        address indexed rejectedBy,
        bytes32 indexed reasonHash,
        uint256 timestamp
    );

    event OSTTransferReceiptHashRecorded(
        uint256 indexed id,
        bytes32 indexed receiptHash,
        uint256 timestamp
    );

    event OSTTransfersPaused(
        address indexed admin,
        uint256 timestamp
    );

    event OSTTransfersUnpaused(
        address indexed admin,
        uint256 timestamp
    );

    constructor(address _accessControl, address _tokenManager, address _adminMultisig) {
        require(_accessControl != address(0), "Invalid access control");
        require(_tokenManager != address(0), "Invalid token manager");
        require(_adminMultisig != address(0), "Invalid admin multisig");

        accessControl = IAccessControl(_accessControl);
        tokenManager = ITokenManager(_tokenManager);
        adminMultisig = IAdminMultisig(_adminMultisig);
        escrowAddress = address(this);
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
    modifier transferExists(
        uint256 id
    ) {
        require(
            transfers[id].seller != address(0),
            "Transfer not found"
        );
        _;
    }

    modifier onlyParticipant(
        uint256 id
    ) {
        require(
            msg.sender == transfers[id].seller ||
                msg.sender == transfers[id].buyer,
            "Caller is not a transfer participant"
        );
        _;
    }

    // -------------------------------------------------------------------------
    // Pause
    // -------------------------------------------------------------------------

    function pause()
        external
        onlyAdminOrEmergency
    {
        _pause();

        emit OSTTransfersPaused(
            msg.sender,
            block.timestamp
        );
    }

    function unpause()
        external
        onlyEmergency
    {
        _unpause();

        emit OSTTransfersUnpaused(
            msg.sender,
            block.timestamp
        );
    }

    // -------------------------------------------------------------------------
    // Request creation
    // -------------------------------------------------------------------------

    function createSellTransferRequest(
        address seller,
        address buyer,
        uint256 amount,
        uint256 pricePerOST,
        bytes32 referenceHash
    )
        external
        override
        whenNotPaused
        nonReentrant
        returns (uint256)
    {
        require(
            msg.sender == seller || accessControl.isAdmin(msg.sender),
            "Only seller or admin can create"
        );
        if (msg.sender != seller) {
            adminMultisig.consumeApprovedAction(getAdminCreateTransferRequestActionHash(
                TransferType.SellRequest, seller, buyer, amount, pricePerOST, referenceHash
            ));
        }

        return _createTransferRequest(
            TransferType.SellRequest,
            seller,
            buyer,
            amount,
            pricePerOST,
            referenceHash,
            seller
        );
    }

    function createBuyTransferRequest(
        address buyer,
        address seller,
        uint256 amount,
        uint256 pricePerOST,
        bytes32 referenceHash
    )
        external
        override
        whenNotPaused
        nonReentrant
        returns (uint256)
    {
        require(
            msg.sender == buyer || accessControl.isAdmin(msg.sender),
            "Only buyer or admin can create"
        );
        if (msg.sender != buyer) {
            adminMultisig.consumeApprovedAction(getAdminCreateTransferRequestActionHash(
                TransferType.BuyRequest, seller, buyer, amount, pricePerOST, referenceHash
            ));
        }

        return _createTransferRequest(
            TransferType.BuyRequest,
            seller,
            buyer,
            amount,
            pricePerOST,
            referenceHash,
            buyer
        );
    }
    function getAdminCreateTransferRequestActionHash(
        TransferType transferType, address seller, address buyer,
        uint256 amount, uint256 pricePerOST, bytes32 referenceHash
    ) public view override returns (bytes32) {
        require(transferType == TransferType.SellRequest || transferType == TransferType.BuyRequest, "Invalid transfer type");
        return keccak256(abi.encode(address(this), block.chainid, "ADMIN_CREATE_OST_REQUEST",
            transferType, seller, buyer, amount, pricePerOST, referenceHash));
    }

    function getAdminValidateSellerPaymentActionHash(uint256 id, bytes32 sellerReceiptHash)
        public view override transferExists(id) returns (bytes32)
    {
        OSTTransfer storage transfer = transfers[id];
        return keccak256(abi.encode(address(this), block.chainid, "ADMIN_VALIDATE_SELLER_PAYMENT",
            id, transfer.seller, transfer.buyer, transfer.amount, transfer.agreementHash,
            transfer.paymentProofHash, sellerReceiptHash));
    }

    function getAdminConfirmOSTTransactionActionHash(uint256 id, bytes32 receiptHash)
        public view override transferExists(id) returns (bytes32)
    {
        OSTTransfer storage transfer = transfers[id];
        return keccak256(abi.encode(address(this), block.chainid, "ADMIN_CONFIRM_OST_TRANSACTION",
            id, transfer.seller, transfer.buyer, transfer.amount, transfer.agreementHash,
            transfer.paymentProofHash, transfer.sellerReceiptHash, receiptHash));
    }

    function getAdminConfirmSellerPaymentAndReleaseActionHash(
        uint256 id, bytes32 sellerReceiptHash, bytes32 receiptHash
    ) public view override transferExists(id) returns (bytes32) {
        OSTTransfer storage transfer = transfers[id];
        return keccak256(abi.encode(address(this), block.chainid, "ADMIN_CONFIRM_SELLER_PAYMENT_AND_RELEASE",
            id, transfer.seller, transfer.buyer, transfer.amount, transfer.pricePerOST,
            transfer.referenceHash, transfer.agreementHash, transfer.paymentProofHash,
            sellerReceiptHash, receiptHash));
    }

    function _setTransferStatus(OSTTransfer storage transfer, TransferStatus status) internal {
        if (status == TransferStatus.Released || status == TransferStatus.Returned ||
            status == TransferStatus.Cancelled || status == TransferStatus.Rejected) {
            activeTransferCount[transfer.seller]--;
            activeTransferCount[transfer.buyer]--;
            openTransferCount--;
        }
        transfer.status = status;
    }

function getAdminCreateAgreedSellTransferActionHash(
    address seller,
    address buyer,
    uint256 amount,
    uint256 pricePerOST,
    bytes32 referenceHash,
    bytes32 agreementHash
) public view override returns (bytes32) {
    return keccak256(
        abi.encode(
            address(this),
            block.chainid,
            "ADMIN_CREATE_AGREED_SELL_TRANSFER_AND_LOCK_ESCROW",
            seller,
            buyer,
            amount,
            pricePerOST,
            referenceHash,
            agreementHash
        )
    );
}

function adminCreateAgreedSellTransferAndLockEscrow(
    address seller,
    address buyer,
    uint256 amount,
    uint256 pricePerOST,
    bytes32 referenceHash,
    bytes32 agreementHash
) external override onlyAdmin whenNotPaused nonReentrant returns (uint256) {
    require(agreementHash != bytes32(0), "Agreement hash required");

    bytes32 actionHash = getAdminCreateAgreedSellTransferActionHash(
        seller,
        buyer,
        amount,
        pricePerOST,
        referenceHash,
        agreementHash
    );

    adminMultisig.consumeApprovedAction(actionHash);

    uint256 id = _createTransferRequest(
        TransferType.SellRequest,
        seller,
        buyer,
        amount,
        pricePerOST,
        referenceHash,
        seller
    );

    OSTTransfer storage transfer = transfers[id];
    _lockEscrowAfterAgreement(id, transfer, agreementHash, msg.sender);

    return id;
}

function getAdminAcceptTransferAndLockEscrowActionHash(
    uint256 id,
    bytes32 agreementHash
) public view override transferExists(id) returns (bytes32) {
    OSTTransfer storage transfer = transfers[id];

    return keccak256(
        abi.encode(
            address(this),
            block.chainid,
            "ADMIN_ACCEPT_TRANSFER_AND_LOCK_ESCROW",
            id,
            transfer.seller,
            transfer.buyer,
            transfer.amount,
            transfer.pricePerOST,
            transfer.referenceHash,
            transfer.counterOfferHash,
            agreementHash
        )
    );
}

function adminAcceptTransferAndLockEscrow(
    uint256 id,
    bytes32 agreementHash
) external override onlyAdmin transferExists(id) whenNotPaused nonReentrant {
    require(agreementHash != bytes32(0), "Agreement hash required");

    bytes32 actionHash = getAdminAcceptTransferAndLockEscrowActionHash(id, agreementHash);
    adminMultisig.consumeApprovedAction(actionHash);

    OSTTransfer storage transfer = transfers[id];
    _lockEscrowAfterAgreement(id, transfer, agreementHash, msg.sender);
}

function adminRejectTransfer(
    uint256 id,
    bytes32 reasonHash
)
    external
    override
    onlyAdmin
    transferExists(id)
    whenNotPaused
{
    OSTTransfer storage transfer =
        transfers[id];

    require(
        transfer.status == TransferStatus.Requested ||
            transfer.status == TransferStatus.Countered,
        "Transfer cannot be rejected"
    );

    require(
        reasonHash != bytes32(0),
        "Reason hash required"
    );

    transfer.resolutionHash =
        reasonHash;

    transfer.lastActionBy =
        msg.sender;

    transfer.updatedAt =
        block.timestamp;

    transfer.completedAt =
        block.timestamp;

    _setTransferStatus(transfer, TransferStatus.Rejected);

    emit OSTTransferRejected(
        id,
        msg.sender,
        reasonHash,
        block.timestamp
    );
}

function adminRegisterBuyerPaymentProof(
    uint256 id,
    bytes32 paymentProofHash
)
    external
    override
    onlyAdmin
    transferExists(id)
    whenNotPaused
{
    OSTTransfer storage transfer =
        transfers[id];

    require(
        transfer.status == TransferStatus.Escrowed,
        "Transfer is not escrowed"
    );

    require(
        paymentProofHash != bytes32(0),
        "Payment proof hash required"
    );

    transfer.paymentProofHash =
        paymentProofHash;

    transfer.lastActionBy =
        msg.sender;

    transfer.updatedAt =
        block.timestamp;

    _setTransferStatus(transfer, TransferStatus.PaymentProofRegistered);
        paymentValidationDeadline[id] = block.timestamp + PAYMENT_VALIDATION_TIMEOUT;

    emit BuyerPaymentProofRegistered(
        id,
        transfer.buyer,
        paymentProofHash,
        block.timestamp
    );
}

function adminValidateSellerPaymentReceipt(
    uint256 id,
    bytes32 sellerReceiptHash
)
    external
    override
    onlyAdmin
    transferExists(id)
    whenNotPaused
{
    OSTTransfer storage transfer =
        transfers[id];

    require(
        transfer.status == TransferStatus.PaymentProofRegistered,
        "Payment proof not registered"
    );

    require(
        sellerReceiptHash != bytes32(0),
        "Seller receipt hash required"
    );

    adminMultisig.consumeApprovedAction(getAdminValidateSellerPaymentActionHash(id, sellerReceiptHash));

    transfer.sellerReceiptHash =
        sellerReceiptHash;

    transfer.lastActionBy =
        msg.sender;

    transfer.updatedAt =
        block.timestamp;

    _setTransferStatus(transfer, TransferStatus.SellerValidatedPayment);

    emit SellerPaymentReceiptValidated(
        id,
        transfer.seller,
        sellerReceiptHash,
        block.timestamp
    );
}

function getAdminMarkTransferDisputedActionHash(uint256 id, bytes32 disputeHash)
    public view override transferExists(id) returns (bytes32)
{
    OSTTransfer storage transfer = transfers[id];
    return keccak256(abi.encode(address(this), block.chainid, "ADMIN_MARK_OST_TRANSFER_DISPUTED",
        id, transfer.seller, transfer.buyer, transfer.amount, transfer.referenceHash, disputeHash));
}
function adminMarkTransferDisputed(
    uint256 id,
    bytes32 disputeHash
)
    external
    override
    onlyAdmin
    transferExists(id)
    whenNotPaused
{
    OSTTransfer storage transfer =
        transfers[id];

    require(
        transfer.status == TransferStatus.Escrowed ||
            transfer.status == TransferStatus.PaymentProofRegistered ||
            transfer.status == TransferStatus.SellerValidatedPayment,
        "Transfer cannot be disputed"
    );

    require(
        disputeHash != bytes32(0),
        "Dispute hash required"
    );

    adminMultisig.consumeApprovedAction(getAdminMarkTransferDisputedActionHash(id, disputeHash));

    transfer.resolutionHash =
        disputeHash;

    transfer.lastActionBy =
        msg.sender;

    transfer.updatedAt =
        block.timestamp;

    _setTransferStatus(transfer, TransferStatus.Disputed);

    emit OSTTransferDisputed(
        id,
        msg.sender,
        disputeHash,
        block.timestamp
    );
}
    function _createTransferRequest(
        TransferType transferType,
        address seller,
        address buyer,
        uint256 amount,
        uint256 pricePerOST,
        bytes32 referenceHash,
        address proposer
    )
        internal
        returns (uint256)
    {
        require(
            seller != address(0),
            "Invalid seller"
        );

        require(
            buyer != address(0),
            "Invalid buyer"
        );

        require(
            seller != buyer,
            "Seller and buyer must differ"
        );

        require(
            amount > 0,
            "Amount must be greater than zero"
        );

        require(
            pricePerOST > 0,
            "Price must be greater than zero"
        );

        require(
            referenceHash != bytes32(0),
            "Reference hash required"
        );

        accessControl.onlyValidSender(seller);
        accessControl.onlyValidSender(buyer);

        require(
            tokenManager.balanceOfOST(seller) >= amount,
            "Insufficient seller OST balance"
        );

        uint256 id =
            nextTransferId++;

        transfers[id] = OSTTransfer({
            id: id,
            transferType: transferType,
            proposer: proposer,
            lastActionBy: proposer,
            seller: seller,
            buyer: buyer,
            amount: amount,
            pricePerOST: pricePerOST,
            createdAt: block.timestamp,
            updatedAt: block.timestamp,
            completedAt: 0,
            escrowDeadline: 0,
            status: TransferStatus.Requested,
            referenceHash: referenceHash,
            counterOfferHash: bytes32(0),
            agreementHash: bytes32(0),
            paymentProofHash: bytes32(0),
            sellerReceiptHash: bytes32(0),
            receiptHash: bytes32(0),
            resolutionHash: bytes32(0)
        });

        activeTransferCount[seller]++;
        activeTransferCount[buyer]++;
        openTransferCount++;

        emit OSTTransferRequested(
            id,
            transferType,
            proposer,
            seller,
            buyer,
            amount,
            pricePerOST,
            referenceHash,
            block.timestamp
        );

        return id;
    }

    // -------------------------------------------------------------------------
    // Agreement / counter-offer
    // -------------------------------------------------------------------------

    function counterTransfer(
        uint256 id,
        uint256 newAmount,
        uint256 newPricePerOST,
        bytes32 counterOfferHash
    )
        external
        override
        transferExists(id)
        onlyParticipant(id)
        whenNotPaused
        nonReentrant
    {
        OSTTransfer storage transfer =
            transfers[id];

        require(
            transfer.status == TransferStatus.Requested ||
                transfer.status == TransferStatus.Countered,
            "Transfer cannot be countered"
        );

        require(
            msg.sender != transfer.lastActionBy,
            "Wait for counterparty response"
        );

        require(
            newAmount > 0,
            "Amount must be greater than zero"
        );

        require(
            newPricePerOST > 0,
            "Price must be greater than zero"
        );

        require(
            counterOfferHash != bytes32(0),
            "Counter offer hash required"
        );

        require(
            tokenManager.balanceOfOST(transfer.seller) >= newAmount,
            "Insufficient seller OST balance"
        );

        transfer.amount =
            newAmount;

        transfer.pricePerOST =
            newPricePerOST;

        transfer.counterOfferHash =
            counterOfferHash;

        transfer.lastActionBy =
            msg.sender;

        transfer.updatedAt =
            block.timestamp;

        _setTransferStatus(transfer, TransferStatus.Countered);

        emit OSTTransferCountered(
            id,
            msg.sender,
            newAmount,
            newPricePerOST,
            counterOfferHash,
            block.timestamp
        );
    }

function acceptTransfer(
    uint256 id,
    bytes32 agreementHash
)
    external
    override
    transferExists(id)
    onlyParticipant(id)
    whenNotPaused
    nonReentrant
{
    OSTTransfer storage transfer =
        transfers[id];

    require(
        msg.sender != transfer.lastActionBy,
        "Wait for counterparty response"
    );

    _lockEscrowAfterAgreement(
        id,
        transfer,
        agreementHash,
        msg.sender
    );
}
function _lockEscrowAfterAgreement(
    uint256 id,
    OSTTransfer storage transfer,
    bytes32 agreementHash,
    address actor
)
    internal
{
    require(
        transfer.status == TransferStatus.Requested ||
            transfer.status == TransferStatus.Countered,
        "Transfer cannot be accepted"
    );

    require(
        agreementHash != bytes32(0),
        "Agreement hash required"
    );

    accessControl.onlyValidSender(transfer.seller);
    accessControl.onlyValidSender(transfer.buyer);

    require(
        tokenManager.balanceOfOST(transfer.seller) >= transfer.amount,
        "Insufficient seller OST balance"
    );

    tokenManager.transferOSTfromAtoB(
        transfer.seller,
        escrowAddress,
        transfer.amount
    );

    transfer.agreementHash =
        agreementHash;

    transfer.lastActionBy =
        actor;

    transfer.updatedAt =
        block.timestamp;

    transfer.escrowDeadline =
        block.timestamp + ESCROW_TIMEOUT;

    _setTransferStatus(transfer, TransferStatus.Escrowed);

    emit OSTTransferEscrowed(
        id,
        transfer.seller,
        transfer.buyer,
        transfer.amount,
        transfer.pricePerOST,
        agreementHash,
        block.timestamp
    );
}
    function rejectTransfer(
        uint256 id,
        bytes32 reasonHash
    )
        external
        override
        transferExists(id)
        onlyParticipant(id)
        whenNotPaused
    {
        OSTTransfer storage transfer =
            transfers[id];

        require(
            transfer.status == TransferStatus.Requested ||
                transfer.status == TransferStatus.Countered,
            "Transfer cannot be rejected"
        );

        require(
            msg.sender != transfer.lastActionBy,
            "Wait for counterparty response"
        );

        require(
            reasonHash != bytes32(0),
            "Reason hash required"
        );

        transfer.resolutionHash =
            reasonHash;

        transfer.lastActionBy =
            msg.sender;

        transfer.updatedAt =
            block.timestamp;

        transfer.completedAt =
            block.timestamp;

        _setTransferStatus(transfer, TransferStatus.Rejected);

        emit OSTTransferRejected(
            id,
            msg.sender,
            reasonHash,
            block.timestamp
        );
    }

    function cancelTransfer(
        uint256 id
    )
        external
        override
        transferExists(id)
        onlyParticipant(id)
        whenNotPaused
    {
        OSTTransfer storage transfer =
            transfers[id];

        require(
            transfer.status == TransferStatus.Requested ||
                transfer.status == TransferStatus.Countered,
            "Transfer cannot be cancelled"
        );

        transfer.lastActionBy =
            msg.sender;

        transfer.updatedAt =
            block.timestamp;

        transfer.completedAt =
            block.timestamp;

        _setTransferStatus(transfer, TransferStatus.Cancelled);

        emit OSTTransferCancelled(
            id,
            msg.sender,
            block.timestamp
        );
    }

    // -------------------------------------------------------------------------
    // Payment evidence and seller validation
    // -------------------------------------------------------------------------

    function registerBuyerPaymentProof(
        uint256 id,
        bytes32 paymentProofHash
    )
        external
        override
        transferExists(id)
        whenNotPaused
    {
        OSTTransfer storage transfer =
            transfers[id];

        require(
            msg.sender == transfer.buyer,
            "Only buyer can register payment proof"
        );

        require(
            transfer.status == TransferStatus.Escrowed,
            "Transfer is not escrowed"
        );

        require(
            paymentProofHash != bytes32(0),
            "Payment proof hash required"
        );

        transfer.paymentProofHash =
            paymentProofHash;

        transfer.lastActionBy =
            msg.sender;

        transfer.updatedAt =
            block.timestamp;

        _setTransferStatus(transfer, TransferStatus.PaymentProofRegistered);
        paymentValidationDeadline[id] = block.timestamp + PAYMENT_VALIDATION_TIMEOUT;

        emit BuyerPaymentProofRegistered(
            id,
            msg.sender,
            paymentProofHash,
            block.timestamp
        );
    }

    function sellerValidatePaymentReceipt(
        uint256 id,
        bytes32 sellerReceiptHash
    )
        external
        override
        transferExists(id)
        whenNotPaused
    {
        OSTTransfer storage transfer =
            transfers[id];

        require(
            msg.sender == transfer.seller,
            "Only seller can validate payment receipt"
        );

        require(
            transfer.status == TransferStatus.PaymentProofRegistered,
            "Payment proof not registered"
        );

        require(
            sellerReceiptHash != bytes32(0),
            "Seller receipt hash required"
        );

        transfer.sellerReceiptHash =
            sellerReceiptHash;

        transfer.lastActionBy =
            msg.sender;

        transfer.updatedAt =
            block.timestamp;

        _setTransferStatus(transfer, TransferStatus.SellerValidatedPayment);

        emit SellerPaymentReceiptValidated(
            id,
            msg.sender,
            sellerReceiptHash,
            block.timestamp
        );
    }

    function markTransferDisputed(
        uint256 id,
        bytes32 disputeHash
    )
        external
        override
        transferExists(id)
        onlyParticipant(id)
        whenNotPaused
    {
        OSTTransfer storage transfer =
            transfers[id];

        require(
            transfer.status == TransferStatus.Escrowed ||
                transfer.status == TransferStatus.PaymentProofRegistered ||
                transfer.status == TransferStatus.SellerValidatedPayment,
            "Transfer cannot be disputed"
        );

        require(
            disputeHash != bytes32(0),
            "Dispute hash required"
        );

        transfer.resolutionHash =
            disputeHash;

        transfer.lastActionBy =
            msg.sender;

        transfer.updatedAt =
            block.timestamp;

        _setTransferStatus(transfer, TransferStatus.Disputed);

        emit OSTTransferDisputed(
            id,
            msg.sender,
            disputeHash,
            block.timestamp
        );
    }

    /// @notice Returns OST after an untouched escrow expires, or after the seller
    ///         waits out an unvalidated payment proof with no dispute.
    /// @dev Anyone may reclaim untouched escrow; only the seller may reclaim
    ///      unvalidated payment proof escrow. Funds return to that seller. Callable while
    ///      this module is paused so a pause cannot trap expired escrow forever.
    function reclaimExpiredEscrow(uint256 id) external override transferExists(id) nonReentrant {
        OSTTransfer storage transfer = transfers[id];

        bool proofPending = transfer.status == TransferStatus.PaymentProofRegistered;
        require(
            transfer.status == TransferStatus.Escrowed || proofPending,
            "Escrow is not reclaimable"
        );

        uint256 deadline = proofPending ? paymentValidationDeadline[id] : transfer.escrowDeadline;
        if (proofPending) require(msg.sender == transfer.seller, "Only seller can reclaim payment proof escrow");
        require(
            deadline != 0 && block.timestamp > deadline,
            "Escrow deadline not reached"
        );

        tokenManager.transferOSTfromAtoB(
            escrowAddress,
            transfer.seller,
            transfer.amount
        );

        transfer.lastActionBy = msg.sender;
        transfer.updatedAt = block.timestamp;
        transfer.completedAt = block.timestamp;
        _setTransferStatus(transfer, TransferStatus.Returned);

        emit ExpiredEscrowReclaimed(
            id,
            transfer.seller,
            msg.sender,
            transfer.amount,
            deadline,
            block.timestamp
        );

    }

    // -------------------------------------------------------------------------
    // Registrar/admin finalization
    // -------------------------------------------------------------------------

    /// @notice One quorum approves both seller payment confirmation and the immediate OST release.
    /// @dev Both receipt hashes are immutable approval inputs. Any failed release rolls back the confirmation and consumption.
    function adminConfirmSellerPaymentAndRelease(
        uint256 id, bytes32 sellerReceiptHash, bytes32 receiptHash
    ) external override onlyAdmin transferExists(id) whenNotPaused nonReentrant {
        OSTTransfer storage transfer = transfers[id];
        require(transfer.status == TransferStatus.PaymentProofRegistered, "Payment proof not registered");
        require(sellerReceiptHash != bytes32(0), "Seller receipt hash required");
        require(receiptHash != bytes32(0), "Receipt hash required");
        adminMultisig.consumeApprovedAction(getAdminConfirmSellerPaymentAndReleaseActionHash(id, sellerReceiptHash, receiptHash));
        transfer.sellerReceiptHash = sellerReceiptHash;
        _setTransferStatus(transfer, TransferStatus.SellerValidatedPayment);
        emit SellerPaymentReceiptValidated(id, transfer.seller, sellerReceiptHash, block.timestamp);
        _releaseEscrowToBuyer(id, transfer, receiptHash);
    }

    function adminConfirmOSTTransaction(
        uint256 id,
        bytes32 receiptHash
    )
        external
        override
        onlyAdmin
        transferExists(id)
        whenNotPaused
        nonReentrant
    {
        OSTTransfer storage transfer =
            transfers[id];

        require(
            transfer.status == TransferStatus.SellerValidatedPayment,
            "Seller has not validated payment"
        );

        require(
            receiptHash != bytes32(0),
            "Receipt hash required"
        );

        adminMultisig.consumeApprovedAction(getAdminConfirmOSTTransactionActionHash(id, receiptHash));

        _releaseEscrowToBuyer(
            id,
            transfer,
            receiptHash
        );
    }

    function getAdminResolveTransferActionHash(
        uint256 id,
        bool releaseToBuyer,
        bytes32 resolutionHash,
        bytes32 receiptHash
    ) public view override transferExists(id) returns (bytes32) {
        OSTTransfer storage transfer = transfers[id];

        return keccak256(
            abi.encode(
                address(this),
                block.chainid,
                "ADMIN_RESOLVE_OST_TRANSFER",
                id,
                transfer.seller,
                transfer.buyer,
                transfer.amount,
                releaseToBuyer,
                resolutionHash,
                receiptHash
            )
        );
    }

    function adminResolveTransfer(
        uint256 id,
        bool releaseToBuyer,
        bytes32 resolutionHash,
        bytes32 receiptHash
    ) external override onlyAdmin transferExists(id) whenNotPaused nonReentrant {
        OSTTransfer storage transfer = transfers[id];

        require(
            transfer.status == TransferStatus.Escrowed ||
                transfer.status == TransferStatus.PaymentProofRegistered ||
                transfer.status == TransferStatus.SellerValidatedPayment ||
                transfer.status == TransferStatus.Disputed,
            "Transfer cannot be resolved"
        );

        require(resolutionHash != bytes32(0), "Resolution hash required");
        require(receiptHash != bytes32(0), "Receipt hash required");

        bytes32 actionHash = getAdminResolveTransferActionHash(
            id,
            releaseToBuyer,
            resolutionHash,
            receiptHash
        );

        adminMultisig.consumeApprovedAction(actionHash);

        transfer.resolutionHash = resolutionHash;

        if (releaseToBuyer) {
            _releaseEscrowToBuyer(id, transfer, receiptHash);
        } else {
            tokenManager.transferOSTfromAtoB(escrowAddress, transfer.seller, transfer.amount);

            transfer.receiptHash = receiptHash;
            transfer.lastActionBy = msg.sender;
            transfer.updatedAt = block.timestamp;
            transfer.completedAt = block.timestamp;
            _setTransferStatus(transfer, TransferStatus.Returned);

            emit OSTTransferReturned(
                id,
                transfer.seller,
                transfer.buyer,
                transfer.amount,
                resolutionHash,
                receiptHash,
                block.timestamp
            );
        }
    }

    function _releaseEscrowToBuyer(
        uint256 id,
        OSTTransfer storage transfer,
        bytes32 receiptHash
    )
        internal
    {
        // M-3: both participants must remain eligible at the actual share release.
        // Earlier checks at request creation and escrow lock are not sufficient:
        // a participant may be frozen, de-authorized, or de-whitelisted later.
        accessControl.onlyValidSender(transfer.seller);
        accessControl.onlyValidSender(transfer.buyer);

        tokenManager.transferOSTfromAtoB(
            escrowAddress,
            transfer.buyer,
            transfer.amount
        );

        transfer.receiptHash =
            receiptHash;

        transfer.lastActionBy =
            msg.sender;

        transfer.updatedAt =
            block.timestamp;

        transfer.completedAt =
            block.timestamp;

        _setTransferStatus(transfer, TransferStatus.Released);

        emit OSTTransferReleased(
            id,
            transfer.seller,
            transfer.buyer,
            transfer.amount,
            receiptHash,
            block.timestamp
        );
    }

    function adminRecordTransferReceiptHash(
        uint256 id,
        bytes32 receiptHash
    )
        external
        override
        onlyAdmin
        transferExists(id)
    {
        OSTTransfer storage transfer =
            transfers[id];

        require(
            transfer.status == TransferStatus.Released ||
                transfer.status == TransferStatus.Returned,
            "Transfer not completed"
        );

        require(
            receiptHash != bytes32(0),
            "Receipt hash required"
        );

        require(transfer.receiptHash == bytes32(0), "Receipt hash already recorded");
        transfer.receiptHash =
            receiptHash;

        transfer.updatedAt =
            block.timestamp;

        emit OSTTransferReceiptHashRecorded(
            id,
            receiptHash,
            block.timestamp
        );
    }

    // -------------------------------------------------------------------------
    // Views
    // -------------------------------------------------------------------------

    function transfersf(
        uint256 id
    )
        external
        view
        override
        returns (OSTTransfer memory)
    {
        return transfers[id];
    }

    function nextTransferIdf()
        external
        view
        override
        returns (uint256)
    {
        return nextTransferId;
    }
}
