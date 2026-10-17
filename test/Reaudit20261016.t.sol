// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "./IQOSTokenTest.t.sol";

contract Reaudit20261016Test is Test {

    IQOS public iqos;
    AccessControl public accessControl;
    TokenManager public tokenManager;
    OSTTransferModule public ostTransferModule;
    ConversionModule public conversionModule;
    AdminMultisig public adminMultisig;
    BSARegistry public bsaRegistry;
    HashRegistry public hashRegistry;
    ValuationAnchor public valuationAnchor;
    GovernanceRegistry public governanceRegistry;
    EmergencyController public emergencyController;
    HolderMigrationController public holderMigrationController;
    TokenOperatorController public tokenOperatorController;

    address owner = address(0xABCD);
    address signer2 = address(0xBEEF);
    address signer3 = address(0xCAFE);
    address safeOwner = address(0xA11CE);
    address alice = address(0x1);
    address bob = address(0x2);
    address mallory = address(0x3);

    address aliceNewWallet = address(0x4);
    address newSigner = address(0xD00D);

    bytes32 constant SIGNER_ROTATION_REF = keccak256("admin-signer-rotation-ref");
    bytes32 constant ACTION_CONSUMER_REF = keccak256("action-consumer-change-ref");
    bytes32 constant REQUIRED_SIGNATURES_REF = keccak256("required-signatures-change-ref");
    bytes32 constant BSA_HASH = keccak256("bsa-refHash-hash-only");
    bytes32 constant AWARD_REF = keccak256("iqs-award-refHash-hash");
    bytes32 constant EXERCISE_REF = keccak256("exercise-refHash-hash");
    bytes32 constant CAPITAL_PAYMENT_HASH = keccak256("capital-payment-hash");
    bytes32 constant RECEIPT_HASH = keccak256("receipt-hash");
    bytes32 constant TRANSFER_REF = keccak256("ost-transfer-refHash-hash");
    bytes32 constant AGREEMENT_HASH = keccak256("agreement-hash");
    bytes32 constant PAYMENT_PROOF_HASH = keccak256("payment-proof-hash");
    bytes32 constant SELLER_RECEIPT_HASH = keccak256("seller-receipt-hash");
    bytes32 constant SAMPLE_HASH = keccak256("document-hash");
    bytes32 constant BSA_TERMS_HASH = keccak256("bsa-terms-hash-only");
    bytes32 constant PERIOD_Q3_2026 = keccak256("Q3-2026");
    bytes32 constant VALUATION_HASH = keccak256("valuation-record-q3-2026");
    bytes32 constant VALUATION_CORRECTION_HASH = keccak256("valuation-correction-q3-2026");
    bytes32 constant METHODOLOGY_HASH = keccak256("EXPVAL-2026-03");
    bytes32 constant VOTE_METADATA_HASH = keccak256("vote-metadata-hash");
    bytes32 constant BALLOT_ROOT = keccak256("test-root-of-canonical-signed-ballots");
    bytes32 constant MIGRATION_REF = keccak256("holder-migration-evidence-hash");
    bytes32 constant TOKEN_OPERATOR_REF = keccak256("token-operator-change-ref");
    bytes32 constant EMERGENCY_PAUSE_ALL_REF =keccak256("emergency-pause-all-ref");
    bytes32 constant EMERGENCY_UNPAUSE_ALL_REF =keccak256("emergency-unpause-all-ref");
    bytes32 constant EMERGENCY_DISTRIBUTION_REF =keccak256("emergency-distribution-ref");
    bytes32 constant EMERGENCY_CONVERSIONS_REF =keccak256("emergency-conversions-ref");
    bytes32 constant EMERGENCY_TRANSACTIONS_REF =keccak256("emergency-transactions-ref");

function setUp() public {
    vm.startPrank(owner);

    accessControl = new AccessControl(owner);

    accessControl.addAdmin(signer2);
    accessControl.addAdmin(signer3);

    tokenManager = new TokenManager(address(accessControl));

    address[] memory signers = new address[](3);
    signers[0] = owner;
    signers[1] = signer2;
    signers[2] = signer3;

    adminMultisig = new AdminMultisig(
        address(accessControl),
        signers,
        2
    );

    // Keep the production invariant: every multisig signer is an admin and
    // AdminMultisig is the one-time controller for atomic signer/admin rotation.
    accessControl.setAdminSignerController(address(adminMultisig));

    ostTransferModule = new OSTTransferModule(
        address(accessControl),
        address(tokenManager),
        address(adminMultisig)
    );

    bsaRegistry = new BSARegistry(
        address(accessControl),
        address(tokenManager),
        address(adminMultisig)
    );

    conversionModule = new ConversionModule(
        address(accessControl),
        address(tokenManager),
        address(adminMultisig),
        address(bsaRegistry)
    );

    hashRegistry = new HashRegistry(
        address(accessControl)
    );

    governanceRegistry = new GovernanceRegistry(
        address(accessControl),
        address(hashRegistry),
        address(adminMultisig)
    );


    valuationAnchor = new ValuationAnchor(
        address(accessControl),
        address(adminMultisig),
        address(hashRegistry)
    );


    emergencyController = new EmergencyController(
        address(accessControl),
        address(adminMultisig),
        address(tokenManager),
        address(bsaRegistry),
        address(conversionModule),
        address(ostTransferModule),
        address(valuationAnchor),
        address(governanceRegistry)
    );


    holderMigrationController = new HolderMigrationController(
        address(accessControl),
        address(adminMultisig),
        address(tokenManager),
        address(bsaRegistry)
    );

    bsaRegistry.setHolderMigrationController(address(holderMigrationController));

    accessControl.setRole(accessControl.ROLE_ACCOUNT_MANAGER(), address(tokenManager), true);
    accessControl.setRole(accessControl.ROLE_ANCHOR(), address(valuationAnchor), true);
    accessControl.setRole(accessControl.ROLE_ANCHOR(), address(governanceRegistry), true);
    accessControl.setRole(accessControl.ROLE_EMERGENCY(), address(emergencyController), true);
    /*
     * TokenManager needs admin rights because during holder migration it updates
     * AccessControl state for old/new wallets.
     */

    tokenManager.setWalletMigrationController(
        address(holderMigrationController)
    );

    /*
     * Bootstrap token operators BEFORE locking TokenManager behind
     * TokenOperatorController.
     */
    tokenManager.setTokenOperator(
        address(ostTransferModule),
        true
    );

    // M-6: register OSTTransferModule as the sole custodial OST escrow.
    // This must run during deployment bootstrap, before operator controller lock.
    tokenManager.setOSTEscrowAddress(address(ostTransferModule));
    assertEq(tokenManager.ostEscrowAddress(), address(ostTransferModule));

    tokenManager.setTokenOperator(
        address(bsaRegistry),
        true
    );

    tokenManager.setTokenOperator(
        address(conversionModule),
        true
    );

    tokenOperatorController = new TokenOperatorController(
        address(accessControl),
        address(adminMultisig),
        address(tokenManager)
    );

    tokenManager.setTokenOperatorController(
        address(tokenOperatorController)
    );

    /*
     * Register all approved multisig action consumers BEFORE bootstrap lock.
     */
    adminMultisig.setActionConsumer(
        address(conversionModule),
        true
    );

    adminMultisig.setActionConsumer(
        address(valuationAnchor),
        true
    );
    adminMultisig.setActionConsumer(address(governanceRegistry), true);

    adminMultisig.setActionConsumer(
        address(holderMigrationController),
        true
    );

    adminMultisig.setActionConsumer(
        address(tokenOperatorController),
        true
    );
    adminMultisig.setActionConsumer(
        address(emergencyController),
        true
    );
    bsaRegistry.setConversionModule(
        address(conversionModule)
    );

    iqos = new IQOS(
        address(accessControl),
        address(tokenManager),
        address(ostTransferModule),
        address(conversionModule),
        address(hashRegistry),
        address(adminMultisig),
        address(bsaRegistry),
        address(valuationAnchor),
        address(governanceRegistry),
        address(emergencyController),
        address(holderMigrationController),
        address(tokenOperatorController)
    );
    adminMultisig.setActionConsumer(address(bsaRegistry), true);
    adminMultisig.setActionConsumer(address(ostTransferModule), true);
    adminMultisig.lockActionConsumerBootstrap();

    vm.stopPrank();
}

function _makeValidUser(address user) internal {
        vm.startPrank(owner);

        if (!accessControl.isWhiteListed(user)) {
            accessControl.addToWhiteList(user);
        }

        if (!accessControl.isAuthorized(user)) {
            accessControl.authorizeAddress(user);
        }

        vm.stopPrank();
    }

function _proposeTestAction(bytes32 actionHash, address consumer) internal {
        (bool exists,,,,,,, uint256 previousDeadline) = adminMultisig.getActionProposal(actionHash);
        uint256 nowTimestamp = vm.getBlockTimestamp();
        if (exists && nowTimestamp <= previousDeadline) return;

        // External getter MUST run before vm.prank, otherwise the prank
        // is consumed by ACTION_APPROVAL_VALIDITY(), not proposeAction().
        uint256 deadline = nowTimestamp + adminMultisig.ACTION_APPROVAL_VALIDITY();
        vm.prank(owner);
        adminMultisig.proposeAction(
            actionHash,
            consumer,
            bytes4(keccak256("TEST_ACTION(bytes32)")),
            keccak256(abi.encode(actionHash, consumer)),
            "Foundry test fixture - not a production proposal",
            deadline
        );
    }

function _recordBSA(
        address user,
        uint256 strikePrice,
        uint256 maxIQS
    ) internal returns (uint256) {
        _makeValidUser(user);

        uint256 expiryDate =
            block.timestamp + 365 days;

        bytes32 actionHash =
            bsaRegistry.getRecordBSAActionHash(
                user,
                BSA_HASH,
                BSA_TERMS_HASH,
                strikePrice,
                maxIQS,
                expiryDate,
                0
            );

        _approveActionForConsumerByTwoSigners(actionHash, address(bsaRegistry));

        vm.prank(owner);

        return bsaRegistry.recordBSA(
            user,
            BSA_HASH,
            BSA_TERMS_HASH,
            strikePrice,
            maxIQS,
            expiryDate,
            0
        );
    }

function _awardIQS(
        address user,
        uint256 amount
    ) internal returns (uint256) {
        uint256 bsaId =
            _recordBSA(
                user,
                185,
                amount
            );

        _approveActionForConsumerByTwoSigners(bsaRegistry.getCreditIQSActionHash(bsaId, amount, AWARD_REF), address(bsaRegistry));
    vm.prank(owner);

        bsaRegistry.creditIQS(
            bsaId,
            amount,
            AWARD_REF
        );

        return bsaId;
    }

function _mintOST(address user, uint256 amount) internal {
        uint256 bsaId =
            _awardIQS(
                user,
                amount
            );

        vm.prank(user);

        uint256 requestId =
            conversionModule.requestExercise(
                bsaId,
                amount,
                EXERCISE_REF
            );

        vm.prank(owner);
        conversionModule.approveExercise(requestId);

        vm.prank(owner);
        conversionModule.confirmCapitalReceived(
            requestId,
            CAPITAL_PAYMENT_HASH
        );

        bytes32 actionHash =
            conversionModule.getFinalizeExerciseActionHash(
                requestId,
                RECEIPT_HASH
            );

        _approveActionForConsumerByAllSigners(
            actionHash,
            address(conversionModule)
        );

        vm.prank(owner);
        conversionModule.finalizeExercise(
            requestId,
            RECEIPT_HASH
        );
    }

function _approveActionForConsumerByTwoSigners(
    bytes32 actionHash,
    address consumer
) internal {
    _proposeTestAction(actionHash, consumer);
    vm.prank(owner);
    adminMultisig.approveActionForConsumer(
        actionHash,
        consumer
    );

    vm.prank(signer2);
    adminMultisig.approveActionForConsumer(
        actionHash,
        consumer
    );
}

function _approveActionForConsumerByAllSigners(
    bytes32 actionHash,
    address consumer
) internal {
    _proposeTestAction(actionHash, consumer);
    vm.prank(owner);
    adminMultisig.approveActionForConsumer(
        actionHash,
        consumer
    );

    vm.prank(signer2);
    adminMultisig.approveActionForConsumer(
        actionHash,
        consumer
    );

    vm.prank(signer3);
    adminMultisig.approveActionForConsumer(
        actionHash,
        consumer
    );
}

function _reviewEscrow() internal returns (uint256) {
        _mintOST(alice, 100);
        _makeValidUser(bob);
        vm.prank(alice);
        uint256 id = ostTransferModule.createSellTransferRequest(alice, bob, 30, 200, TRANSFER_REF);
        vm.prank(bob);
        ostTransferModule.acceptTransfer(id, AGREEMENT_HASH);
        return id;
    }

function _reviewPaymentProof(uint256 id) internal {
        vm.prank(bob);
        ostTransferModule.registerBuyerPaymentProof(id, PAYMENT_PROOF_HASH);
    }

function _reviewSellerValidation(uint256 id) internal {
        _reviewPaymentProof(id);
        vm.prank(alice);
        ostTransferModule.sellerValidatePaymentReceipt(id, SELLER_RECEIPT_HASH);
    }

function _reviewCapitalReceived() internal returns (uint256 bsaId, uint256 requestId) {
        bsaId = _awardIQS(alice, 100);
        vm.prank(alice);
        requestId = conversionModule.requestExercise(bsaId, 30, EXERCISE_REF);
        vm.prank(owner);
        conversionModule.approveExercise(requestId);
        vm.prank(owner);
        conversionModule.confirmCapitalReceived(requestId, CAPITAL_PAYMENT_HASH);
    }


    function _credit(uint256 id, uint256 amount, bytes32 refHash) internal {
        _approveActionForConsumerByTwoSigners(bsaRegistry.getCreditIQSActionHash(id, amount, refHash), address(bsaRegistry));
        vm.prank(owner); bsaRegistry.creditIQS(id, amount, refHash);
    }
    function _cancel(uint256 id, bytes32 reason) internal {
        _approveActionForConsumerByTwoSigners(bsaRegistry.getCancelBSAActionHash(id, reason), address(bsaRegistry));
        vm.prank(owner); bsaRegistry.cancelBSA(id, reason);
    }
    function _consumeState(bytes32 hash, bool expected) internal view {
        (,bool consumed,) = adminMultisig.getApprovalState(hash); assertEq(consumed, expected);
    }
    function _migrationHash() internal view returns (bytes32) {
        return keccak256(abi.encode(address(holderMigrationController), block.chainid, "HOLDER_WALLET_MIGRATION", alice, aliceNewWallet, MIGRATION_REF));
    }
    function _approveMigration() internal returns (uint256) {
        _approveActionForConsumerByTwoSigners(_migrationHash(), address(holderMigrationController));
        return holderMigrationController.migrationReadyAt(alice, aliceNewWallet, MIGRATION_REF);
    }
    function _migrate() internal {
        vm.prank(owner); holderMigrationController.migrateHolder(alice, aliceNewWallet, MIGRATION_REF);
    }
    function _abortHash(bytes32 reason) internal view returns (bytes32) {
        return holderMigrationController.getAbortHolderMigrationActionHash(alice, aliceNewWallet, MIGRATION_REF, reason);
    }
    function _abort(bytes32 reason) internal {
        vm.prank(owner); holderMigrationController.abortHolderMigration(alice, aliceNewWallet, MIGRATION_REF, reason);
    }
    function _recordAt(address user, uint256 maxIQS, uint256 expiry, bytes32 refHash) internal returns (uint256) {
        _makeValidUser(user);
        bytes32 hash = bsaRegistry.getRecordBSAActionHash(user, refHash, BSA_TERMS_HASH, 185, maxIQS, expiry, 0);
        _approveActionForConsumerByTwoSigners(hash, address(bsaRegistry));
        vm.prank(owner); return bsaRegistry.recordBSA(user, refHash, BSA_TERMS_HASH, 185, maxIQS, expiry, 0);
    }
    function _replacement(bytes32 hash) internal view returns (IAdminMultisig.ProposalReplacement memory) {
        return IAdminMultisig.ProposalReplacement(hash, adminMultisig.getActionProposalFingerprint(hash),
            address(bsaRegistry), BSARegistry.cancelBSA.selector, keccak256("correct-calldata"), "Quorum repair", block.timestamp + 7 days);
    }
    function _squat(bytes32 hash) internal {
        vm.prank(signer3); adminMultisig.proposeAction(hash, address(conversionModule), bytes4(0x11223344),
            keccak256("incorrect-calldata"), "Incorrect consumer", block.timestamp + 7 days);
    }
    function _repair(IAdminMultisig.ProposalReplacement memory r) internal {
        vm.prank(owner); adminMultisig.approveProposalReplacement(r);
        vm.prank(signer2); adminMultisig.approveProposalReplacement(r);
    }

    function testN01SingleAdminCannotCancelOrBurnIQS() public {
        uint256 id = _recordBSA(alice,185,100); _credit(id,80,AWARD_REF);
        bytes32 reason=keccak256("cancel"); bytes32 hash=bsaRegistry.getCancelBSAActionHash(id,reason);
        vm.prank(owner); vm.expectRevert("Action belongs to different consumer"); bsaRegistry.cancelBSA(id,reason);
        _proposeTestAction(hash,address(bsaRegistry));
        vm.prank(owner); adminMultisig.approveActionForConsumer(hash,address(bsaRegistry));
        vm.prank(owner); vm.expectRevert("Action not approved"); bsaRegistry.cancelBSA(id,reason);
        assertEq(tokenManager.balanceOfIQS(alice),80); assertEq(bsaRegistry.totalIQSInEscrow(),20);
        vm.prank(signer2); adminMultisig.approveActionForConsumer(hash,address(bsaRegistry));
        vm.prank(owner); bsaRegistry.cancelBSA(id,reason);
        assertEq(tokenManager.balanceOfIQS(alice),0); assertEq(bsaRegistry.totalIQSInEscrow(),0);
        _consumeState(hash,true);
        vm.prank(owner); vm.expectRevert("BSA cannot be cancelled"); bsaRegistry.cancelBSA(id,reason);
    }
    function testN01CancellationBindsReasonAndBSA() public {
        uint256 first=_recordBSA(alice,185,100); uint256 second=_recordBSA(bob,185,100);
        bytes32 reason=keccak256("cancel-first"); bytes32 hash=bsaRegistry.getCancelBSAActionHash(first,reason);
        _approveActionForConsumerByTwoSigners(hash,address(bsaRegistry));
        vm.prank(owner); vm.expectRevert("Action belongs to different consumer"); bsaRegistry.cancelBSA(second,reason);
        vm.prank(owner); vm.expectRevert("Action belongs to different consumer"); bsaRegistry.cancelBSA(first,keccak256("other"));
        _consumeState(hash,false); assertEq(bsaRegistry.totalIQSInEscrow(),200);
    }
    function testN01BurnFailureRollsBackApprovalAndEscrow() public {
        uint256 id=_recordBSA(alice,185,100); _credit(id,40,AWARD_REF);
        bytes32 reason=keccak256("rollback"); bytes32 hash=bsaRegistry.getCancelBSAActionHash(id,reason);
        _approveActionForConsumerByTwoSigners(hash,address(bsaRegistry));
        vm.prank(address(tokenOperatorController)); tokenManager.setTokenOperator(address(bsaRegistry),false);
        vm.prank(owner); vm.expectRevert("Caller is not a token operator"); bsaRegistry.cancelBSA(id,reason);
        _consumeState(hash,false); assertEq(bsaRegistry.totalIQSInEscrow(),60); assertEq(tokenManager.totalSupplyIQS(),40);
    }

    function testN02SettledTransferReceiptCannotBeOverwritten() public {
        uint256 id=_reviewEscrow(); _reviewSellerValidation(id);
        _approveActionForConsumerByTwoSigners(ostTransferModule.getAdminConfirmOSTTransactionActionHash(id,RECEIPT_HASH),address(ostTransferModule));
        vm.prank(owner); ostTransferModule.adminConfirmOSTTransaction(id,RECEIPT_HASH);
        vm.prank(signer2); vm.expectRevert("Receipt hash already recorded"); ostTransferModule.adminRecordTransferReceiptHash(id,keccak256("replacement"));
        vm.prank(owner); vm.expectRevert("Receipt hash already recorded"); ostTransferModule.adminRecordTransferReceiptHash(id,RECEIPT_HASH);
        assertEq(ostTransferModule.transfersf(id).receiptHash,RECEIPT_HASH);
    }
    function testN02ReclaimedTransferAllowsOnlyFirstReceipt() public {
        uint256 id=_reviewEscrow(); vm.warp(ostTransferModule.transfersf(id).escrowDeadline+1);
        ostTransferModule.reclaimExpiredEscrow(id);
        vm.prank(owner); ostTransferModule.adminRecordTransferReceiptHash(id,RECEIPT_HASH);
        vm.prank(signer2); vm.expectRevert("Receipt hash already recorded"); ostTransferModule.adminRecordTransferReceiptHash(id,keccak256("replacement"));
        assertEq(ostTransferModule.transfersf(id).receiptHash,RECEIPT_HASH);
    }
    function testN02SettledExerciseReceiptCannotBeOverwritten() public {
        (,uint256 id)=_reviewCapitalReceived();
        _approveActionForConsumerByTwoSigners(conversionModule.getFinalizeExerciseActionHash(id,RECEIPT_HASH),address(conversionModule));
        vm.prank(owner); conversionModule.finalizeExercise(id,RECEIPT_HASH);
        vm.prank(owner); vm.expectRevert("Receipt hash already recorded"); conversionModule.recordExerciseReceiptHash(id,keccak256("replacement"));
        vm.prank(signer2); vm.expectRevert("Receipt hash already recorded"); conversionModule.recordExerciseReceiptHash(id,RECEIPT_HASH);
        assertEq(conversionModule.getExerciseRequest(id).receiptHash,RECEIPT_HASH);
    }
    function testN02ReturnedResolutionReceiptIsAlsoImmutable() public {
        uint256 id=_reviewEscrow(); bytes32 reason=keccak256("return");
        _approveActionForConsumerByTwoSigners(ostTransferModule.getAdminResolveTransferActionHash(id,false,reason,RECEIPT_HASH),address(ostTransferModule));
        vm.prank(owner); ostTransferModule.adminResolveTransfer(id,false,reason,RECEIPT_HASH);
        vm.prank(owner); vm.expectRevert("Receipt hash already recorded"); ostTransferModule.adminRecordTransferReceiptHash(id,keccak256("rewrite"));
    }

    function testN03OneAdminCannotDisputeAndBlockReclaim() public {
        uint256 id=_reviewEscrow(); bytes32 reason=keccak256("dispute");
        bytes32 hash=ostTransferModule.getAdminMarkTransferDisputedActionHash(id,reason);
        _proposeTestAction(hash,address(ostTransferModule));
        vm.prank(owner); adminMultisig.approveActionForConsumer(hash,address(ostTransferModule));
        vm.prank(owner); vm.expectRevert("Action not approved"); ostTransferModule.adminMarkTransferDisputed(id,reason);
        vm.warp(ostTransferModule.transfersf(id).escrowDeadline+1); ostTransferModule.reclaimExpiredEscrow(id);
        assertEq(tokenManager.balanceOfOST(alice),100);
    }
    function testN03QuorumDisputeBindsReasonAndIsConsumed() public {
        uint256 id=_reviewEscrow(); bytes32 reason=keccak256("dispute");
        bytes32 hash=ostTransferModule.getAdminMarkTransferDisputedActionHash(id,reason);
        _approveActionForConsumerByTwoSigners(hash,address(ostTransferModule));
        vm.prank(owner); vm.expectRevert("Action belongs to different consumer"); ostTransferModule.adminMarkTransferDisputed(id,keccak256("wrong"));
        vm.prank(owner); ostTransferModule.adminMarkTransferDisputed(id,reason); _consumeState(hash,true);
        assertEq(uint256(ostTransferModule.transfersf(id).status),uint256(IOSTTransferModule.TransferStatus.Disputed));
        vm.warp(ostTransferModule.transfersf(id).escrowDeadline+1); vm.expectRevert("Escrow is not reclaimable"); ostTransferModule.reclaimExpiredEscrow(id);
    }

    function testN04CreditsMoveRightsFromEscrowToSupply() public {
        uint256 id=_recordBSA(alice,185,100);
        assertEq(bsaRegistry.totalIQSInEscrow(),100); assertEq(bsaRegistry.iqsInEscrowOf(alice),100); assertEq(tokenManager.totalSupplyIQS(),0);
        _credit(id,30,AWARD_REF);
        assertEq(bsaRegistry.totalIQSInEscrow(),70); assertEq(tokenManager.totalSupplyIQS(),30); assertEq(bsaRegistry.iqsInEscrowOf(alice),70);
        _credit(id,70,keccak256("remaining"));
        assertEq(bsaRegistry.totalIQSInEscrow(),0); assertEq(tokenManager.totalSupplyIQS(),100);
    }
    function testN04ExpiryExcludedBeforeSyncAndCannotSubtractTwice() public {
        uint256 id=_recordBSA(alice,185,100); _credit(id,30,AWARD_REF);
        uint256 expiry=bsaRegistry.bsasf(id).expiryDate;
        vm.warp(expiry-1); assertEq(bsaRegistry.totalIQSInEscrow(),70);
        vm.warp(expiry); assertEq(bsaRegistry.totalIQSInEscrow(),0); assertEq(bsaRegistry.iqsInEscrowOf(alice),0);
        assertEq(uint256(bsaRegistry.bsasf(id).status),uint256(IBSARegistry.BSAStatus.Active));
        bsaRegistry.syncBSAStatus(id); bsaRegistry.syncBSAStatus(id);
        assertEq(bsaRegistry.totalIQSInEscrow(),0); assertEq(tokenManager.totalSupplyIQS(),0);
    }
    function testN04StaggeredExpiriesAndCancelledAllocation() public {
        uint256 t=block.timestamp;
        uint256 first=_recordAt(alice,100,t+10 days,keccak256("first"));
        uint256 second=_recordAt(bob,200,t+20 days,keccak256("second"));
        uint256 third=_recordAt(mallory,300,t+20 days,keccak256("third"));
        _credit(first,20,AWARD_REF); _credit(second,50,keccak256("second-credit")); _cancel(third,keccak256("cancel-third"));
        assertEq(bsaRegistry.totalIQSInEscrow(),230);
        vm.warp(t+10 days); assertEq(bsaRegistry.totalIQSInEscrow(),150);
        bsaRegistry.syncBSAStatus(first); assertEq(bsaRegistry.totalIQSInEscrow(),150);
        vm.warp(t+20 days); assertEq(bsaRegistry.totalIQSInEscrow(),0);
        bsaRegistry.syncBSAStatus(second); assertEq(bsaRegistry.totalIQSInEscrow(),0);
    }
    function testN04ExercisingPreservesValuationDenominator() public {
        uint256 id=_recordBSA(alice,185,100); _credit(id,40,AWARD_REF);
        vm.prank(alice); uint256 request=conversionModule.requestExercise(id,10,EXERCISE_REF);
        vm.prank(owner); conversionModule.approveExercise(request);
        vm.prank(owner); conversionModule.confirmCapitalReceived(request,CAPITAL_PAYMENT_HASH);
        _approveActionForConsumerByTwoSigners(conversionModule.getFinalizeExerciseActionHash(request,RECEIPT_HASH),address(conversionModule));
        vm.prank(owner); conversionModule.finalizeExercise(request,RECEIPT_HASH);
        assertEq(tokenManager.totalSupplyOSTf(),10); assertEq(tokenManager.totalSupplyIQS(),30); assertEq(bsaRegistry.totalIQSInEscrow(),60);
        assertEq(tokenManager.totalSupplyOSTf()+tokenManager.totalSupplyIQS()+bsaRegistry.totalIQSInEscrow(),100);
    }
    function testN04ExpiryGetterWorksWhileTokenManagerPaused() public {
        uint256 id=_recordBSA(alice,185,100); _credit(id,40,AWARD_REF);
        vm.prank(owner); tokenManager.pause(); vm.warp(bsaRegistry.bsasf(id).expiryDate);
        assertEq(bsaRegistry.totalIQSInEscrow(),0);
        vm.expectRevert(); bsaRegistry.syncBSAStatus(id);
        assertEq(bsaRegistry.totalIQSInEscrow(),0);
    }
    function testN04FullUint64ExpiryRange() public {
        uint256 id=_recordAt(alice,100,type(uint64).max,keccak256("far-future"));
        assertEq(bsaRegistry.totalIQSInEscrow(),100);
        vm.warp(uint256(type(uint64).max)-1); assertEq(bsaRegistry.totalIQSInEscrow(),100);
        vm.warp(type(uint64).max); assertEq(bsaRegistry.totalIQSInEscrow(),0);
        bsaRegistry.syncBSAStatus(id); assertEq(bsaRegistry.totalIQSInEscrow(),0);
    }
    function testN04MigrationMovesHolderEscrowWithoutChangingGlobal() public {
        uint256 id=_recordBSA(alice,185,100); _credit(id,30,AWARD_REF);
        uint256 ready=_approveMigration(); vm.warp(ready); _migrate();
        assertEq(bsaRegistry.iqsInEscrowOf(alice),0); assertEq(bsaRegistry.iqsInEscrowOf(aliceNewWallet),70);
        assertEq(bsaRegistry.totalIQSInEscrow(),70); assertEq(tokenManager.totalSupplyIQS(),30);
    }
    function testN04NewBSAAfterUnsyncedExpiryPreservesAggregate() public {
        uint256 id=_recordBSA(alice,185,100); _credit(id,30,AWARD_REF);
        vm.warp(bsaRegistry.bsasf(id).expiryDate);
        uint256 next=_recordAt(alice,200,block.timestamp+365 days,keccak256("new-bsa"));
        assertGt(next,id); assertEq(bsaRegistry.totalIQSInEscrow(),200); assertEq(tokenManager.totalSupplyIQS(),0);
    }
    function testFuzz_N04EscrowEqualsUnreleasedUnexpiredRights(uint64 rawMax, uint64 rawCredit, uint32 rawExpiry) public {
        uint256 maxIQS=bound(rawMax,1,1e12); uint256 amount=bound(rawCredit,0,maxIQS);
        uint256 expiry=block.timestamp+bound(rawExpiry,1,3650 days);
        uint256 id=_recordAt(alice,maxIQS,expiry,keccak256("fuzz-bsa"));
        if(amount>0) _credit(id,amount,AWARD_REF);
        assertEq(bsaRegistry.totalIQSInEscrow(),maxIQS-amount);
        assertEq(bsaRegistry.iqsInEscrowOf(alice),maxIQS-amount); assertEq(tokenManager.totalSupplyIQS(),amount);
        vm.warp(expiry); assertEq(bsaRegistry.totalIQSInEscrow(),0);
        bsaRegistry.syncBSAStatus(id); assertEq(bsaRegistry.totalIQSInEscrow(),0);
    }

    function testF05QuorumRepairsSquatBeforeExpiryAndPreventsResquatting() public {
        bytes32 hash=keccak256("squatted-action"); _squat(hash);
        IAdminMultisig.ProposalReplacement memory r=_replacement(hash);
        bytes32 replacementHash=adminMultisig.getProposalReplacementHash(r);
        vm.prank(owner); adminMultisig.approveProposalReplacement(r);
        (,,address consumer,,,,,)=adminMultisig.getActionProposal(hash); assertEq(consumer,address(conversionModule));
        vm.prank(owner); vm.expectRevert("Signer already voted"); adminMultisig.approveProposalReplacement(r);
        vm.prank(signer2); adminMultisig.approveProposalReplacement(r);
        assertEq(adminMultisig.getProposalReplacementApprovalCount(replacementHash),2);
        (,,consumer,,,,,)=adminMultisig.getActionProposal(hash); assertEq(consumer,address(bsaRegistry));
        vm.warp(r.deadline+1);
        vm.prank(signer3); vm.expectRevert("Action intent fixed by quorum");
        adminMultisig.proposeAction(hash,address(conversionModule),r.selector,r.calldataHash,"Resquat",block.timestamp+7 days);
        vm.prank(owner); adminMultisig.proposeAction(hash,r.consumer,r.selector,r.calldataHash,"Renew repaired intent",block.timestamp+7 days);
        assertEq(adminMultisig.proposalVersion(hash),3);
    }
    function testF05RepairClearsOldApprovalsAndCannotReplayGeneration() public {
        bytes32 hash=keccak256("old-approvals"); _squat(hash);
        vm.prank(signer3); adminMultisig.approveActionForConsumer(hash,address(conversionModule));
        IAdminMultisig.ProposalReplacement memory r=_replacement(hash); _repair(r);
        (uint256 count,bool consumed,bool exists)=adminMultisig.getApprovalState(hash);
        assertEq(count,0); assertFalse(consumed); assertFalse(exists);
        assertFalse(adminMultisig.hasApprovedAction(hash,signer3));
        vm.prank(owner); vm.expectRevert("Proposal changed"); adminMultisig.approveProposalReplacement(r);
    }
    function testF05DifferentReplacementPayloadsDoNotCombineVotes() public {
        bytes32 hash=keccak256("split-votes"); _squat(hash);
        IAdminMultisig.ProposalReplacement memory r=_replacement(hash);
        vm.prank(owner); adminMultisig.approveProposalReplacement(r);
        r.calldataHash=keccak256("other-data");
        vm.prank(signer2); adminMultisig.approveProposalReplacement(r);
        (,,address consumer,,,,,)=adminMultisig.getActionProposal(hash); assertEq(consumer,address(conversionModule));
    }
    function testF05ExpiredRenewalInvalidatesPendingReplacementVotes() public {
        bytes32 hash=keccak256("stale-votes"); _squat(hash);
        IAdminMultisig.ProposalReplacement memory r=_replacement(hash);
        vm.prank(owner); adminMultisig.approveProposalReplacement(r);
        vm.warp(r.deadline+1); _squat(hash);
        vm.prank(signer2); vm.expectRevert("Proposal changed"); adminMultisig.approveProposalReplacement(r);
    }
    function testF05NonSignerCannotRepairAndConsumedActionCannotBeReopened() public {
        uint256 id=_recordBSA(alice,185,100); bytes32 reason=keccak256("cancel");
        bytes32 hash=bsaRegistry.getCancelBSAActionHash(id,reason); _squat(hash);
        IAdminMultisig.ProposalReplacement memory r=_replacement(hash);
        r.calldataHash=keccak256(abi.encodeCall(bsaRegistry.cancelBSA,(id,reason)));
        vm.prank(mallory); vm.expectRevert("Caller is not signer"); adminMultisig.approveProposalReplacement(r);
        _repair(r); _approveActionForConsumerByTwoSigners(hash,address(bsaRegistry));
        vm.prank(owner); bsaRegistry.cancelBSA(id,reason);
        r.expectedFingerprint=adminMultisig.getActionProposalFingerprint(hash);
        vm.prank(owner); vm.expectRevert("Action already consumed"); adminMultisig.approveProposalReplacement(r);
    }
    function testF05SignerRotationInvalidatesRepairVotes() public {
        bytes32 hash=keccak256("rotation-votes"); _squat(hash);
        IAdminMultisig.ProposalReplacement memory r=_replacement(hash);
        vm.prank(owner); adminMultisig.approveProposalReplacement(r);
        bytes32 rotation=adminMultisig.getReplaceSignerActionHash(signer3,newSigner,SIGNER_ROTATION_REF);
        _approveActionForConsumerByTwoSigners(rotation,address(adminMultisig));
        vm.prank(owner); adminMultisig.replaceSigner(signer3,newSigner,SIGNER_ROTATION_REF);
        vm.prank(signer2); adminMultisig.approveProposalReplacement(r);
        (,,address consumer,,,,,)=adminMultisig.getActionProposal(hash); assertEq(consumer,address(conversionModule));
        vm.prank(owner); adminMultisig.approveProposalReplacement(r);
        (,,consumer,,,,,)=adminMultisig.getActionProposal(hash); assertEq(consumer,address(bsaRegistry));
    }

    function testN05DelayStartsAtSecondSignatureNotProposalOrFirstSignature() public {
        _awardIQS(alice,50); bytes32 hash=_migrationHash(); _proposeTestAction(hash,address(holderMigrationController));
        vm.prank(owner); adminMultisig.approveActionForConsumer(hash,address(holderMigrationController));
        vm.warp(block.timestamp+3 days);
        assertEq(holderMigrationController.migrationReadyAt(alice,aliceNewWallet,MIGRATION_REF),0);
        vm.prank(signer2); adminMultisig.approveActionForConsumer(hash,address(holderMigrationController));
        uint256 ready=holderMigrationController.migrationReadyAt(alice,aliceNewWallet,MIGRATION_REF);
        assertEq(ready,block.timestamp+48 hours);
        vm.expectRevert("Migration delay not elapsed"); _migrate();
        vm.warp(ready-1); vm.expectRevert("Migration delay not elapsed"); _migrate();
        vm.warp(ready); _migrate(); assertEq(tokenManager.balanceOfIQS(aliceNewWallet),50);
        assertFalse(adminMultisig.hasApprovedAction(hash,signer3));
    }
    function testN05RevokeAndReapproveRestartsDelay() public {
        _awardIQS(alice,50); uint256 ready=_approveMigration();
        vm.warp(ready-1); vm.prank(signer2); adminMultisig.revokeApproval(_migrationHash());
        assertEq(holderMigrationController.migrationReadyAt(alice,aliceNewWallet,MIGRATION_REF),0);
        vm.prank(signer2); adminMultisig.approveActionForConsumer(_migrationHash(),address(holderMigrationController));
        uint256 newReady=holderMigrationController.migrationReadyAt(alice,aliceNewWallet,MIGRATION_REF);
        assertEq(newReady,block.timestamp+48 hours); assertGt(newReady,ready);
        vm.warp(ready); vm.expectRevert("Migration delay not elapsed"); _migrate();
        vm.warp(newReady); _migrate();
    }
    function testN05OneSignerCannotAbortButSeparateQuorumCan() public {
        _awardIQS(alice,50); uint256 ready=_approveMigration(); bytes32 reason=keccak256("abort"); bytes32 hash=_abortHash(reason);
        _proposeTestAction(hash,address(holderMigrationController));
        vm.prank(owner); adminMultisig.approveActionForConsumer(hash,address(holderMigrationController));
        vm.expectRevert("Action not approved"); _abort(reason);
        assertFalse(holderMigrationController.abortedMigrations(_migrationHash()));
        vm.prank(signer2); adminMultisig.approveActionForConsumer(hash,address(holderMigrationController));
        _abort(reason); _consumeState(hash,true);
        vm.warp(ready); vm.expectRevert("Migration aborted"); _migrate();
        assertEq(tokenManager.balanceOfIQS(alice),50); assertEq(tokenManager.balanceOfIQS(aliceNewWallet),0);
    }
    function testN05AbortBindsReasonAndCannotAbortExecutedMigration() public {
        _awardIQS(alice,50); uint256 ready=_approveMigration(); bytes32 reason=keccak256("abort");
        _approveActionForConsumerByTwoSigners(_abortHash(reason),address(holderMigrationController));
        vm.expectRevert("Action belongs to different consumer"); _abort(keccak256("other"));
        vm.warp(ready); _migrate();
        vm.expectRevert("Migration already executed"); _abort(reason);
        assertTrue(holderMigrationController.executedMigrations(_migrationHash()));
    }
    function testN05AbortAfterDelayBeforeExecutionStillWorks() public {
        _awardIQS(alice,50); uint256 ready=_approveMigration(); vm.warp(ready+1);
        bytes32 reason=keccak256("late-abort"); _approveActionForConsumerByTwoSigners(_abortHash(reason),address(holderMigrationController));
        _abort(reason); vm.expectRevert("Migration aborted"); _migrate();
    }
    function testN05ExpiredApprovalsCannotExecuteDespiteElapsedDelay() public {
        _awardIQS(alice,50); _approveMigration(); vm.warp(block.timestamp+7 days+1);
        vm.expectRevert("Action not approved"); _migrate();
    }
    function testN05FailedExecutionKeepsApprovalAndAllBalances() public {
        uint256 id=_reviewEscrow(); uint256 ready=_approveMigration(); vm.warp(ready);
        vm.expectRevert("Wallet has open OST transfers"); _migrate();
        _consumeState(_migrationHash(),false); assertEq(tokenManager.balanceOfOST(alice),70);
        assertEq(ostTransferModule.transfersf(id).seller,alice); assertFalse(tokenManager.retiredHolderWallet(alice));
    }
    function testN05NewAttemptAfterAbortRequiresNewDelay() public {
        _awardIQS(alice,50); uint256 ready=_approveMigration(); bytes32 reason=keccak256("abort");
        _approveActionForConsumerByTwoSigners(_abortHash(reason),address(holderMigrationController)); _abort(reason);
        vm.warp(ready); bytes32 refHash=keccak256("new-attempt");
        bytes32 hash=holderMigrationController.getHolderMigrationActionHash(alice,aliceNewWallet,refHash);
        _approveActionForConsumerByTwoSigners(hash,address(holderMigrationController));
        vm.prank(owner); vm.expectRevert("Migration delay not elapsed"); holderMigrationController.migrateHolder(alice,aliceNewWallet,refHash);
        vm.warp(block.timestamp+48 hours); vm.prank(owner); holderMigrationController.migrateHolder(alice,aliceNewWallet,refHash);
        assertEq(tokenManager.balanceOfIQS(aliceNewWallet),50);
    }

    function testN05SignerRotationInvalidatesTheOldDelay() public {
        _awardIQS(alice,50); uint256 oldReady=_approveMigration(); vm.warp(oldReady-1);
        bytes32 rotation=adminMultisig.getReplaceSignerActionHash(signer3,newSigner,SIGNER_ROTATION_REF);
        _approveActionForConsumerByTwoSigners(rotation,address(adminMultisig));
        vm.prank(owner); adminMultisig.replaceSigner(signer3,newSigner,SIGNER_ROTATION_REF);
        assertEq(holderMigrationController.migrationReadyAt(alice,aliceNewWallet,MIGRATION_REF),0);
        uint256 newReady=_approveMigration(); assertEq(newReady,block.timestamp+48 hours);
        vm.warp(oldReady); vm.expectRevert("Migration delay not elapsed"); _migrate();
        vm.warp(newReady); _migrate();
    }
    function testN05RenewedProposalNeedsNewSignaturesAndDelay() public {
        _awardIQS(alice,50); _approveMigration();
        (, , , , , , , uint256 deadline)=adminMultisig.getActionProposal(_migrationHash());
        vm.warp(deadline+1); uint256 newReady=_approveMigration();
        assertEq(newReady,block.timestamp+48 hours);
        vm.expectRevert("Migration delay not elapsed"); _migrate();
        vm.warp(newReady); _migrate();
    }
    function testN05ThirdSignatureCannotAccelerateMigration() public {
        _awardIQS(alice,50); uint256 ready=_approveMigration(); vm.warp(ready-1);
        vm.prank(signer3); adminMultisig.approveActionForConsumer(_migrationHash(),address(holderMigrationController));
        assertEq(holderMigrationController.migrationReadyAt(alice,aliceNewWallet,MIGRATION_REF),ready);
        vm.expectRevert("Migration delay not elapsed"); _migrate();
        vm.warp(ready); _migrate();
    }
    function testF05RepairedSelectorAndCalldataCannotBeSquatted() public {
        bytes32 hash=keccak256("bound-metadata"); _squat(hash);
        IAdminMultisig.ProposalReplacement memory r=_replacement(hash); _repair(r); vm.warp(r.deadline+1);
        vm.prank(signer3); vm.expectRevert("Action intent fixed by quorum");
        adminMultisig.proposeAction(hash,r.consumer,bytes4(0x11223344),r.calldataHash,"Wrong selector",block.timestamp+7 days);
        vm.prank(signer3); vm.expectRevert("Action intent fixed by quorum");
        adminMultisig.proposeAction(hash,r.consumer,r.selector,keccak256("wrong-data"),"Wrong calldata",block.timestamp+7 days);
    }
}
