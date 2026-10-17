// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "../src/IQOS.sol";
import "../src/AccessControl.sol";
import "../src/TokenManager.sol";
import "../src/OSTTransferModule.sol";
import "../src/ConversionModule.sol";
import "../src/AdminMultisig.sol";
import "../src/BSARegistry.sol";
import "../src/IBSARegistry.sol";
import "../src/HashRegistry.sol";
import "../src/IOSTTransferModule.sol";
import "../src/IConversionModule.sol";
import "../src/ValuationAnchor.sol";
import "../src/IValuationAnchor.sol";
import "../src/GovernanceRegistry.sol";
import "../src/IGovernanceRegistry.sol";
import "../src/EmergencyController.sol";
import "../src/IEmergencyController.sol";
import "../src/HolderMigrationController.sol";
import "../src/IHolderMigrationController.sol";
import "../src/TokenOperatorController.sol";
import "../src/ITokenOperatorController.sol";

interface IReviewPausable {
    function unpause() external;
    function paused() external view returns (bool);
}

contract IQOSAMFTest is Test {
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
    bytes32 constant BSA_HASH = keccak256("bsa-reference-hash-only");
    bytes32 constant AWARD_REF = keccak256("iqs-award-reference-hash");
    bytes32 constant EXERCISE_REF = keccak256("exercise-reference-hash");
    bytes32 constant CAPITAL_PAYMENT_HASH = keccak256("capital-payment-hash");
    bytes32 constant RECEIPT_HASH = keccak256("receipt-hash");
    bytes32 constant TRANSFER_REF = keccak256("ost-transfer-reference-hash");
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

    /// @dev TEST-ONLY generic proposal. Production bridge must store exact
    ///      execution calldata hash, selector and a verified factual description.
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

    function _approveActionByAllSigners(bytes32 actionHash) internal {
        _proposeTestAction(actionHash, address(adminMultisig));
        vm.prank(owner);
        adminMultisig.approveAction(actionHash);

        vm.prank(signer2);
        adminMultisig.approveAction(actionHash);

        vm.prank(signer3);
        adminMultisig.approveAction(actionHash);
    }
    function _approveActionByTwoSigners(
        bytes32 actionHash
    )
        internal
    {
        _proposeTestAction(actionHash, address(adminMultisig));
        vm.prank(owner);
        adminMultisig.approveAction(
            actionHash
        );

        vm.prank(signer2);
        adminMultisig.approveAction(
            actionHash
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

    function _approveConfirmTransfer(uint256 id, bytes32 receiptHash) internal {
        bytes32 hash = ostTransferModule.getAdminConfirmOSTTransactionActionHash(id, receiptHash);
        if (!adminMultisig.isActionApproved(hash)) {
            _approveActionForConsumerByTwoSigners(hash, address(ostTransferModule));
        }
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

    function testInitialAMFDeployment() public view {
        assertEq(accessControl.owner(), owner);
        assertTrue(accessControl.isAdmin(owner));

        assertEq(tokenManager.totalSupplyIQS(), 0);
        assertEq(tokenManager.totalSupplyOSTf(), 0);
        assertEq(tokenManager.maxSupplyIQS(), type(uint256).max);
        assertEq(tokenManager.maxSupplyOSTf(), type(uint256).max);

        assertTrue(tokenManager.isTokenOperator(address(ostTransferModule)));
        assertTrue(tokenManager.isTokenOperator(address(conversionModule)));

        assertEq(adminMultisig.requiredSignatures(), 2);
        assertEq(accessControl.adminSignerController(), address(adminMultisig));
        assertTrue(accessControl.isAdmin(signer2));
        assertTrue(accessControl.isAdmin(signer3));
        assertTrue(adminMultisig.isSigner(owner));
        assertTrue(adminMultisig.isSigner(signer2));
        assertTrue(adminMultisig.isSigner(signer3));
        assertTrue(adminMultisig.isActionConsumer(address(conversionModule)));
    }
    function _approveHolderMigration(
        address oldWallet,
        address newWallet,
        bytes32 referenceHash
    ) internal returns (bytes32) {
        bytes32 actionHash =
            holderMigrationController.getHolderMigrationActionHash(
                oldWallet,
                newWallet,
                referenceHash
            );

        // N-05: default 2-of-3 quorum, then the full on-chain delay.
        _approveActionForConsumerByTwoSigners(
            actionHash,
            address(holderMigrationController)
        );

        vm.warp(vm.getBlockTimestamp() + holderMigrationController.MIGRATION_DELAY());
        return actionHash;
    }
    function testIQSAwardedDirectlyToHolderAndCountedInEscrow() public {
        _awardIQS(alice, 100);

        assertEq(tokenManager.balanceOfIQS(alice), 100);
        assertEq(tokenManager.totalSupplyIQS(), 100);
    }

    function testLegacyTreasuryMintIQSReverts() public {
        vm.prank(owner);
        vm.expectRevert("Use mintIQSTo under BSA");

        tokenManager.mintIQS(100);
    }

    function testIQSCannotBeTransferredSoldOrGiven() public {
        _awardIQS(alice, 100);
        _makeValidUser(bob);

        vm.prank(owner);
        vm.expectRevert("IQS is non-transferable");

        tokenManager.transferIQSfromAtoB(
            alice,
            bob,
            10
        );
    }

    function testExerciseIQSToOSTRequiresDoubleOwnerApproval() public {
        uint256 bsaId =
            _awardIQS(alice, 50);

        vm.prank(alice);

        uint256 requestId =
            conversionModule.requestExercise(
                bsaId,
                20,
                EXERCISE_REF
            );

        vm.prank(owner);
        conversionModule.approveExercise(requestId);

        vm.prank(owner);
        conversionModule.confirmCapitalReceived(
            requestId,
            CAPITAL_PAYMENT_HASH
        );

        bytes32 actionHash = conversionModule.getFinalizeExerciseActionHash(
            requestId,
            RECEIPT_HASH
        );

        _approveActionForConsumerByAllSigners(
            actionHash,
            address(conversionModule)
        );

        assertTrue(adminMultisig.isActionApproved(actionHash));

        vm.prank(owner);
        conversionModule.finalizeExercise(
            requestId,
            RECEIPT_HASH
        );

        IConversionModule.IQSExerciseRequest memory request =
            conversionModule.getExerciseRequest(requestId);
        assertEq(request.bsaId, bsaId);
        assertEq(request.strikePrice, 185);
        assertEq(request.capitalDue, 3_700);
        assertEq(request.bsaReferenceHash, BSA_HASH);
        assertEq(
            uint256(request.status),
            uint256(IConversionModule.ExerciseStatus.Settled)
        );

        assertEq(tokenManager.balanceOfIQS(alice), 30);
        assertEq(tokenManager.totalSupplyIQS(), 30);
        assertEq(tokenManager.balanceOfOST(alice), 20);
        assertEq(tokenManager.totalSupplyOSTf(), 20);

        (, bool consumed,) = adminMultisig.getApprovalState(actionHash);
        assertTrue(consumed);
    }

    function testCannotFinalizeExerciseWithOnlyOneOwnerApproval() public {
        uint256 bsaId =
            _awardIQS(alice, 50);

        vm.prank(alice);

        uint256 requestId =
            conversionModule.requestExercise(
                bsaId,
                20,
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

        _proposeTestAction(actionHash, address(conversionModule));


        vm.prank(owner);
        adminMultisig.approveActionForConsumer(
            actionHash,
            address(conversionModule)
        );

        vm.prank(owner);
        vm.expectRevert("Action not approved");

        conversionModule.finalizeExercise(
            requestId,
            RECEIPT_HASH
        );
    }

    function testWhitelistedOSTP2PTransferWithRegistrarRelease() public {
        _mintOST(alice, 100);
        _makeValidUser(bob);

        vm.prank(alice);

        uint256 transferId = ostTransferModule.createSellTransferRequest(
            alice,
            bob,
            30,
            210,
            TRANSFER_REF
        );

        vm.prank(bob);
        ostTransferModule.acceptTransfer(
            transferId,
            AGREEMENT_HASH
        );

        assertEq(tokenManager.balanceOfOST(alice), 70);
        assertEq(tokenManager.balanceOfOST(address(ostTransferModule)), 30);
        assertEq(tokenManager.balanceOfOST(bob), 0);

        IOSTTransferModule.OSTTransfer memory escrowedTransfer =
            ostTransferModule.transfersf(transferId);

        assertEq(
            uint256(escrowedTransfer.status),
            uint256(IOSTTransferModule.TransferStatus.Escrowed)
        );

        vm.prank(bob);
        ostTransferModule.registerBuyerPaymentProof(
            transferId,
            PAYMENT_PROOF_HASH
        );

        vm.prank(alice);
        ostTransferModule.sellerValidatePaymentReceipt(
            transferId,
            SELLER_RECEIPT_HASH
        );

        _approveConfirmTransfer(transferId, RECEIPT_HASH);
        vm.prank(owner);
        ostTransferModule.adminConfirmOSTTransaction(
            transferId,
            RECEIPT_HASH
        );

        IOSTTransferModule.OSTTransfer memory releasedTransfer =
            ostTransferModule.transfersf(transferId);

        assertEq(
            uint256(releasedTransfer.status),
            uint256(IOSTTransferModule.TransferStatus.Released)
        );

        assertEq(tokenManager.balanceOfOST(alice), 70);
        assertEq(tokenManager.balanceOfOST(bob), 30);
        assertEq(tokenManager.balanceOfOST(address(ostTransferModule)), 0);
        assertEq(releasedTransfer.receiptHash, RECEIPT_HASH);
    }

    function testAdminCanResolveDisputedOSTTransferBackToSeller() public {
        _mintOST(alice, 100);
        _makeValidUser(bob);

        vm.prank(alice);
        uint256 transferId = ostTransferModule.createSellTransferRequest(
            alice,
            bob,
            25,
            200,
            TRANSFER_REF
        );

        vm.prank(bob);
        ostTransferModule.acceptTransfer(transferId, AGREEMENT_HASH);

        vm.prank(bob);
        ostTransferModule.markTransferDisputed(
            transferId,
            keccak256("dispute-hash")
        );

        bytes32 resolutionHash = keccak256("resolution-hash");

        bytes32 actionHash = ostTransferModule.getAdminResolveTransferActionHash(
            transferId,
            false,
            resolutionHash,
            RECEIPT_HASH
        );

        _approveActionForConsumerByTwoSigners(
            actionHash,
            address(ostTransferModule)
        );

        vm.prank(owner);
        ostTransferModule.adminResolveTransfer(
            transferId,
            false,
            resolutionHash,
            RECEIPT_HASH
        );

        IOSTTransferModule.OSTTransfer memory returnedTransfer =
            ostTransferModule.transfersf(transferId);

        assertEq(
            uint256(returnedTransfer.status),
            uint256(IOSTTransferModule.TransferStatus.Returned)
        );

        assertEq(tokenManager.balanceOfOST(alice), 100);
        assertEq(tokenManager.balanceOfOST(bob), 0);
        assertEq(tokenManager.balanceOfOST(address(ostTransferModule)), 0);

        (, bool consumed,) = adminMultisig.getApprovalState(actionHash);
        assertTrue(consumed);
    }

    function testHashRegistryAnchorsOnlyHashAndMetadata() public {
        vm.prank(owner);

        hashRegistry.anchorHash(
            SAMPLE_HASH,
            "AMF_RECEIPT",
            1
        );

        (
            bool exists,
            address submitter,
            uint256 timestamp,
            string memory referenceType,
            uint256 referenceId
        ) = hashRegistry.getHashRecord(SAMPLE_HASH);

        assertTrue(exists);
        assertEq(submitter, owner);
        assertGt(timestamp, 0);
        assertEq(referenceType, "AMF_RECEIPT");
        assertEq(referenceId, 1);
    }
    function testPublishValuationAnchorRequiresDoubleOwnerApproval()public
    {
        uint256 referenceId = 1;

        bytes32 actionHash =
            valuationAnchor.getPublishValuationActionHash(
                PERIOD_Q3_2026,
                VALUATION_HASH,
                METHODOLOGY_HASH,
                referenceId,
                false,
                0
            );

        _approveActionForConsumerByAllSigners(
            actionHash,
            address(valuationAnchor)
        );

        vm.prank(owner);

        uint256 anchorId =
            valuationAnchor.publishQuarterlyValuation(
                PERIOD_Q3_2026,
                VALUATION_HASH,
                METHODOLOGY_HASH,
                referenceId
            );

        IValuationAnchor.ValuationAnchorRecord memory record =
            valuationAnchor.anchorsf(anchorId);

        assertEq(record.id, anchorId);
        assertEq(record.periodHash, PERIOD_Q3_2026);
        assertEq(record.valuationHash, VALUATION_HASH);
        assertEq(record.methodologyHash, METHODOLOGY_HASH);
        assertEq(record.referenceId, referenceId);
        assertEq(
            uint256(record.kind),
            uint256(IValuationAnchor.AnchorKind.Quarterly)
        );

        (
            bool exists,
            address submitter,
            uint256 timestamp,
            string memory referenceType,
            uint256 hashReferenceId
        ) =
            hashRegistry.getModuleHashRecord(
                address(valuationAnchor), VALUATION_HASH
            );

        assertTrue(exists);
        assertEq(submitter, address(valuationAnchor));
        assertGt(timestamp, 0);
        assertEq(referenceType, "VALUATION");
        assertEq(hashReferenceId, referenceId);

        (, bool consumed,) =
            adminMultisig.getApprovalState(actionHash);

        assertTrue(consumed);
    }
    function testCannotPublishValuationAnchorWithOnlyOneOwnerApproval()
    public
    {
        uint256 referenceId = 1;

        bytes32 actionHash =
            valuationAnchor.getPublishValuationActionHash(
                PERIOD_Q3_2026,
                VALUATION_HASH,
                METHODOLOGY_HASH,
                referenceId,
                false,
                0
            );

        _proposeTestAction(actionHash, address(valuationAnchor));


        vm.prank(owner);
        adminMultisig.approveActionForConsumer(
            actionHash,
            address(valuationAnchor)
        );

        vm.prank(owner);
        vm.expectRevert("Action not approved");

        valuationAnchor.publishQuarterlyValuation(
            PERIOD_Q3_2026,
            VALUATION_HASH,
            METHODOLOGY_HASH,
            referenceId
        );
    }
    function testGovernanceOutcomeWithPopulationIsAnchored()
    public
    {
        uint256[] memory answerIds =
            new uint256[](2);

        answerIds[0] = 11;
        answerIds[1] = 12;

        uint256[] memory votePowers =
            new uint256[](2);

        votePowers[0] = 800;
        votePowers[1] = 200;

        bytes32 actionHash = governanceRegistry.getRecordOutcomeActionHash(
            1, VOTE_METADATA_HASH, BALLOT_ROOT, 3, answerIds, votePowers,
            IGovernanceRegistry.VotingPopulation.IQSAndOSTHolders,
            IGovernanceRegistry.VotingPowerSource.IQSAndOST
        );
        _approveActionForConsumerByTwoSigners(actionHash, address(governanceRegistry));

        vm.prank(owner);

        uint256 outcomeId =
            governanceRegistry.recordOutcomeWithBallotRoot(
                1,
                VOTE_METADATA_HASH,
                BALLOT_ROOT,
                3,
                answerIds,
                votePowers,
                IGovernanceRegistry.VotingPopulation.IQSAndOSTHolders,
                IGovernanceRegistry.VotingPowerSource.IQSAndOST
            );

        IGovernanceRegistry.GovernanceOutcome memory outcome =
            governanceRegistry.outcomesf(outcomeId);

        assertEq(outcome.voteId, 1);
        assertEq(outcome.metadataHash, VOTE_METADATA_HASH);
        assertEq(governanceRegistry.ballotMerkleRootByVoteId(1), BALLOT_ROOT);
        assertEq(
            outcome.resultHash,
            governanceRegistry.calculateResultHashWithBallotRoot(
                1, VOTE_METADATA_HASH, BALLOT_ROOT, 3, answerIds, votePowers,
                IGovernanceRegistry.VotingPopulation.IQSAndOSTHolders,
                IGovernanceRegistry.VotingPowerSource.IQSAndOST
            )
        );
        assertEq(outcome.participantCount, 3);
        assertEq(outcome.answerIds.length, 2);
        assertEq(outcome.votePowers.length, 2);
        assertEq(outcome.answerIds[0], 11);
        assertEq(outcome.answerIds[1], 12);
        assertEq(outcome.votePowers[0], 800);
        assertEq(outcome.votePowers[1], 200);

        assertEq(
            uint256(outcome.population),
            uint256(IGovernanceRegistry.VotingPopulation.IQSAndOSTHolders)
        );

        assertEq(
            uint256(outcome.powerSource),
            uint256(IGovernanceRegistry.VotingPowerSource.IQSAndOST)
        );

        (
            bool exists,
            address submitter,
            uint256 timestamp,
            string memory referenceType,
            uint256 referenceId
        ) =
            hashRegistry.getModuleHashRecord(
                address(governanceRegistry), outcome.resultHash
            );

        assertTrue(exists);
        assertEq(submitter, address(governanceRegistry));
        assertGt(timestamp, 0);
        assertEq(referenceType, "VOTE_RESULT");
        assertEq(referenceId, 1);
    }
    function testCannotRecordSameVoteOutcomeTwice()
    public
    {
        uint256[] memory answerIds =
            new uint256[](2);

        answerIds[0] = 11;
        answerIds[1] = 12;

        uint256[] memory votePowers =
            new uint256[](2);

        votePowers[0] = 800;
        votePowers[1] = 200;

        bytes32 actionHash = governanceRegistry.getRecordOutcomeActionHash(
            1, VOTE_METADATA_HASH, BALLOT_ROOT, 3, answerIds, votePowers,
            IGovernanceRegistry.VotingPopulation.IQSAndOSTHolders,
            IGovernanceRegistry.VotingPowerSource.IQSAndOST
        );
        _approveActionForConsumerByTwoSigners(actionHash, address(governanceRegistry));

        vm.prank(owner);

        governanceRegistry.recordOutcomeWithBallotRoot(
            1,
            VOTE_METADATA_HASH,
            BALLOT_ROOT,
            3,
            answerIds,
            votePowers,
            IGovernanceRegistry.VotingPopulation.IQSAndOSTHolders,
            IGovernanceRegistry.VotingPowerSource.IQSAndOST
        );

        vm.prank(owner);
        vm.expectRevert("Vote outcome already recorded");

        governanceRegistry.recordOutcomeWithBallotRoot(
            1,
            VOTE_METADATA_HASH,
            BALLOT_ROOT,
            3,
            answerIds,
            votePowers,
            IGovernanceRegistry.VotingPopulation.IQSAndOSTHolders,
            IGovernanceRegistry.VotingPowerSource.IQSAndOST
        );
    }
    function testM5GovernanceRejectsLegacyOutcomeEntryPoints() public {
        uint256[] memory answerIds = new uint256[](1);
        uint256[] memory powers = new uint256[](1);
        answerIds[0] = 1;
        powers[0] = 10;
        vm.prank(owner);
        vm.expectRevert("Use ballot-root outcome API");
        governanceRegistry.recordOutcome(11, VOTE_METADATA_HASH, 1, answerIds, powers);
        vm.prank(owner);
        vm.expectRevert("Use ballot-root outcome API");
        governanceRegistry.recordOutcomeWithPopulation(
            11, VOTE_METADATA_HASH, 1, answerIds, powers,
            IGovernanceRegistry.VotingPopulation.IQSAndOSTHolders,
            IGovernanceRegistry.VotingPowerSource.IQSAndOST
        );
    }

    function testM5GovernanceCannotRecordWithoutCorrectConsumerApproval() public {
        uint256[] memory answers = new uint256[](1);
        uint256[] memory powers = new uint256[](1);
        answers[0] = 1;
        powers[0] = 10;
        vm.prank(owner);
        vm.expectRevert("Action belongs to different consumer");
        governanceRegistry.recordOutcomeWithBallotRoot(
            12, VOTE_METADATA_HASH, BALLOT_ROOT, 1, answers, powers,
            IGovernanceRegistry.VotingPopulation.IQSAndOSTHolders,
            IGovernanceRegistry.VotingPowerSource.IQSAndOST
        );
        bytes32 actionHash = governanceRegistry.getRecordOutcomeActionHash(
            12, VOTE_METADATA_HASH, BALLOT_ROOT, 1, answers, powers,
            IGovernanceRegistry.VotingPopulation.IQSAndOSTHolders,
            IGovernanceRegistry.VotingPowerSource.IQSAndOST
        );
        _proposeTestAction(actionHash, address(governanceRegistry));

        vm.prank(owner);
        adminMultisig.approveActionForConsumer(actionHash, address(governanceRegistry));
        vm.prank(owner);
        vm.expectRevert("Action not approved");
        governanceRegistry.recordOutcomeWithBallotRoot(
            12, VOTE_METADATA_HASH, BALLOT_ROOT, 1, answers, powers,
            IGovernanceRegistry.VotingPopulation.IQSAndOSTHolders,
            IGovernanceRegistry.VotingPowerSource.IQSAndOST
        );
        assertFalse(governanceRegistry.isVoteOutcomeRecorded(12));
    }

    function testM5GovernanceCannotSubstituteBallotRootAfterApproval() public {
        uint256[] memory answers = new uint256[](1);
        uint256[] memory powers = new uint256[](1);
        answers[0] = 1;
        powers[0] = 10;
        bytes32 actionHash = governanceRegistry.getRecordOutcomeActionHash(
            13, VOTE_METADATA_HASH, BALLOT_ROOT, 1, answers, powers,
            IGovernanceRegistry.VotingPopulation.IQSAndOSTHolders,
            IGovernanceRegistry.VotingPowerSource.IQSAndOST
        );
        _approveActionForConsumerByTwoSigners(actionHash, address(governanceRegistry));
        vm.prank(owner);
        vm.expectRevert("Action belongs to different consumer");
        governanceRegistry.recordOutcomeWithBallotRoot(
            13, VOTE_METADATA_HASH, keccak256("substituted-root"), 1, answers, powers,
            IGovernanceRegistry.VotingPopulation.IQSAndOSTHolders,
            IGovernanceRegistry.VotingPowerSource.IQSAndOST
        );
        assertFalse(governanceRegistry.isVoteOutcomeRecorded(13));
        (, bool consumed,) = adminMultisig.getApprovalState(actionHash);
        assertFalse(consumed);
    }

    function testM5GovernanceRequiresBallotRoot() public {
        uint256[] memory answers = new uint256[](1);
        uint256[] memory powers = new uint256[](1);
        answers[0] = 1;
        powers[0] = 10;
        vm.prank(owner);
        vm.expectRevert("Ballot root required");
        governanceRegistry.recordOutcomeWithBallotRoot(
            14, VOTE_METADATA_HASH, bytes32(0), 1, answers, powers,
            IGovernanceRegistry.VotingPopulation.IQSAndOSTHolders,
            IGovernanceRegistry.VotingPowerSource.IQSAndOST
        );
    }

    function testEmergencyCannotUnpauseWithoutMultisigApproval()
        public
    {
        vm.prank(owner);
        vm.expectRevert("Action belongs to different consumer");

        emergencyController.unpauseTransactions(
            EMERGENCY_TRANSACTIONS_REF
        );

        assertFalse(
            ostTransferModule.paused()
        );
    }

    function testEmergencyCannotUnpauseWithOnlyOneSignature()
        public
    {
        bytes32 actionHash =
            emergencyController.getEmergencyActionHash(
                IEmergencyController.EmergencyScope.Transactions,
                false,
                EMERGENCY_TRANSACTIONS_REF
            );

        _proposeTestAction(actionHash, address(emergencyController));


        vm.prank(owner);
        adminMultisig.approveActionForConsumer(
            actionHash,
            address(emergencyController)
        );

        vm.prank(owner);
        vm.expectRevert("Action not approved");

        emergencyController.unpauseTransactions(
            EMERGENCY_TRANSACTIONS_REF
        );

        assertFalse(
            ostTransferModule.paused()
        );
    }

    function testEmergencyPauseIsImmediateAndUnpauseRequiresMultisig()
        public
    {
        bytes32 pauseHash =
            emergencyController.getEmergencyActionHash(
                IEmergencyController.EmergencyScope.All,
                true,
                EMERGENCY_PAUSE_ALL_REF
            );

        _approveActionForConsumerByTwoSigners(
            pauseHash,
            address(emergencyController)
        );

        vm.prank(owner);
        emergencyController.pauseAll(
            EMERGENCY_PAUSE_ALL_REF
        );

        IEmergencyController.EmergencyStatus memory pausedStatus =
            emergencyController.getEmergencyStatus();

        assertTrue(pausedStatus.tokenManagerPaused);
        assertTrue(pausedStatus.bsaRegistryPaused);
        assertTrue(pausedStatus.conversionModulePaused);
        assertTrue(pausedStatus.ostTransferModulePaused);
        assertTrue(pausedStatus.valuationAnchorPaused);
        assertTrue(pausedStatus.governanceRegistryPaused);

        (
            uint256 pauseApprovalCount,
            bool pauseConsumed,
            bool pauseExists
        ) = adminMultisig.getApprovalState(
            pauseHash
        );

        assertEq(
            pauseApprovalCount,
            2
        );
        assertFalse(
            pauseConsumed
        );
        assertTrue(
            pauseExists
        );

        bytes32 unpauseHash =
            emergencyController.getEmergencyActionHash(
                IEmergencyController.EmergencyScope.All,
                false,
                EMERGENCY_UNPAUSE_ALL_REF
            );

        _approveActionForConsumerByTwoSigners(
            unpauseHash,
            address(emergencyController)
        );

        vm.prank(owner);
        emergencyController.unpauseAll(
            EMERGENCY_UNPAUSE_ALL_REF
        );

        IEmergencyController.EmergencyStatus memory runningStatus =
            emergencyController.getEmergencyStatus();

        assertFalse(runningStatus.tokenManagerPaused);
        assertFalse(runningStatus.bsaRegistryPaused);
        assertFalse(runningStatus.conversionModulePaused);
        assertFalse(runningStatus.ostTransferModulePaused);
        assertFalse(runningStatus.valuationAnchorPaused);
        assertFalse(runningStatus.governanceRegistryPaused);

        (
            uint256 unpauseApprovalCount,
            bool unpauseConsumed,
            bool unpauseExists
        ) = adminMultisig.getApprovalState(
            unpauseHash
        );

        assertEq(
            unpauseApprovalCount,
            2
        );
        assertTrue(
            unpauseConsumed
        );
        assertTrue(
            unpauseExists
        );
    }

    function testEmergencyActionHashChangesWithReferenceHash()
        public
        view
    {
        bytes32 firstReference =
            keccak256("emergency-cycle-1");

        bytes32 secondReference =
            keccak256("emergency-cycle-2");

        bytes32 firstHash =
            emergencyController.getEmergencyActionHash(
                IEmergencyController.EmergencyScope.All,
                true,
                firstReference
            );

        bytes32 secondHash =
            emergencyController.getEmergencyActionHash(
                IEmergencyController.EmergencyScope.All,
                true,
                secondReference
            );

        assertTrue(
            firstHash != secondHash
        );
    }

    function testNonAdminCannotPauseTransactions()
        public
    {
        vm.prank(mallory);
        vm.expectRevert("Caller is not an admin");

        emergencyController.pauseTransactions(
            EMERGENCY_TRANSACTIONS_REF
        );
    }

    function testEmergencyPauseDistributionBlocksIQSCredit()
        public
    {
        uint256 bsaId =
            _recordBSA(
                alice,
                185,
                100
            );

        bytes32 actionHash =
            emergencyController.getEmergencyActionHash(
                IEmergencyController.EmergencyScope.Distribution,
                true,
                EMERGENCY_DISTRIBUTION_REF
            );

        _approveActionForConsumerByTwoSigners(
            actionHash,
            address(emergencyController)
        );

        vm.prank(owner);
        emergencyController.pauseDistribution(
            EMERGENCY_DISTRIBUTION_REF
        );

        assertTrue(
            bsaRegistry.paused()
        );

        _approveActionForConsumerByTwoSigners(bsaRegistry.getCreditIQSActionHash(bsaId, 10, AWARD_REF), address(bsaRegistry));
    vm.prank(owner);
        vm.expectRevert();

        bsaRegistry.creditIQS(
            bsaId,
            10,
            AWARD_REF
        );
    }

    function testEmergencyPauseConversionsBlocksExerciseRequest()
        public
    {
        uint256 bsaId =
            _awardIQS(
                alice,
                50
            );

        bytes32 actionHash =
            emergencyController.getEmergencyActionHash(
                IEmergencyController.EmergencyScope.Conversions,
                true,
                EMERGENCY_CONVERSIONS_REF
            );

        _approveActionForConsumerByTwoSigners(
            actionHash,
            address(emergencyController)
        );

        vm.prank(owner);
        emergencyController.pauseConversions(
            EMERGENCY_CONVERSIONS_REF
        );

        assertTrue(
            conversionModule.paused()
        );

        vm.prank(alice);
        vm.expectRevert();

        conversionModule.requestExercise(
            bsaId,
            10,
            EXERCISE_REF
        );
    }

    function testEmergencyPauseTransactionsBlocksOSTTransfer()
        public
    {
        _mintOST(
            alice,
            100
        );

        _makeValidUser(
            bob
        );

        bytes32 actionHash =
            emergencyController.getEmergencyActionHash(
                IEmergencyController.EmergencyScope.Transactions,
                true,
                EMERGENCY_TRANSACTIONS_REF
            );

        _approveActionForConsumerByTwoSigners(
            actionHash,
            address(emergencyController)
        );

        vm.prank(owner);
        emergencyController.pauseTransactions(
            EMERGENCY_TRANSACTIONS_REF
        );

        assertTrue(
            ostTransferModule.paused()
        );

        vm.prank(alice);
        vm.expectRevert();

        ostTransferModule.createSellTransferRequest(
            alice,
            bob,
            10,
            200,
            TRANSFER_REF
        );
    }

    function testHolderMigrationUsesQuorumAndOnChainDelay()
    public
    {
        _awardIQS(alice, 50);
        _mintOST(alice, 30);

        _approveHolderMigration(
            alice,
            aliceNewWallet,
            MIGRATION_REF
        );

        vm.prank(owner);

        uint256 migrationId =
            holderMigrationController.migrateHolder(
                alice,
                aliceNewWallet,
                MIGRATION_REF
            );

        IHolderMigrationController.HolderMigration memory migration =
            holderMigrationController.migrationsf(migrationId);

        assertEq(migration.oldWallet, alice);
        assertEq(migration.newWallet, aliceNewWallet);
        assertEq(migration.referenceHash, MIGRATION_REF);

        assertEq(tokenManager.balanceOfIQS(alice), 0);
        assertEq(tokenManager.balanceOfOST(alice), 0);

        assertEq(tokenManager.balanceOfIQS(aliceNewWallet), 50);
        assertEq(tokenManager.balanceOfOST(aliceNewWallet), 30);

        (, bool consumed,) =
            adminMultisig.getApprovalState(
                holderMigrationController.getHolderMigrationActionHash(
                    alice,
                    aliceNewWallet,
                    MIGRATION_REF
                )
            );

        assertTrue(consumed);
    }
    function testCannotMigrateHolderWithOnlyOneOwnerApproval()
    public
    {
        _awardIQS(alice, 50);

        bytes32 actionHash =
            holderMigrationController.getHolderMigrationActionHash(
                alice,
                aliceNewWallet,
                MIGRATION_REF
            );

        _proposeTestAction(actionHash, address(holderMigrationController));


        vm.prank(owner);
        adminMultisig.approveActionForConsumer(
            actionHash,
            address(holderMigrationController)
        );

        vm.prank(owner);
        vm.expectRevert("Action not approved");

        holderMigrationController.migrateHolder(
            alice,
            aliceNewWallet,
            MIGRATION_REF
        );
    }
    function testHolderMigrationRequiresTwoSignersAnd48Hours() public {
        _awardIQS(alice, 50);
        bytes32 hash = holderMigrationController.getHolderMigrationActionHash(alice, aliceNewWallet, MIGRATION_REF);
        _approveActionForConsumerByTwoSigners(hash, address(holderMigrationController));
        vm.prank(owner);
        vm.expectRevert("Migration delay not elapsed");
        holderMigrationController.migrateHolder(alice, aliceNewWallet, MIGRATION_REF);
        uint256 ready = holderMigrationController.migrationReadyAt(alice, aliceNewWallet, MIGRATION_REF);
        vm.warp(ready - 1);
        vm.prank(owner);
        vm.expectRevert("Migration delay not elapsed");
        holderMigrationController.migrateHolder(alice, aliceNewWallet, MIGRATION_REF);
        vm.warp(ready);
        vm.prank(owner);
        holderMigrationController.migrateHolder(alice, aliceNewWallet, MIGRATION_REF);
        assertEq(tokenManager.balanceOfIQS(aliceNewWallet), 50);
        (, bool consumed,) = adminMultisig.getApprovalState(hash);
        assertTrue(consumed);
    }

    function testDirectTokenManagerHolderMigrationIsBlocked()
    public
    {
        _awardIQS(alice, 50);

        vm.prank(owner);
        vm.expectRevert("Caller is not wallet migration controller");

        tokenManager.adminMigrateWallet(
            alice,
            aliceNewWallet,
            MIGRATION_REF
        );
    }
    function testDirectAdminTokenOperationsAreBlocked()
    public
    {
        _makeValidUser(alice);

        vm.prank(owner);
        vm.expectRevert("Caller is not a token operator");

        tokenManager.mintIQSTo(
            alice,
            10,
            AWARD_REF
        );

        vm.prank(owner);
        vm.expectRevert("Caller is not a token operator");

        tokenManager.mintOSTTo(
            alice,
            10,
            RECEIPT_HASH
        );

        vm.prank(owner);
        vm.expectRevert("Caller is not a token operator");

        tokenManager.transferOSTfromAtoB(
            alice,
            bob,
            10
        );
    }
    function testDirectAdminCannotSetTokenOperatorAfterControllerLocked()
    public
    {
        vm.prank(owner);
        vm.expectRevert("Caller is not token operator controller");

        tokenManager.setTokenOperator(
            mallory,
            true
        );
    }
    function testTokenOperatorChangeRequiresDoubleOwnerApproval()
    public
    {
        bytes32 actionHash =
            tokenOperatorController.getSetTokenOperatorActionHash(
                mallory,
                true,
                TOKEN_OPERATOR_REF
            );

        _approveActionForConsumerByAllSigners(
            actionHash,
            address(tokenOperatorController)
        );

        vm.prank(owner);

        uint256 changeId =
            tokenOperatorController.setTokenOperator(
                mallory,
                true,
                TOKEN_OPERATOR_REF
            );

        ITokenOperatorController.TokenOperatorChange memory change =
            tokenOperatorController.changesf(changeId);

        assertEq(change.operator, mallory);
        assertTrue(change.status);
        assertEq(change.referenceHash, TOKEN_OPERATOR_REF);
        assertTrue(tokenManager.isTokenOperator(mallory));

        (, bool consumed,) =
            adminMultisig.getApprovalState(actionHash);

        assertTrue(consumed);
    }
    function testCannotChangeTokenOperatorWithOnlyOneSignature()
    public
    {
        bytes32 actionHash =
            tokenOperatorController.getSetTokenOperatorActionHash(
                mallory,
                true,
                TOKEN_OPERATOR_REF
            );

        _proposeTestAction(actionHash, address(tokenOperatorController));


        vm.prank(owner);
        adminMultisig.approveActionForConsumer(
            actionHash,
            address(tokenOperatorController)
        );

        vm.prank(owner);
        vm.expectRevert("Action not approved");

        tokenOperatorController.setTokenOperator(
            mallory,
            true,
            TOKEN_OPERATOR_REF
        );
    }
    function testActionConsumerBootstrapIsLockedAfterSetup()
    public
{
    assertTrue(adminMultisig.actionConsumerBootstrapLocked());

    vm.prank(owner);
    vm.expectRevert("Action consumer bootstrap is locked");

    adminMultisig.setActionConsumer(
        mallory,
        true
    );
}
function testActionConsumerChangeRequiresDoubleOwnerApproval()
    public
{
    bytes32 actionHash =
        adminMultisig.getSetActionConsumerActionHash(
            mallory,
            true,
            ACTION_CONSUMER_REF
        );

    _approveActionByAllSigners(actionHash);

    vm.prank(owner);

    adminMultisig.setActionConsumerWithApproval(
        mallory,
        true,
        ACTION_CONSUMER_REF
    );

    assertTrue(
        adminMultisig.isActionConsumer(mallory)
    );

    (, bool consumed,) =
        adminMultisig.getApprovalState(actionHash);

    assertTrue(consumed);
}
function testCannotChangeActionConsumerWithOnlyOneSignature()
    public
{
    bytes32 actionHash =
        adminMultisig.getSetActionConsumerActionHash(
            mallory,
            true,
            ACTION_CONSUMER_REF
        );

    _proposeTestAction(actionHash, address(adminMultisig));


    vm.prank(owner);
    adminMultisig.approveAction(actionHash);

    vm.prank(owner);
    vm.expectRevert("Action not approved");

    adminMultisig.setActionConsumerWithApproval(
        mallory,
        true,
        ACTION_CONSUMER_REF
    );
}
function testOldSignerCannotApproveAfterRotation()
    public
{
    bytes32 rotationHash =
        adminMultisig.getReplaceSignerActionHash(
            signer3,
            newSigner,
            SIGNER_ROTATION_REF
        );

    _approveActionByAllSigners(rotationHash);

    vm.prank(owner);

    adminMultisig.replaceSigner(
        signer3,
        newSigner,
        SIGNER_ROTATION_REF
    );

    assertFalse(accessControl.isAdmin(signer3));
    assertTrue(accessControl.isAdmin(newSigner));

    bytes32 newActionHash =
        keccak256("new-action-after-signer-rotation");

    vm.prank(signer3);
    vm.expectRevert("Caller is not signer");

    adminMultisig.approveAction(
        newActionHash
    );

    _proposeTestAction(newActionHash, address(adminMultisig));


    vm.prank(newSigner);

    adminMultisig.approveAction(
        newActionHash
    );

    assertTrue(
        adminMultisig.hasApprovedAction(
            newActionHash,
            newSigner
        )
    );
}
function testRequiredSignaturesChangeRequiresDoubleOwnerApproval()
    public
{
    bytes32 actionHash =
        adminMultisig.getSetRequiredSignaturesActionHash(
            3,
            REQUIRED_SIGNATURES_REF
        );

    _approveActionByAllSigners(actionHash);

    vm.prank(owner);

    adminMultisig.setRequiredSignaturesWithApproval(
        3,
        REQUIRED_SIGNATURES_REF
    );

    assertEq(
        adminMultisig.requiredSignatures(),
        3
    );

    (, bool consumed,) =
        adminMultisig.getApprovalState(actionHash);

    assertTrue(consumed);
}
function testFinalCoreRegistryAndSecurityLocks()
    public
    view
{
    
    assertEq(address(iqos.accessControl()), address(accessControl));
    assertEq(address(iqos.tokenManager()), address(tokenManager));
    assertEq(address(iqos.ostTransferModule()), address(ostTransferModule));
    assertEq(address(iqos.conversionModule()), address(conversionModule));
    assertEq(address(iqos.hashRegistry()), address(hashRegistry));
    assertEq(address(iqos.adminMultisig()), address(adminMultisig));
    assertEq(address(iqos.bsaRegistry()), address(bsaRegistry));
    assertEq(address(iqos.valuationAnchor()), address(valuationAnchor));
    assertEq(address(iqos.governanceRegistry()), address(governanceRegistry));
    assertEq(address(iqos.emergencyController()), address(emergencyController));
    assertEq(address(iqos.holderMigrationController()), address(holderMigrationController));
    assertEq(address(iqos.tokenOperatorController()), address(tokenOperatorController));
    assertTrue(adminMultisig.isActionConsumer(address(ostTransferModule)));
    assertTrue(adminMultisig.actionConsumerBootstrapLocked());
    assertEq(accessControl.adminSignerController(), address(adminMultisig));
    assertTrue(
        adminMultisig.isActionConsumer(
            address(emergencyController)
        )
    );
    assertEq(
        tokenManager.walletMigrationController(),
        address(holderMigrationController)
    );

    assertEq(
        bsaRegistry.holderMigrationController(),
        address(holderMigrationController)
    );

    assertEq(
        tokenManager.tokenOperatorController(),
        address(tokenOperatorController)
    );

    assertTrue(tokenManager.isTokenOperator(address(bsaRegistry)));
    assertTrue(tokenManager.isTokenOperator(address(conversionModule)));
    assertTrue(tokenManager.isTokenOperator(address(ostTransferModule)));

    assertTrue(adminMultisig.isActionConsumer(address(conversionModule)));
    assertTrue(adminMultisig.isActionConsumer(address(valuationAnchor)));
    assertTrue(adminMultisig.isActionConsumer(address(holderMigrationController)));
    assertTrue(adminMultisig.isActionConsumer(address(tokenOperatorController)));
}
function testCannotRepointWalletMigrationController()
    public
{
    assertEq(
        tokenManager.walletMigrationController(),
        address(holderMigrationController)
    );

    vm.prank(owner);

    vm.expectRevert(
        "Wallet migration controller already set"
    );

    tokenManager.setWalletMigrationController(
        address(0xDEAD)
    );

    assertEq(
        tokenManager.walletMigrationController(),
        address(holderMigrationController)
    );
}
function testHolderMigrationAlsoMigratesBSAAndNewWalletCanExercise() public {
    uint256 bsaId = _awardIQS(alice, 100);

    IBSARegistry.BSARecord memory beforeMigration = bsaRegistry.bsasf(bsaId);
    assertEq(beforeMigration.holder, alice);
    assertEq(uint256(beforeMigration.status), uint256(IBSARegistry.BSAStatus.Exhausted));
    assertEq(bsaRegistry.activeBSAOf(alice), 0);

    uint256[] memory oldWalletBSAIdsBefore = bsaRegistry.getBSAIdsOf(alice);
    assertEq(oldWalletBSAIdsBefore.length, 1);
    assertEq(oldWalletBSAIdsBefore[0], bsaId);

    _approveHolderMigration(alice, aliceNewWallet, MIGRATION_REF);

    vm.prank(owner);
    holderMigrationController.migrateHolder(alice, aliceNewWallet, MIGRATION_REF);

    IBSARegistry.BSARecord memory afterMigration = bsaRegistry.bsasf(bsaId);
    assertEq(afterMigration.holder, aliceNewWallet);

    assertEq(tokenManager.balanceOfIQS(alice), 0);
    assertEq(tokenManager.balanceOfIQS(aliceNewWallet), 100);

    uint256[] memory oldWalletBSAIdsAfter = bsaRegistry.getBSAIdsOf(alice);
    uint256[] memory newWalletBSAIdsAfter = bsaRegistry.getBSAIdsOf(aliceNewWallet);

    assertEq(oldWalletBSAIdsAfter.length, 0);
    assertEq(newWalletBSAIdsAfter.length, 1);
    assertEq(newWalletBSAIdsAfter[0], bsaId);

    assertEq(bsaRegistry.availableIQSToExercise(bsaId), 100);

    vm.prank(aliceNewWallet);
    uint256 requestId = conversionModule.requestExercise(bsaId, 25, keccak256("post-migration-exercise-ref"));

    IConversionModule.IQSExerciseRequest memory request = conversionModule.getExerciseRequest(requestId);
    assertEq(request.bsaId, bsaId);

    vm.prank(alice);
    vm.expectRevert();
    conversionModule.requestExercise(bsaId, 1, keccak256("old-wallet-must-not-exercise"));
}

function testAccessControlOwnershipTransferIsTwoStep() public {
    assertEq(accessControl.owner(), owner);
    assertEq(accessControl.pendingOwner(), address(0));

    vm.prank(owner);
    accessControl.transferOwnership(safeOwner);

    // Ownership must NOT change immediately.
    assertEq(accessControl.owner(), owner);
    assertEq(accessControl.pendingOwner(), safeOwner);

    // Random address cannot accept ownership.
    vm.prank(mallory);
    vm.expectRevert();
    accessControl.acceptOwnership();

    assertEq(accessControl.owner(), owner);
    assertEq(accessControl.pendingOwner(), safeOwner);

    // Safe accepts ownership in a separate transaction.
    vm.prank(safeOwner);
    accessControl.acceptOwnership();

    assertEq(accessControl.owner(), safeOwner);
    assertEq(accessControl.pendingOwner(), address(0));
}

function testDeployerCanBeFullyRemovedBeforeSafeOwnershipHandover() public {
    // Production deployment keeps the deployer separate from all multisig signers.
    address deployer = address(0xD3E0);
    address localSigner1 = address(0xD3E1);
    address localSigner2 = address(0xD3E2);
    address localSigner3 = address(0xD3E3);

    vm.startPrank(deployer);

    AccessControl localAccessControl = new AccessControl(deployer);
    localAccessControl.addAdmin(localSigner1);
    localAccessControl.addAdmin(localSigner2);
    localAccessControl.addAdmin(localSigner3);

    address[] memory localSigners = new address[](3);
    localSigners[0] = localSigner1;
    localSigners[1] = localSigner2;
    localSigners[2] = localSigner3;

    AdminMultisig localAdminMultisig = new AdminMultisig(
        address(localAccessControl),
        localSigners,
        2
    );

    localAccessControl.setAdminSignerController(address(localAdminMultisig));

    assertTrue(localAccessControl.isAdmin(deployer));
    assertTrue(localAccessControl.isAuthorized(deployer));
    assertTrue(localAccessControl.isWhiteListed(deployer));
    assertEq(localAccessControl.owner(), deployer);
    assertFalse(localAdminMultisig.isSigner(deployer));

    localAccessControl.revokeAuthorization(deployer);
    localAccessControl.removeFromWhiteList(deployer);
    localAccessControl.removeAdmin(deployer);
    localAccessControl.transferOwnership(safeOwner);

    vm.stopPrank();

    assertEq(localAccessControl.owner(), deployer);
    assertEq(localAccessControl.pendingOwner(), safeOwner);
    assertFalse(localAccessControl.isAdmin(deployer));
    assertFalse(localAccessControl.isAuthorized(deployer));
    assertFalse(localAccessControl.isWhiteListed(deployer));

    vm.prank(safeOwner);
    localAccessControl.acceptOwnership();

    assertEq(localAccessControl.owner(), safeOwner);
    assertEq(localAccessControl.pendingOwner(), address(0));

    vm.prank(deployer);
    vm.expectRevert();
    localAccessControl.addAdmin(address(0xDEAD));

    vm.prank(safeOwner);
    localAccessControl.addAdmin(address(0xDEAD));

    assertTrue(localAccessControl.isAdmin(address(0xDEAD)));
}

function testLostSignerCanBeReplacedByRemainingSigners() public {
    bytes32 actionHash = adminMultisig.getReplaceSignerActionHash(
        signer3,
        newSigner,
        SIGNER_ROTATION_REF
    );

    _proposeTestAction(actionHash, address(adminMultisig));


    vm.prank(owner);
    adminMultisig.approveAction(actionHash);

    vm.prank(signer2);
    adminMultisig.approveAction(actionHash);

    assertEq(
        adminMultisig.getApprovalCountExcluding(actionHash, signer3),
        2
    );

    vm.prank(owner);
    adminMultisig.replaceSigner(signer3, newSigner, SIGNER_ROTATION_REF);

    assertFalse(adminMultisig.isSigner(signer3));
    assertTrue(adminMultisig.isSigner(newSigner));
    assertFalse(accessControl.isAdmin(signer3));
    assertTrue(accessControl.isAdmin(newSigner));

    (, bool consumed,) = adminMultisig.getApprovalState(actionHash);
    assertTrue(consumed);
}
function testSignerBeingReplacedDoesNotCountTowardRecoveryThreshold() public {
    bytes32 actionHash = adminMultisig.getReplaceSignerActionHash(
        signer3,
        newSigner,
        SIGNER_ROTATION_REF
    );

    // One legitimate remaining signer.
    _proposeTestAction(actionHash, address(adminMultisig));

    vm.prank(owner);
    adminMultisig.approveAction(actionHash);

    // Signer being replaced also signs.
    vm.prank(signer3);
    adminMultisig.approveAction(actionHash);

    // Raw approval count is 2, but only one valid remaining signer approved.
    (uint256 approvalCount,,) = adminMultisig.getApprovalState(actionHash);
    assertEq(approvalCount, 2);

    assertEq(
        adminMultisig.getApprovalCountExcluding(actionHash, signer3),
        1
    );

    vm.prank(owner);
    vm.expectRevert("Action not approved by remaining signers");

    adminMultisig.replaceSigner(
        signer3,
        newSigner,
        SIGNER_ROTATION_REF
    );

    assertTrue(adminMultisig.isSigner(signer3));
    assertFalse(adminMultisig.isSigner(newSigner));
}
function testHolderMigrationWorksWithRequiredMultisigThreshold() public {
    _awardIQS(alice, 50);

    bytes32 actionHash = holderMigrationController.getHolderMigrationActionHash(
        alice,
        aliceNewWallet,
        MIGRATION_REF
    );

    _approveActionForConsumerByAllSigners(
            actionHash,
            address(holderMigrationController)
        );
    vm.warp(vm.getBlockTimestamp() + holderMigrationController.MIGRATION_DELAY());

    vm.prank(owner);
    holderMigrationController.migrateHolder(
        alice,
        aliceNewWallet,
        MIGRATION_REF
    );

    assertEq(tokenManager.balanceOfIQS(alice), 0);
    assertEq(tokenManager.balanceOfIQS(aliceNewWallet), 50);

    (, bool consumed,) = adminMultisig.getApprovalState(actionHash);
    assertTrue(consumed);
}
function testApprovalsFromPreviousSignerEpochDoNotCountAfterRotation() public {
    bytes32 staleActionHash = keccak256("action-created-before-rotation");

    _proposeTestAction(staleActionHash, address(adminMultisig));


    vm.prank(owner);
    adminMultisig.approveAction(staleActionHash);

    assertEq(adminMultisig.signerEpoch(), 1);

    bytes32 rotationHash = adminMultisig.getReplaceSignerActionHash(
        signer3,
        newSigner,
        SIGNER_ROTATION_REF
    );

    _proposeTestAction(rotationHash, address(adminMultisig));


    vm.prank(owner);
    adminMultisig.approveAction(rotationHash);

    vm.prank(signer2);
    adminMultisig.approveAction(rotationHash);

    vm.prank(owner);
    adminMultisig.replaceSigner(signer3, newSigner, SIGNER_ROTATION_REF);

    assertFalse(accessControl.isAdmin(signer3));
    assertTrue(accessControl.isAdmin(newSigner));
    assertEq(adminMultisig.signerEpoch(), 2);

    // Owner's old approval must no longer count.
    (uint256 approvalCount,,) = adminMultisig.getApprovalState(staleActionHash);
    assertEq(approvalCount, 0);

    assertFalse(
        adminMultisig.hasApprovedAction(
            staleActionHash,
            owner
        )
    );

    // New signer signs in current epoch.
    vm.prank(newSigner);
    adminMultisig.approveAction(staleActionHash);

    (approvalCount,,) = adminMultisig.getApprovalState(staleActionHash);

    // Must be ONE, not two.
    assertEq(approvalCount, 1);
}
function testSignerCanRevokePendingApproval() public {
    bytes32 actionHash = keccak256("revocable-action");

    _proposeTestAction(actionHash, address(adminMultisig));


    vm.prank(owner);
    adminMultisig.approveAction(actionHash);

    assertTrue(adminMultisig.hasApprovedAction(actionHash, owner));

    vm.prank(owner);
    adminMultisig.revokeApproval(actionHash);

    assertFalse(adminMultisig.hasApprovedAction(actionHash, owner));

    (uint256 approvalCount, bool consumed, bool exists) =
        adminMultisig.getApprovalState(actionHash);

    assertEq(approvalCount, 0);
    assertFalse(consumed);
    assertTrue(exists);
}
function testExpiredApprovalCannotBeConsumed() public {
    bytes32 actionHash = keccak256("expiring-action");

    _proposeTestAction(actionHash, address(adminMultisig));


    vm.prank(owner);
    adminMultisig.approveAction(actionHash);

    vm.prank(signer2);
    adminMultisig.approveAction(actionHash);

    assertTrue(adminMultisig.isActionApproved(actionHash));

    vm.warp(block.timestamp + adminMultisig.ACTION_APPROVAL_VALIDITY() + 1);

    assertFalse(adminMultisig.isActionApproved(actionHash));

    (uint256 approvalCount,,) = adminMultisig.getApprovalState(actionHash);
    assertEq(approvalCount, 0);
}
function testAdminCannotResolveOSTTransferWithoutMultisigApproval() public {
    _mintOST(alice, 100);
    _makeValidUser(bob);

    vm.prank(alice);
    uint256 transferId = ostTransferModule.createSellTransferRequest(
        alice,
        bob,
        25,
        200,
        TRANSFER_REF
    );

    vm.prank(bob);
    ostTransferModule.acceptTransfer(transferId, AGREEMENT_HASH);

    vm.prank(owner);
    vm.expectRevert("Action belongs to different consumer");

    ostTransferModule.adminResolveTransfer(
        transferId,
        true,
        keccak256("resolution-without-multisig"),
        RECEIPT_HASH
    );

    assertEq(tokenManager.balanceOfOST(bob), 0);
    assertEq(tokenManager.balanceOfOST(address(ostTransferModule)), 25);
}
function testAdminCreateAgreedTransferRequiresMultisig() public {
    _mintOST(alice, 100);
    _makeValidUser(bob);

    bytes32 referenceHash = keccak256("admin-created-transfer");
    bytes32 agreementHash = keccak256("admin-created-agreement");

    bytes32 actionHash = ostTransferModule.getAdminCreateAgreedSellTransferActionHash(
        alice,
        bob,
        30,
        200,
        referenceHash,
        agreementHash
    );

    vm.prank(owner);
    vm.expectRevert("Action belongs to different consumer");

    ostTransferModule.adminCreateAgreedSellTransferAndLockEscrow(
        alice,
        bob,
        30,
        200,
        referenceHash,
        agreementHash
    );

    _approveActionForConsumerByTwoSigners(
            actionHash,
            address(ostTransferModule)
        );

    vm.prank(owner);
    uint256 transferId = ostTransferModule.adminCreateAgreedSellTransferAndLockEscrow(
        alice,
        bob,
        30,
        200,
        referenceHash,
        agreementHash
    );

    IOSTTransferModule.OSTTransfer memory transfer =
        ostTransferModule.transfersf(transferId);

    assertEq(
        uint256(transfer.status),
        uint256(IOSTTransferModule.TransferStatus.Escrowed)
    );

    assertEq(tokenManager.balanceOfOST(alice), 70);
    assertEq(tokenManager.balanceOfOST(address(ostTransferModule)), 30);

    (, bool consumed,) = adminMultisig.getApprovalState(actionHash);
    assertTrue(consumed);
}
function testAdminAcceptTransferRequiresMultisig() public {
    _mintOST(alice, 100);
    _makeValidUser(bob);

    vm.prank(alice);
    uint256 transferId = ostTransferModule.createSellTransferRequest(
        alice,
        bob,
        20,
        200,
        TRANSFER_REF
    );

    bytes32 actionHash = ostTransferModule.getAdminAcceptTransferAndLockEscrowActionHash(
        transferId,
        AGREEMENT_HASH
    );

    vm.prank(owner);
    vm.expectRevert("Action belongs to different consumer");

    ostTransferModule.adminAcceptTransferAndLockEscrow(
        transferId,
        AGREEMENT_HASH
    );

    _approveActionForConsumerByTwoSigners(
            actionHash,
            address(ostTransferModule)
        );

    vm.prank(owner);
    ostTransferModule.adminAcceptTransferAndLockEscrow(
        transferId,
        AGREEMENT_HASH
    );

    IOSTTransferModule.OSTTransfer memory transfer =
        ostTransferModule.transfersf(transferId);

    assertEq(
        uint256(transfer.status),
        uint256(IOSTTransferModule.TransferStatus.Escrowed)
    );

    assertEq(tokenManager.balanceOfOST(alice), 80);
    assertEq(tokenManager.balanceOfOST(address(ostTransferModule)), 20);

    (, bool consumed,) = adminMultisig.getApprovalState(actionHash);
    assertTrue(consumed);
}
function testSellerEscrowCanBeReclaimedAfterDeadline() public {
    _mintOST(alice, 100);
    _makeValidUser(bob);

    vm.prank(alice);
    uint256 transferId = ostTransferModule.createSellTransferRequest(
        alice,
        bob,
        30,
        200,
        TRANSFER_REF
    );

    vm.prank(bob);
    ostTransferModule.acceptTransfer(transferId, AGREEMENT_HASH);

    IOSTTransferModule.OSTTransfer memory escrowed =
        ostTransferModule.transfersf(transferId);

    assertEq(tokenManager.balanceOfOST(alice), 70);
    assertEq(tokenManager.balanceOfOST(address(ostTransferModule)), 30);
    assertGt(escrowed.escrowDeadline, block.timestamp);

    vm.warp(escrowed.escrowDeadline + 1);

    vm.prank(mallory);
    ostTransferModule.reclaimExpiredEscrow(transferId);

    IOSTTransferModule.OSTTransfer memory returned =
        ostTransferModule.transfersf(transferId);

    assertEq(
        uint256(returned.status),
        uint256(IOSTTransferModule.TransferStatus.Returned)
    );

    assertEq(tokenManager.balanceOfOST(alice), 100);
    assertEq(tokenManager.balanceOfOST(address(ostTransferModule)), 0);
}
function testCannotReclaimEscrowBeforeDeadline() public {
    _mintOST(alice, 100);
    _makeValidUser(bob);

    vm.prank(alice);
    uint256 transferId = ostTransferModule.createSellTransferRequest(
        alice,
        bob,
        30,
        200,
        TRANSFER_REF
    );

    vm.prank(bob);
    ostTransferModule.acceptTransfer(transferId, AGREEMENT_HASH);

    vm.prank(mallory);
    vm.expectRevert("Escrow deadline not reached");

    ostTransferModule.reclaimExpiredEscrow(transferId);

    assertEq(tokenManager.balanceOfOST(alice), 70);
    assertEq(tokenManager.balanceOfOST(address(ostTransferModule)), 30);
}
function testPaymentProofEscrowCannotBeReclaimedBeforeSecondDeadline() public {
    _mintOST(alice, 100);
    _makeValidUser(bob);

    vm.prank(alice);
    uint256 transferId = ostTransferModule.createSellTransferRequest(
        alice,
        bob,
        30,
        200,
        TRANSFER_REF
    );

    vm.prank(bob);
    ostTransferModule.acceptTransfer(transferId, AGREEMENT_HASH);

    IOSTTransferModule.OSTTransfer memory escrowed =
        ostTransferModule.transfersf(transferId);

    vm.prank(bob);
    ostTransferModule.registerBuyerPaymentProof(
        transferId,
        PAYMENT_PROOF_HASH
    );

    vm.warp(ostTransferModule.paymentValidationDeadline(transferId));

    vm.prank(alice);
    vm.expectRevert("Escrow deadline not reached");

    ostTransferModule.reclaimExpiredEscrow(transferId);
}
function testExpiredEscrowCanBeReclaimedWhileOSTModulePaused() public {
    _mintOST(alice, 100);
    _makeValidUser(bob);

    vm.prank(alice);
    uint256 transferId = ostTransferModule.createSellTransferRequest(
        alice,
        bob,
        30,
        200,
        TRANSFER_REF
    );

    vm.prank(bob);
    ostTransferModule.acceptTransfer(transferId, AGREEMENT_HASH);

    IOSTTransferModule.OSTTransfer memory transfer =
        ostTransferModule.transfersf(transferId);

    vm.prank(owner);
    ostTransferModule.pause();

    vm.warp(transfer.escrowDeadline + 1);

    vm.prank(mallory);
    ostTransferModule.reclaimExpiredEscrow(transferId);

    assertEq(tokenManager.balanceOfOST(alice), 100);
}
function testHashSupersessionPreservesOriginalAnchor() public {
    bytes32 oldHash = keccak256("original-document");
    bytes32 newHash = keccak256("corrected-document");
    bytes32 reasonHash = keccak256("correction-reason");

    vm.prank(owner);
    hashRegistry.anchorHash(oldHash, "TRADE_RECEIPT", 123);

    vm.prank(owner);
    hashRegistry.supersedeHash(oldHash, newHash, reasonHash);

    assertTrue(hashRegistry.isHashValid(oldHash));
    assertTrue(hashRegistry.isHashValid(newHash));
    assertTrue(hashRegistry.isHashSuperseded(oldHash));
    assertFalse(hashRegistry.isHashSuperseded(newHash));

    (
        bytes32 oldSupersededBy,
        bytes32 oldSupersedes,
        bytes32 storedReasonHash
    ) = hashRegistry.getSupersession(oldHash);

    assertEq(oldSupersededBy, newHash);
    assertEq(oldSupersedes, bytes32(0));
    assertEq(storedReasonHash, reasonHash);

    (
        bytes32 newSupersededBy,
        bytes32 newSupersedes,
        bytes32 newReasonHash
    ) = hashRegistry.getSupersession(newHash);

    assertEq(newSupersededBy, bytes32(0));
    assertEq(newSupersedes, oldHash);
    assertEq(newReasonHash, bytes32(0));

    (
        bool oldExists,
        ,
        ,
        string memory oldReferenceType,
        uint256 oldReferenceId
    ) = hashRegistry.getHashRecord(oldHash);

    (
        bool newExists,
        ,
        ,
        string memory newReferenceType,
        uint256 newReferenceId
    ) = hashRegistry.getHashRecord(newHash);

    assertTrue(oldExists);
    assertTrue(newExists);
    assertEq(oldReferenceType, "TRADE_RECEIPT");
    assertEq(newReferenceType, "TRADE_RECEIPT");
    assertEq(oldReferenceId, 123);
    assertEq(newReferenceId, 123);
}
function testHashCannotBeSupersededTwice() public {
    bytes32 oldHash = keccak256("original-document");
    bytes32 newHash = keccak256("corrected-document");
    bytes32 anotherHash = keccak256("another-correction");

    vm.prank(owner);
    hashRegistry.anchorHash(oldHash, "TRADE_RECEIPT", 123);

    vm.prank(owner);
    hashRegistry.supersedeHash(
        oldHash,
        newHash,
        keccak256("first-reason")
    );

    vm.prank(owner);
    vm.expectRevert("Hash already superseded");

    hashRegistry.supersedeHash(
        oldHash,
        anotherHash,
        keccak256("second-reason")
    );
}
function testOSTTransfersAreNotBlockedByFormerTreasuryCap() public {
    _makeValidUser(alice);
    _makeValidUser(bob);

    _mintOST(alice, 100);

    vm.prank(alice);
    uint256 transferId = ostTransferModule.createSellTransferRequest(
        alice,
        bob,
        50,
        200,
        TRANSFER_REF
    );

    vm.prank(bob);
    ostTransferModule.acceptTransfer(transferId, AGREEMENT_HASH);

    vm.prank(bob);
    ostTransferModule.registerBuyerPaymentProof(
        transferId,
        PAYMENT_PROOF_HASH
    );

    vm.prank(alice);
    ostTransferModule.sellerValidatePaymentReceipt(
        transferId,
        SELLER_RECEIPT_HASH
    );

    _approveConfirmTransfer(transferId, RECEIPT_HASH);
        vm.prank(owner);
    ostTransferModule.adminConfirmOSTTransaction(
        transferId,
        RECEIPT_HASH
    );

    assertEq(tokenManager.balanceOfOST(alice), 50);
    assertEq(tokenManager.balanceOfOST(bob), 50);
}
function testLargeOwnerOSTBalanceDoesNotFreezeLedger() public {
    _makeValidUser(alice);
    _makeValidUser(bob);

    _mintOST(owner, 900);
    _mintOST(alice, 100);

    vm.prank(alice);
    uint256 transferId = ostTransferModule.createSellTransferRequest(
        alice,
        bob,
        20,
        200,
        TRANSFER_REF
    );

    vm.prank(bob);
    ostTransferModule.acceptTransfer(transferId, AGREEMENT_HASH);

    assertEq(tokenManager.balanceOfOST(alice), 80);
    assertEq(tokenManager.balanceOfOST(address(ostTransferModule)), 20);
}
function testH2ModulesHaveScopedPermissions() public view {
    assertFalse(accessControl.isAdmin(address(tokenManager)));
    assertFalse(accessControl.isAdmin(address(valuationAnchor)));
    assertFalse(accessControl.isAdmin(address(governanceRegistry)));
    assertFalse(accessControl.isAdmin(address(emergencyController)));
    assertFalse(accessControl.isAdmin(address(holderMigrationController)));

    assertTrue(accessControl.hasRole(accessControl.ROLE_ACCOUNT_MANAGER(), address(tokenManager)));
    assertTrue(accessControl.hasRole(accessControl.ROLE_ANCHOR(), address(valuationAnchor)));
    assertTrue(accessControl.hasRole(accessControl.ROLE_ANCHOR(), address(governanceRegistry)));
    assertTrue(accessControl.hasRole(accessControl.ROLE_EMERGENCY(), address(emergencyController)));
}
function testCancelBSABurnsUnexercisedIQS() public {
    uint256 bsaId = _recordBSA(alice, 185, 100);

    _approveActionForConsumerByTwoSigners(bsaRegistry.getCreditIQSActionHash(bsaId, 80, AWARD_REF), address(bsaRegistry));
    vm.prank(owner);
    bsaRegistry.creditIQS(bsaId, 80, AWARD_REF);

    assertEq(tokenManager.balanceOfIQS(alice), 80);
    assertEq(tokenManager.totalSupplyIQS(), 80);

    _approveActionForConsumerByTwoSigners(bsaRegistry.getCancelBSAActionHash(bsaId, keccak256("cancel-bsa")), address(bsaRegistry));
    vm.prank(owner);
    bsaRegistry.cancelBSA(bsaId, keccak256("cancel-bsa"));

    IBSARegistry.BSARecord memory bsa = bsaRegistry.bsasf(bsaId);

    assertEq(uint256(bsa.status), uint256(IBSARegistry.BSAStatus.Cancelled));
    assertEq(bsa.awardedIQS, 80);
    assertEq(bsa.convertedIQS, 0);
    assertEq(bsaRegistry.availableIQSToExercise(bsaId), 0);
    assertEq(tokenManager.balanceOfIQS(alice), 0);
    assertEq(tokenManager.totalSupplyIQS(), 0);
}
function testCancelBSABurnsOnlyRemainingIQSAfterExercise() public {
    uint256 bsaId = _recordBSA(alice, 185, 100);

    _approveActionForConsumerByTwoSigners(bsaRegistry.getCreditIQSActionHash(bsaId, 80, AWARD_REF), address(bsaRegistry));
    vm.prank(owner);
    bsaRegistry.creditIQS(bsaId, 80, AWARD_REF);

    vm.prank(alice);
    uint256 requestId = conversionModule.requestExercise(bsaId, 20, EXERCISE_REF);

    vm.prank(owner);
    conversionModule.approveExercise(requestId);

    vm.prank(owner);
    conversionModule.confirmCapitalReceived(requestId, CAPITAL_PAYMENT_HASH);

    bytes32 actionHash = conversionModule.getFinalizeExerciseActionHash(requestId, RECEIPT_HASH);
    _approveActionForConsumerByTwoSigners(
            actionHash,
            address(conversionModule)
        );

    vm.prank(owner);
    conversionModule.finalizeExercise(requestId, RECEIPT_HASH);

    assertEq(tokenManager.balanceOfIQS(alice), 60);
    assertEq(tokenManager.balanceOfOST(alice), 20);

    _approveActionForConsumerByTwoSigners(bsaRegistry.getCancelBSAActionHash(bsaId, keccak256("partial-cancel")), address(bsaRegistry));
    vm.prank(owner);
    bsaRegistry.cancelBSA(bsaId, keccak256("partial-cancel"));

    IBSARegistry.BSARecord memory bsa = bsaRegistry.bsasf(bsaId);

    assertEq(bsa.awardedIQS, 80);
    assertEq(bsa.convertedIQS, 20);
    assertEq(uint256(bsa.status), uint256(IBSARegistry.BSAStatus.Cancelled));

    assertEq(tokenManager.balanceOfIQS(alice), 0);
    assertEq(tokenManager.balanceOfOST(alice), 20);
    assertEq(tokenManager.totalSupplyIQS(), 0);
    assertEq(tokenManager.totalSupplyOSTf(), 20);
}
function testCancelBSAWithoutAwards() public {
    uint256 bsaId = _recordBSA(alice, 185, 100);

    _approveActionForConsumerByTwoSigners(bsaRegistry.getCancelBSAActionHash(bsaId, keccak256("cancel-empty-bsa")), address(bsaRegistry));
    vm.prank(owner);
    bsaRegistry.cancelBSA(bsaId, keccak256("cancel-empty-bsa"));

    IBSARegistry.BSARecord memory bsa = bsaRegistry.bsasf(bsaId);

    assertEq(uint256(bsa.status), uint256(IBSARegistry.BSAStatus.Cancelled));
    assertEq(bsaRegistry.activeBSAOf(alice), 0);
    assertEq(tokenManager.totalSupplyIQS(), 0);
}
function testBSACancellationRevertsIfIQSBurnFails() public {
    uint256 bsaId = _recordBSA(alice, 185, 100);

    _approveActionForConsumerByTwoSigners(bsaRegistry.getCreditIQSActionHash(bsaId, 40, AWARD_REF), address(bsaRegistry));
    vm.prank(owner);
    bsaRegistry.creditIQS(bsaId, 40, AWARD_REF);

    vm.prank(address(tokenOperatorController));
    tokenManager.setTokenOperator(address(bsaRegistry), false);

    _approveActionForConsumerByTwoSigners(bsaRegistry.getCancelBSAActionHash(bsaId, keccak256("failed-cancel")), address(bsaRegistry));
    vm.prank(owner);
    vm.expectRevert("Caller is not a token operator");
    bsaRegistry.cancelBSA(bsaId, keccak256("failed-cancel"));

    IBSARegistry.BSARecord memory bsa = bsaRegistry.bsasf(bsaId);

    assertEq(uint256(bsa.status), uint256(IBSARegistry.BSAStatus.Active));
    assertEq(tokenManager.balanceOfIQS(alice), 40);
    assertEq(tokenManager.totalSupplyIQS(), 40);
}
function testExpiredBSACannotCreateNewExerciseRequest() public {
    uint256 bsaId = _recordBSA(alice, 185, 100);

    _approveActionForConsumerByTwoSigners(bsaRegistry.getCreditIQSActionHash(bsaId, 40, AWARD_REF), address(bsaRegistry));
    vm.prank(owner);
    bsaRegistry.creditIQS(bsaId, 40, AWARD_REF);

    IBSARegistry.BSARecord memory bsa = bsaRegistry.bsasf(bsaId);

    vm.warp(bsa.expiryDate);

    assertEq(bsaRegistry.availableIQSToExercise(bsaId), 0);

    bsaRegistry.syncBSAStatus(bsaId);

    assertEq(
        uint256(bsaRegistry.bsasf(bsaId).status),
        uint256(IBSARegistry.BSAStatus.Expired)
    );
    assertEq(bsaRegistry.expiredIQSBurnedOf(bsaId), 40);
    assertEq(tokenManager.balanceOfIQS(alice), 0);
    assertEq(tokenManager.totalSupplyIQS(), 0);

    vm.prank(alice);
    vm.expectRevert("BSA expired");

    conversionModule.requestExercise(
        bsaId,
        10,
        EXERCISE_REF
    );

    assertEq(tokenManager.balanceOfOST(alice), 0);
}
function testExhaustedBSACannotExerciseAfterExpiry() public {
    uint256 bsaId = _recordBSA(alice, 185, 100);

    _approveActionForConsumerByTwoSigners(bsaRegistry.getCreditIQSActionHash(bsaId, 100, AWARD_REF), address(bsaRegistry));
    vm.prank(owner);
    bsaRegistry.creditIQS(bsaId, 100, AWARD_REF);

    IBSARegistry.BSARecord memory bsa = bsaRegistry.bsasf(bsaId);

    assertEq(
        uint256(bsa.status),
        uint256(IBSARegistry.BSAStatus.Exhausted)
    );

    vm.warp(bsa.expiryDate + 1);

    assertEq(bsaRegistry.availableIQSToExercise(bsaId), 0);

    vm.prank(alice);
    vm.expectRevert("BSA expired");

    conversionModule.requestExercise(
        bsaId,
        20,
        EXERCISE_REF
    );
}
function testExerciseRequestedBeforeExpiryCanSettleAfterExpiry() public {
    uint256 bsaId = _recordBSA(alice, 185, 100);

    _approveActionForConsumerByTwoSigners(bsaRegistry.getCreditIQSActionHash(bsaId, 80, AWARD_REF), address(bsaRegistry));
    vm.prank(owner);
    bsaRegistry.creditIQS(bsaId, 80, AWARD_REF);

    IBSARegistry.BSARecord memory bsa = bsaRegistry.bsasf(bsaId);

    vm.warp(bsa.expiryDate - 1);

    vm.prank(alice);
    uint256 requestId = conversionModule.requestExercise(
        bsaId,
        20,
        EXERCISE_REF
    );

    vm.warp(bsa.expiryDate + 1);

    bsaRegistry.syncBSAStatus(bsaId);

    assertEq(
        uint256(bsaRegistry.bsasf(bsaId).status),
        uint256(IBSARegistry.BSAStatus.Expired)
    );
    assertEq(conversionModule.pendingExerciseIQSForBSA(bsaId), 20);
    assertEq(bsaRegistry.expiredIQSBurnedOf(bsaId), 60);
    assertEq(tokenManager.balanceOfIQS(alice), 20);

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

    _approveActionForConsumerByTwoSigners(
            actionHash,
            address(conversionModule)
        );

    vm.prank(owner);
    conversionModule.finalizeExercise(
        requestId,
        RECEIPT_HASH
    );

    assertEq(tokenManager.balanceOfIQS(alice), 0);
    assertEq(tokenManager.totalSupplyIQS(), 0);
    assertEq(tokenManager.balanceOfOST(alice), 20);
    assertEq(bsaRegistry.bsasf(bsaId).convertedIQS, 20);
    assertEq(bsaRegistry.expiredIQSBurnedOf(bsaId), 60);
    assertEq(conversionModule.pendingExerciseIQSForBSA(bsaId), 0);
}
function testExerciseRequestsReserveIQSAndCannotOverbookBSA() public {
    uint256 bsaId = _recordBSA(alice, 185, 100);

    _approveActionForConsumerByTwoSigners(bsaRegistry.getCreditIQSActionHash(bsaId, 80, AWARD_REF), address(bsaRegistry));
    vm.prank(owner);
    bsaRegistry.creditIQS(bsaId, 80, AWARD_REF);

    vm.prank(alice);
    conversionModule.requestExercise(
        bsaId,
        60,
        keccak256("exercise-reservation-1")
    );

    assertEq(conversionModule.pendingExerciseIQSForBSA(bsaId), 60);
    assertEq(bsaRegistry.availableIQSToExercise(bsaId), 20);

    vm.prank(alice);
    vm.expectRevert("Insufficient unreserved BSA IQS");
    conversionModule.requestExercise(
        bsaId,
        21,
        keccak256("exercise-reservation-too-large")
    );

    vm.prank(alice);
    conversionModule.requestExercise(
        bsaId,
        20,
        keccak256("exercise-reservation-2")
    );

    assertEq(conversionModule.pendingExerciseIQSForBSA(bsaId), 80);
    assertEq(bsaRegistry.availableIQSToExercise(bsaId), 0);
}

function testBSACannotBeCancelledWhileExerciseIsPending() public {
    uint256 bsaId = _recordBSA(alice, 185, 100);

    _approveActionForConsumerByTwoSigners(bsaRegistry.getCreditIQSActionHash(bsaId, 80, AWARD_REF), address(bsaRegistry));
    vm.prank(owner);
    bsaRegistry.creditIQS(bsaId, 80, AWARD_REF);

    vm.prank(alice);
    uint256 requestId = conversionModule.requestExercise(
        bsaId,
        20,
        keccak256("pending-before-bsa-cancel")
    );

    vm.prank(owner);
    vm.expectRevert("BSA has pending exercise");
    bsaRegistry.cancelBSA(bsaId, keccak256("must-not-cancel-yet"));

    vm.prank(alice);
    conversionModule.cancelExercise(requestId);

    assertEq(conversionModule.pendingExerciseIQSForBSA(bsaId), 0);

    _approveActionForConsumerByTwoSigners(bsaRegistry.getCancelBSAActionHash(bsaId, keccak256("cancel-after-request-closed")), address(bsaRegistry));
    vm.prank(owner);
    bsaRegistry.cancelBSA(bsaId, keccak256("cancel-after-request-closed"));

    assertEq(
        uint256(bsaRegistry.bsasf(bsaId).status),
        uint256(IBSARegistry.BSAStatus.Cancelled)
    );
    assertEq(tokenManager.balanceOfIQS(alice), 0);
}

function testExpiredPendingExerciseCancellationBurnsReleasedIQS() public {
    uint256 bsaId = _recordBSA(alice, 185, 100);

    _approveActionForConsumerByTwoSigners(bsaRegistry.getCreditIQSActionHash(bsaId, 80, AWARD_REF), address(bsaRegistry));
    vm.prank(owner);
    bsaRegistry.creditIQS(bsaId, 80, AWARD_REF);

    IBSARegistry.BSARecord memory bsa = bsaRegistry.bsasf(bsaId);

    vm.prank(alice);
    uint256 requestId = conversionModule.requestExercise(
        bsaId,
        20,
        keccak256("exercise-before-expiry-cancel-after")
    );

    vm.warp(bsa.expiryDate + 1);
    bsaRegistry.syncBSAStatus(bsaId);

    assertEq(bsaRegistry.expiredIQSBurnedOf(bsaId), 60);
    assertEq(tokenManager.balanceOfIQS(alice), 20);
    assertEq(conversionModule.pendingExerciseIQSForBSA(bsaId), 20);

    vm.prank(alice);
    conversionModule.cancelExercise(requestId);

    assertEq(conversionModule.pendingExerciseIQSForBSA(bsaId), 0);
    assertEq(bsaRegistry.expiredIQSBurnedOf(bsaId), 80);
    assertEq(tokenManager.balanceOfIQS(alice), 0);
    assertEq(tokenManager.totalSupplyIQS(), 0);
}

function testHolderMigrationBlockedWhileExercisePending() public {
    uint256 bsaId = _awardIQS(alice, 80);

    vm.prank(alice);
    uint256 requestId = conversionModule.requestExercise(
        bsaId,
        20,
        keccak256("pending-before-holder-migration")
    );

    _approveHolderMigration(alice, aliceNewWallet, MIGRATION_REF);

    vm.prank(owner);
    vm.expectRevert("BSA has pending exercise");
    holderMigrationController.migrateHolder(
        alice,
        aliceNewWallet,
        MIGRATION_REF
    );

    vm.prank(alice);
    conversionModule.cancelExercise(requestId);

    bytes32 secondMigrationRef =
        keccak256("holder-migration-after-exercise-closed");

    _approveHolderMigration(
        alice,
        aliceNewWallet,
        secondMigrationRef
    );

    vm.prank(owner);
    holderMigrationController.migrateHolder(
        alice,
        aliceNewWallet,
        secondMigrationRef
    );

    assertEq(bsaRegistry.bsasf(bsaId).holder, aliceNewWallet);
    assertEq(tokenManager.balanceOfIQS(aliceNewWallet), 80);
}

function testConversionModuleCannotBeRepointed() public {
    assertEq(bsaRegistry.conversionModule(), address(conversionModule));

    vm.prank(owner);
    vm.expectRevert("Conversion module already set");
    bsaRegistry.setConversionModule(address(0xDEAD));
}

function testFrozenBuyerCannotReceiveOSTFromEscrow() public {
    _mintOST(alice, 100);
    _makeValidUser(bob);

    vm.prank(alice);
    uint256 transferId = ostTransferModule.createSellTransferRequest(
        alice,
        bob,
        30,
        200,
        TRANSFER_REF
    );

    vm.prank(bob);
    ostTransferModule.acceptTransfer(transferId, AGREEMENT_HASH);

    vm.prank(bob);
    ostTransferModule.registerBuyerPaymentProof(
        transferId,
        PAYMENT_PROOF_HASH
    );

    vm.prank(alice);
    ostTransferModule.sellerValidatePaymentReceipt(
        transferId,
        SELLER_RECEIPT_HASH
    );

    // Buyer je bio validan pri prihvatanju, ali je sada zamrznut.
    vm.prank(owner);
    accessControl.freezeAddress(bob);

    _approveConfirmTransfer(transferId, RECEIPT_HASH);
        vm.prank(owner);
    vm.expectRevert("Sender is frozen");
    ostTransferModule.adminConfirmOSTTransaction(
        transferId,
        RECEIPT_HASH
    );

    assertEq(tokenManager.balanceOfOST(alice), 70);
    assertEq(tokenManager.balanceOfOST(bob), 0);
    assertEq(tokenManager.balanceOfOST(address(ostTransferModule)), 30);

    // Nakon odmrzavanja isti transfer može da se finalizuje.
    vm.prank(owner);
    accessControl.unfreezeAddress(bob);

    _approveConfirmTransfer(transferId, RECEIPT_HASH);
        vm.prank(owner);
    ostTransferModule.adminConfirmOSTTransaction(
        transferId,
        RECEIPT_HASH
    );

    assertEq(tokenManager.balanceOfOST(alice), 70);
    assertEq(tokenManager.balanceOfOST(bob), 30);
    assertEq(tokenManager.balanceOfOST(address(ostTransferModule)), 0);
}
function testDeWhitelistedBuyerCannotReceiveOSTViaMultisigResolution() public {
    _mintOST(alice, 100);
    _makeValidUser(bob);

    vm.prank(alice);
    uint256 transferId = ostTransferModule.createSellTransferRequest(
        alice,
        bob,
        25,
        200,
        TRANSFER_REF
    );

    vm.prank(bob);
    ostTransferModule.acceptTransfer(
        transferId,
        AGREEMENT_HASH
    );

    vm.prank(owner);
    accessControl.removeFromWhiteList(bob);

    bytes32 resolutionHash = keccak256("m3-buyer-resolution");

    bytes32 actionHash =
        ostTransferModule.getAdminResolveTransferActionHash(
            transferId,
            true,
            resolutionHash,
            RECEIPT_HASH
        );

    _approveActionForConsumerByTwoSigners(
            actionHash,
            address(ostTransferModule)
        );

    vm.prank(owner);
    vm.expectRevert("Sender not white-listed");

    ostTransferModule.adminResolveTransfer(
        transferId,
        true,
        resolutionHash,
        RECEIPT_HASH
    );

    assertEq(tokenManager.balanceOfOST(bob), 0);
    assertEq(tokenManager.balanceOfOST(address(ostTransferModule)), 25);

    // Revert poništava i eventualnu potrošnju multisig approval-a.
    (, bool consumed,) = adminMultisig.getApprovalState(actionHash);
    assertFalse(consumed);

    vm.prank(owner);
    accessControl.addToWhiteList(bob);

    vm.prank(owner);
    ostTransferModule.adminResolveTransfer(
        transferId,
        true,
        resolutionHash,
        RECEIPT_HASH
    );

    assertEq(tokenManager.balanceOfOST(bob), 25);

    (, consumed,) = adminMultisig.getApprovalState(actionHash);
    assertTrue(consumed);
}
function testFrozenSellerBlocksEscrowReleaseToBuyer() public {
    _mintOST(alice, 100);
    _makeValidUser(bob);

    vm.prank(alice);
    uint256 transferId = ostTransferModule.createSellTransferRequest(
        alice,
        bob,
        20,
        200,
        TRANSFER_REF
    );

    vm.prank(bob);
    ostTransferModule.acceptTransfer(
        transferId,
        AGREEMENT_HASH
    );

    vm.prank(bob);
    ostTransferModule.registerBuyerPaymentProof(
        transferId,
        PAYMENT_PROOF_HASH
    );

    vm.prank(alice);
    ostTransferModule.sellerValidatePaymentReceipt(
        transferId,
        SELLER_RECEIPT_HASH
    );

    vm.prank(owner);
    accessControl.freezeAddress(alice);

    _approveConfirmTransfer(transferId, RECEIPT_HASH);
        vm.prank(owner);
    vm.expectRevert("Sender is frozen");

    ostTransferModule.adminConfirmOSTTransaction(
        transferId,
        RECEIPT_HASH
    );

    assertEq(tokenManager.balanceOfOST(alice), 80);
    assertEq(tokenManager.balanceOfOST(bob), 0);
    assertEq(tokenManager.balanceOfOST(address(ostTransferModule)), 20);
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

    function testM6EscrowIsNotListedAsOSTHolderWhileHoldingShares() public {
        assertEq(tokenManager.ostEscrowAddress(), address(ostTransferModule));
        _mintOST(alice, 100);
        _makeValidUser(bob);

        vm.prank(alice);
        uint256 transferId = ostTransferModule.createSellTransferRequest(
            alice, bob, 30, 200, TRANSFER_REF
        );

        vm.prank(bob);
        ostTransferModule.acceptTransfer(transferId, AGREEMENT_HASH);

        address escrow = address(ostTransferModule);
        assertEq(tokenManager.balanceOfOST(escrow), 30);
        assertEq(tokenManager.balanceOfOST(alice), 70);
        assertEq(tokenManager.totalSupplyOSTf(), 100);

        (address[] memory holders, uint256[] memory balances) =
            tokenManager.getOSTHolders();

        assertEq(holders.length, 1);
        assertEq(balances.length, 1);
        assertEq(holders[0], alice);
        assertEq(balances[0], 70);
        // OST custody is excluded from shareholder enumeration, NOT from supply.
        assertEq(balances[0] + tokenManager.balanceOfOST(escrow), 100);
    }

    function testM6BuyerAppearsInHolderRegisterAfterEscrowRelease() public {
        _mintOST(alice, 100);
        _makeValidUser(bob);

        vm.prank(alice);
        uint256 transferId = ostTransferModule.createSellTransferRequest(
            alice, bob, 30, 200, TRANSFER_REF
        );
        vm.prank(bob);
        ostTransferModule.acceptTransfer(transferId, AGREEMENT_HASH);

        vm.prank(bob);
        ostTransferModule.registerBuyerPaymentProof(transferId, PAYMENT_PROOF_HASH);
        vm.prank(alice);
        ostTransferModule.sellerValidatePaymentReceipt(transferId, SELLER_RECEIPT_HASH);
        _approveConfirmTransfer(transferId, RECEIPT_HASH);
        vm.prank(owner);
        ostTransferModule.adminConfirmOSTTransaction(transferId, RECEIPT_HASH);

        assertEq(tokenManager.balanceOfOST(address(ostTransferModule)), 0);
        assertEq(tokenManager.totalSupplyOSTf(), 100);
        (address[] memory holders, uint256[] memory balances) =
            tokenManager.getOSTHolders();
        assertEq(holders.length, 2);
        assertEq(balances.length, 2);
        bool foundAlice;
        bool foundBob;
        for (uint256 i = 0; i < holders.length; ++i) {
            assertTrue(holders[i] != address(ostTransferModule));
            if (holders[i] == alice) {
                foundAlice = true;
                assertEq(balances[i], 70);
            } else if (holders[i] == bob) {
                foundBob = true;
                assertEq(balances[i], 30);
            } else {
                revert("Unexpected OST holder");
            }
        }
        assertTrue(foundAlice);
        assertTrue(foundBob);
    }

    function testM6EscrowConfigurationCannotBeReplaced() public {
        vm.prank(owner);
        vm.expectRevert("OST escrow already configured");
        tokenManager.setOSTEscrowAddress(address(bsaRegistry));
        assertEq(tokenManager.ostEscrowAddress(), address(ostTransferModule));
    }

    function testM6NonAdminCannotReconfigureOSTEscrow() public {
        vm.prank(mallory);
        vm.expectRevert("Caller is not an admin");
        tokenManager.setOSTEscrowAddress(address(bsaRegistry));
    }



    // -------------------------------------------------------------------------
    // M-8: escrow custody survives controlled OSTTransferModule replacement.
    // -------------------------------------------------------------------------

    function _m8PrepareReplacement() internal returns (OSTTransferModule replacement) {
        replacement = new OSTTransferModule(
            address(accessControl), address(tokenManager), address(adminMultisig)
        );
        bytes32 referenceHash = keccak256("m8-authorize-new-module");
        bytes32 actionHash = tokenOperatorController.getSetTokenOperatorActionHash(
            address(replacement), true, referenceHash
        );
        _approveActionForConsumerByTwoSigners(
            actionHash, address(tokenOperatorController)
        );
        vm.prank(owner);
        tokenOperatorController.setTokenOperator(
            address(replacement), true, referenceHash
        );
        assertTrue(tokenManager.isTokenOperator(address(replacement)));
    }

    function _m8StartEscrow(uint256 amount) internal returns (uint256 transferId) {
        _mintOST(alice, 100);
        _makeValidUser(bob);
        vm.prank(alice);
        transferId = ostTransferModule.createSellTransferRequest(
            alice, bob, amount, 200, TRANSFER_REF
        );
        vm.prank(bob);
        ostTransferModule.acceptTransfer(transferId, AGREEMENT_HASH);
        assertEq(tokenManager.balanceOfOST(address(ostTransferModule)), amount);
    }

    function _m8SettleEscrow(uint256 transferId) internal {
        vm.prank(bob);
        ostTransferModule.registerBuyerPaymentProof(transferId, PAYMENT_PROOF_HASH);
        vm.prank(alice);
        ostTransferModule.sellerValidatePaymentReceipt(
            transferId, SELLER_RECEIPT_HASH
        );
        _approveConfirmTransfer(transferId, RECEIPT_HASH);
        vm.prank(owner);
        ostTransferModule.adminConfirmOSTTransaction(transferId, RECEIPT_HASH);
    }

    function testM8CannotDeregisterOperatorHoldingEscrowedOST() public {
        _m8StartEscrow(30);
        bytes32 referenceHash = keccak256("m8-disable-too-early");
        bytes32 actionHash = tokenOperatorController.getSetTokenOperatorActionHash(
            address(ostTransferModule), false, referenceHash
        );
        _approveActionForConsumerByTwoSigners(
            actionHash, address(tokenOperatorController)
        );

        vm.prank(owner);
        vm.expectRevert("Operator holds OST");
        tokenOperatorController.setTokenOperator(
            address(ostTransferModule), false, referenceHash
        );

        assertTrue(tokenManager.isTokenOperator(address(ostTransferModule)));
        assertEq(tokenManager.balanceOfOST(address(ostTransferModule)), 30);
        (, bool consumed,) = adminMultisig.getApprovalState(actionHash);
        assertFalse(consumed);
    }

    function testM8CannotRotateWithUnsettledEscrow() public {
        _m8StartEscrow(30);
        OSTTransferModule replacement = _m8PrepareReplacement();
        vm.prank(owner);
        ostTransferModule.pause();

        vm.prank(owner);
        vm.expectRevert("Old escrow not drained");
        tokenManager.rotateOSTEscrowAddress(address(replacement));
        assertEq(tokenManager.ostEscrowAddress(), address(ostTransferModule));
    }

    function testM8CannotRotateUntilOldModulePaused() public {
        OSTTransferModule replacement = _m8PrepareReplacement();

        vm.prank(owner);
        vm.expectRevert("Old escrow must be paused");
        tokenManager.rotateOSTEscrowAddress(address(replacement));
        assertEq(tokenManager.ostEscrowAddress(), address(ostTransferModule));
    }

    function testM8CannotMigrateOperatorCustodyAsHolderWallet() public {
        _m8StartEscrow(30);
        vm.prank(address(holderMigrationController));
        vm.expectRevert("Cannot migrate token operator wallet");
        tokenManager.adminMigrateWallet(
            address(ostTransferModule), aliceNewWallet,
            keccak256("m8-escrow-is-not-holder-wallet")
        );
        assertEq(tokenManager.balanceOfOST(address(ostTransferModule)), 30);
    }

    function testM8DrainPauseRotateThenDeregisterOldModule() public {
        uint256 transferId = _m8StartEscrow(30);
        OSTTransferModule replacement = _m8PrepareReplacement();

        // Old module retains permission until the escrow has been settled.
        _m8SettleEscrow(transferId);
        assertEq(tokenManager.balanceOfOST(address(ostTransferModule)), 0);
        assertEq(tokenManager.balanceOfOST(bob), 30);

        vm.prank(owner);
        ostTransferModule.pause();
        vm.prank(owner);
        tokenManager.rotateOSTEscrowAddress(address(replacement));
        assertEq(tokenManager.ostEscrowAddress(), address(replacement));

        bytes32 disableRef = keccak256("m8-disable-drained-module");
        bytes32 disableHash = tokenOperatorController.getSetTokenOperatorActionHash(
            address(ostTransferModule), false, disableRef
        );
        _approveActionForConsumerByTwoSigners(
            disableHash, address(tokenOperatorController)
        );
        vm.prank(owner);
        tokenOperatorController.setTokenOperator(
            address(ostTransferModule), false, disableRef
        );
        assertFalse(tokenManager.isTokenOperator(address(ostTransferModule)));
        assertTrue(tokenManager.isTokenOperator(address(replacement)));

        // New transactions now escrow in the replacement, not the old module.
        vm.prank(alice);
        uint256 nextId = replacement.createSellTransferRequest(
            alice, bob, 20, 200, keccak256("m8-replacement-trade")
        );
        vm.prank(bob);
        replacement.acceptTransfer(nextId, keccak256("m8-replacement-agreement"));

        assertEq(tokenManager.balanceOfOST(address(ostTransferModule)), 0);
        assertEq(tokenManager.balanceOfOST(address(replacement)), 20);
        assertEq(tokenManager.totalSupplyOSTf(), 100);
        (address[] memory holders,) = tokenManager.getOSTHolders();
        for (uint256 i = 0; i < holders.length; i++) {
            assertTrue(holders[i] != address(ostTransferModule));
            assertTrue(holders[i] != address(replacement));
        }
    }


    // M-9: helper deliberately uses the existing, authorized BSA token operator.
    function _m9IssueIQS(address wallet, uint256 amount) internal {
        _makeValidUser(wallet);
        vm.prank(address(bsaRegistry));
        tokenManager.mintIQSTo(wallet, amount, keccak256(abi.encode("m9-iqs", wallet, amount)));
    }

    function _m9FillSlots(address firstHolder) internal {
        _m9IssueIQS(firstHolder, 1);
        for (uint256 i = 1; i < tokenManager.MAX_REGISTERED_HOLDERS(); ++i) {
            _m9IssueIQS(address(uint160(0x10000 + i)), 1);
        }
        assertEq(tokenManager.registeredHolderCount(), 149);
    }

    function testM9MintIQSCannotCreate150thHolder() public {
        _m9FillSlots(alice);
        _makeValidUser(bob);
        vm.prank(address(bsaRegistry));
        vm.expectRevert("Holder cap reached");
        tokenManager.mintIQSTo(bob, 1, keccak256("m9-block-150th-iqs"));

        // A second award to the SAME wallet does not consume another slot.
        vm.prank(address(bsaRegistry));
        tokenManager.mintIQSTo(alice, 1, keccak256("m9-repeat-holder"));
        assertEq(tokenManager.registeredHolderCount(), 149);
        assertEq(tokenManager.balanceOfIQS(alice), 2);

        // Even if one holder burns all IQS, the cumulative subscription slot
        // remains reserved; otherwise churn could evade the cap.
        vm.prank(address(bsaRegistry));
        tokenManager.burnIQS(1, address(uint160(0x10000 + 1)));
        assertEq(tokenManager.registeredHolderCount(), 149);
        vm.prank(address(bsaRegistry));
        vm.expectRevert("Holder cap reached");
        tokenManager.mintIQSTo(bob, 1, keccak256("m9-replace-burnt-wallet"));
    }

    function testM9MintOSTAndTransfersShareSingleHolderCap() public {
        _m9FillSlots(alice);
        _makeValidUser(bob);

        // Converting an existing IQS holder to OST does not count twice.
        vm.prank(address(bsaRegistry));
        tokenManager.mintOSTTo(alice, 2, keccak256("m9-existing-iqs-holder-ost"));
        assertEq(tokenManager.registeredHolderCount(), 149);

        vm.prank(address(bsaRegistry));
        vm.expectRevert("Holder cap reached");
        tokenManager.mintOSTTo(bob, 1, keccak256("m9-block-150th-ost"));

        // Also covers secondary OST transfers, not just issuance.
        vm.prank(address(ostTransferModule));
        vm.expectRevert("Holder cap reached");
        tokenManager.transferOSTfromAtoB(alice, bob, 1);
        assertEq(tokenManager.balanceOfOST(alice), 2);
        assertEq(tokenManager.balanceOfOST(bob), 0);
        assertEq(tokenManager.registeredHolderCount(), 149);
    }

    function testM9EscrowAndSellerReclaimDoNotConsumeExtraHolderSlot() public {
        _m9FillSlots(alice);
        vm.prank(address(bsaRegistry));
        tokenManager.mintOSTTo(alice, 1, keccak256("m9-seller-ost"));
        vm.prank(address(bsaRegistry));
        tokenManager.burnIQS(1, alice);

        // Seller now has ONLY OST. Depositing it must NOT release the seller's
        // permanent slot; otherwise 150th buyer could join while OST is escrowed.
        vm.prank(address(ostTransferModule));
        tokenManager.transferOSTfromAtoB(alice, address(ostTransferModule), 1);
        assertEq(tokenManager.balanceOfOST(alice), 0);
        assertEq(tokenManager.balanceOfOST(address(ostTransferModule)), 1);
        assertEq(tokenManager.registeredHolderCount(), 149);
        assertTrue(tokenManager.hasHolderSlot(alice));
        assertFalse(tokenManager.hasHolderSlot(address(ostTransferModule)));

        // Seller can always reclaim despite the full 149-slot quota.
        vm.prank(address(ostTransferModule));
        tokenManager.transferOSTfromAtoB(address(ostTransferModule), alice, 1);
        assertEq(tokenManager.balanceOfOST(alice), 1);
        assertEq(tokenManager.registeredHolderCount(), 149);
    }

    function testM9HolderMigrationReusesSlotEvenAt149() public {
        _m9FillSlots(alice);
        assertTrue(tokenManager.hasHolderSlot(alice));
        assertFalse(tokenManager.hasHolderSlot(aliceNewWallet));

        _approveHolderMigration(alice, aliceNewWallet, MIGRATION_REF);
        vm.prank(owner);
        holderMigrationController.migrateHolder(alice, aliceNewWallet, MIGRATION_REF);

        assertEq(tokenManager.registeredHolderCount(), 149);
        assertFalse(tokenManager.hasHolderSlot(alice));
        assertTrue(tokenManager.retiredHolderWallet(alice));
        assertTrue(tokenManager.hasHolderSlot(aliceNewWallet));
        assertEq(tokenManager.balanceOfIQS(alice), 0);
        assertEq(tokenManager.balanceOfIQS(aliceNewWallet), 1);

        // Even a privileged re-whitelisting cannot reuse a migrated-out wallet.
        vm.startPrank(owner);
        accessControl.unfreezeAddress(alice);
        accessControl.addToWhiteList(alice);
        accessControl.authorizeAddress(alice);
        vm.stopPrank();
        vm.prank(address(bsaRegistry));
        vm.expectRevert("Retired holder wallet");
        tokenManager.mintIQSTo(alice, 1, keccak256("m9-retired-wallet"));
    }

    // Security review of 6 October 2026: regression tests for F-01 through F-08.
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

    function testF01SingleAdminCannotCreateVictimSellRequest() public {
        _mintOST(alice, 100);
        _makeValidUser(bob);
        vm.prank(owner);
        vm.expectRevert("Action belongs to different consumer");
        ostTransferModule.createSellTransferRequest(alice, bob, 30, 200, TRANSFER_REF);
        assertEq(tokenManager.balanceOfOST(alice), 100);
        assertEq(ostTransferModule.openTransferCount(), 0);
    }

    function testF01SingleAdminCannotCreateBuyerRequestOnBehalfOfHolder() public {
        _mintOST(alice, 100);
        _makeValidUser(bob);
        vm.prank(owner);
        vm.expectRevert("Action belongs to different consumer");
        ostTransferModule.createBuyTransferRequest(bob, alice, 30, 200, TRANSFER_REF);
    }

    function testF01AdminCreatedSellRequestRequiresTwoSignatures() public {
        _mintOST(alice, 100);
        _makeValidUser(bob);
        bytes32 hash = ostTransferModule.getAdminCreateTransferRequestActionHash(
            IOSTTransferModule.TransferType.SellRequest, alice, bob, 30, 200, TRANSFER_REF
        );
        _proposeTestAction(hash, address(ostTransferModule));
        vm.prank(owner);
        adminMultisig.approveActionForConsumer(hash, address(ostTransferModule));
        vm.prank(owner);
        vm.expectRevert("Action not approved");
        ostTransferModule.createSellTransferRequest(alice, bob, 30, 200, TRANSFER_REF);
        vm.prank(signer2);
        adminMultisig.approveActionForConsumer(hash, address(ostTransferModule));
        vm.prank(owner);
        uint256 id = ostTransferModule.createSellTransferRequest(alice, bob, 30, 200, TRANSFER_REF);
        assertEq(ostTransferModule.activeTransferCount(alice), 1);
        assertEq(ostTransferModule.activeTransferCount(bob), 1);
        (, bool consumed,) = adminMultisig.getApprovalState(hash);
        assertTrue(consumed);
        vm.prank(owner);
        vm.expectRevert("Action not approved");
        ostTransferModule.createSellTransferRequest(alice, bob, 30, 200, TRANSFER_REF);
        vm.prank(alice);
        ostTransferModule.cancelTransfer(id);
        assertEq(ostTransferModule.openTransferCount(), 0);
    }

    function testF01AdminCreatedBuyRequestUsesItsOwnActionHash() public {
        _mintOST(alice, 100);
        _makeValidUser(bob);
        bytes32 hash = ostTransferModule.getAdminCreateTransferRequestActionHash(
            IOSTTransferModule.TransferType.BuyRequest, alice, bob, 30, 200, TRANSFER_REF
        );
        _approveActionForConsumerByTwoSigners(hash, address(ostTransferModule));
        vm.prank(owner);
        uint256 id = ostTransferModule.createBuyTransferRequest(bob, alice, 30, 200, TRANSFER_REF);
        assertEq(ostTransferModule.transfersf(id).proposer, bob);
    }

    function testF01AdminCannotValidateSellerReceiptWithoutMultisig() public {
        uint256 id = _reviewEscrow();
        _reviewPaymentProof(id);
        bytes32 hash = ostTransferModule.getAdminValidateSellerPaymentActionHash(id, SELLER_RECEIPT_HASH);
        _proposeTestAction(hash, address(ostTransferModule));
        vm.prank(owner);
        adminMultisig.approveActionForConsumer(hash, address(ostTransferModule));
        vm.prank(owner);
        vm.expectRevert("Action not approved");
        ostTransferModule.adminValidateSellerPaymentReceipt(id, SELLER_RECEIPT_HASH);
        assertEq(uint256(ostTransferModule.transfersf(id).status), uint256(IOSTTransferModule.TransferStatus.PaymentProofRegistered));
        vm.prank(signer2);
        adminMultisig.approveActionForConsumer(hash, address(ostTransferModule));
        vm.prank(owner);
        ostTransferModule.adminValidateSellerPaymentReceipt(id, SELLER_RECEIPT_HASH);
        assertEq(uint256(ostTransferModule.transfersf(id).status), uint256(IOSTTransferModule.TransferStatus.SellerValidatedPayment));
    }

    function testF01SingleAdminCannotReleaseOSTAndApprovalBindsReceipt() public {
        uint256 id = _reviewEscrow();
        _reviewSellerValidation(id);
        bytes32 hash = ostTransferModule.getAdminConfirmOSTTransactionActionHash(id, RECEIPT_HASH);
        _proposeTestAction(hash, address(ostTransferModule));
        vm.prank(owner);
        adminMultisig.approveActionForConsumer(hash, address(ostTransferModule));
        vm.prank(owner);
        vm.expectRevert("Action not approved");
        ostTransferModule.adminConfirmOSTTransaction(id, RECEIPT_HASH);
        vm.prank(signer2);
        adminMultisig.approveActionForConsumer(hash, address(ostTransferModule));
        vm.prank(owner);
        vm.expectRevert("Action belongs to different consumer");
        ostTransferModule.adminConfirmOSTTransaction(id, keccak256("other-receipt"));
        assertTrue(adminMultisig.isActionApproved(hash));
        vm.prank(owner);
        ostTransferModule.adminConfirmOSTTransaction(id, RECEIPT_HASH);
        assertEq(tokenManager.balanceOfOST(bob), 30);
        assertEq(ostTransferModule.openTransferCount(), 0);
        assertEq(ostTransferModule.activeTransferCount(alice), 0);
        assertEq(ostTransferModule.activeTransferCount(bob), 0);
    }

    function testF02RecordBSARequiresApprovalAndConsumesIt() public {
        _makeValidUser(alice);
        uint256 expiry = block.timestamp + 365 days;
        vm.prank(owner);
        vm.expectRevert("Action belongs to different consumer");
        bsaRegistry.recordBSA(alice, BSA_HASH, BSA_TERMS_HASH, 185, 100, expiry, 0);
        assertEq(bsaRegistry.bsaCount(), 0);
        bytes32 hash = bsaRegistry.getRecordBSAActionHash(alice, BSA_HASH, BSA_TERMS_HASH, 185, 100, expiry, 0);
        _proposeTestAction(hash, address(bsaRegistry));
        vm.prank(owner);
        adminMultisig.approveActionForConsumer(hash, address(bsaRegistry));
        vm.prank(owner);
        vm.expectRevert("Action not approved");
        bsaRegistry.recordBSA(alice, BSA_HASH, BSA_TERMS_HASH, 185, 100, expiry, 0);
        vm.prank(signer2);
        adminMultisig.approveActionForConsumer(hash, address(bsaRegistry));
        vm.prank(owner);
        bsaRegistry.recordBSA(alice, BSA_HASH, BSA_TERMS_HASH, 185, 100, expiry, 0);
        (, bool consumed,) = adminMultisig.getApprovalState(hash);
        assertTrue(consumed);
    }

    function testF02CreditRequiresTwoApprovalsAndCannotReplay() public {
        uint256 id = _recordBSA(alice, 185, 100);
        vm.prank(owner);
        vm.expectRevert("Action belongs to different consumer");
        bsaRegistry.creditIQS(id, 30, AWARD_REF);
        bytes32 hash = bsaRegistry.getCreditIQSActionHash(id, 30, AWARD_REF);
        _proposeTestAction(hash, address(bsaRegistry));
        vm.prank(owner);
        adminMultisig.approveActionForConsumer(hash, address(bsaRegistry));
        vm.prank(owner);
        vm.expectRevert("Action not approved");
        bsaRegistry.creditIQS(id, 30, AWARD_REF);
        vm.prank(signer2);
        adminMultisig.approveActionForConsumer(hash, address(bsaRegistry));
        vm.prank(owner);
        bsaRegistry.creditIQS(id, 30, AWARD_REF);
        vm.prank(owner);
        vm.expectRevert("Action not approved");
        bsaRegistry.creditIQS(id, 30, AWARD_REF);
        assertEq(tokenManager.balanceOfIQS(alice), 30);
        assertEq(bsaRegistry.bsasf(id).awardedIQS, 30);
    }

    function testF02FailedMintPreservesCreditApprovalAndRecordedAward() public {
        uint256 id = _recordBSA(alice, 185, 100);
        bytes32 hash = bsaRegistry.getCreditIQSActionHash(id, 30, AWARD_REF);
        _approveActionForConsumerByTwoSigners(hash, address(bsaRegistry));
        vm.prank(owner);
        accessControl.freezeAddress(alice);
        vm.prank(owner);
        vm.expectRevert("Sender is frozen");
        bsaRegistry.creditIQS(id, 30, AWARD_REF);
        assertEq(bsaRegistry.bsasf(id).awardedIQS, 0);
        assertTrue(adminMultisig.isActionApproved(hash));
        vm.prank(owner);
        accessControl.unfreezeAddress(alice);
        vm.prank(owner);
        bsaRegistry.creditIQS(id, 30, AWARD_REF);
        assertEq(tokenManager.balanceOfIQS(alice), 30);
    }

    function testF02CreditApprovalCannotBeUsedForDifferentAmount() public {
        uint256 id = _recordBSA(alice, 185, 100);
        bytes32 hash = bsaRegistry.getCreditIQSActionHash(id, 30, AWARD_REF);
        _approveActionForConsumerByTwoSigners(hash, address(bsaRegistry));
        vm.prank(owner);
        vm.expectRevert("Action belongs to different consumer");
        bsaRegistry.creditIQS(id, 40, AWARD_REF);
        assertTrue(adminMultisig.isActionApproved(hash));
        assertEq(tokenManager.balanceOfIQS(alice), 0);
    }

    function testF03EveryModuleBlocksDirectAdminUnpause() public {
        address[6] memory modules = [address(tokenManager), address(bsaRegistry), address(conversionModule),
            address(ostTransferModule), address(valuationAnchor), address(governanceRegistry)];
        for (uint256 i = 0; i < modules.length; i++) {
            vm.prank(owner);
            (bool ok,) = modules[i].call(abi.encodeWithSignature("pause()"));
            assertTrue(ok);
            vm.prank(signer2);
            vm.expectRevert("Caller is not emergency controller");
            IReviewPausable(modules[i]).unpause();
            assertTrue(IReviewPausable(modules[i]).paused());
        }
        bytes32 hash = emergencyController.getEmergencyActionHash(IEmergencyController.EmergencyScope.All, false, EMERGENCY_UNPAUSE_ALL_REF);
        _approveActionForConsumerByTwoSigners(hash, address(emergencyController));
        vm.prank(owner);
        emergencyController.unpauseAll(EMERGENCY_UNPAUSE_ALL_REF);
        for (uint256 i = 0; i < modules.length; i++) assertFalse(IReviewPausable(modules[i]).paused());
    }

    function testF03ImmediatePauseAllNeedsNoMultisigButResumeDoes() public {
        vm.prank(signer2);
        emergencyController.pauseAll(EMERGENCY_PAUSE_ALL_REF);
        assertTrue(ostTransferModule.paused());
        assertTrue(bsaRegistry.paused());
        vm.prank(signer2);
        vm.expectRevert("Action belongs to different consumer");
        emergencyController.unpauseAll(EMERGENCY_UNPAUSE_ALL_REF);
        assertTrue(ostTransferModule.paused());
    }

    function _reviewAttemptMigration(address oldWallet, address newWallet) internal {
        bytes32 hash = holderMigrationController.getHolderMigrationActionHash(oldWallet, newWallet, MIGRATION_REF);
        _approveActionForConsumerByAllSigners(hash, address(holderMigrationController));
        vm.warp(vm.getBlockTimestamp() + holderMigrationController.MIGRATION_DELAY());
        vm.prank(owner);
        vm.expectRevert("Wallet has open OST transfers");
        holderMigrationController.migrateHolder(oldWallet, newWallet, MIGRATION_REF);
        assertFalse(tokenManager.retiredHolderWallet(oldWallet));
        assertTrue(adminMultisig.isActionApprovedWithRequiredSignatures(hash, 3));
    }

    function testF04EscrowBlocksSellerMigrationAndReturnUnlocksMigration() public {
        uint256 id = _reviewEscrow();
        _reviewAttemptMigration(alice, aliceNewWallet);
        uint256 deadline = ostTransferModule.transfersf(id).escrowDeadline;
        vm.warp(deadline + 1);
        ostTransferModule.reclaimExpiredEscrow(id);
        bytes32 hash = holderMigrationController.getHolderMigrationActionHash(alice, aliceNewWallet, MIGRATION_REF);
        _approveActionForConsumerByAllSigners(hash, address(holderMigrationController));
        vm.warp(vm.getBlockTimestamp() + holderMigrationController.MIGRATION_DELAY());
        vm.prank(owner);
        holderMigrationController.migrateHolder(alice, aliceNewWallet, MIGRATION_REF);
        assertEq(tokenManager.balanceOfOST(aliceNewWallet), 100);
        assertEq(tokenManager.balanceOfOST(address(ostTransferModule)), 0);
    }

    function testF04RequestedTransferBlocksMigrationUntilCancelled() public {
        _mintOST(alice, 100);
        _makeValidUser(bob);
        vm.prank(alice);
        uint256 id = ostTransferModule.createSellTransferRequest(alice, bob, 30, 200, TRANSFER_REF);
        _reviewAttemptMigration(alice, aliceNewWallet);
        vm.prank(alice);
        ostTransferModule.cancelTransfer(id);
        assertEq(ostTransferModule.openTransferCount(), 0);
        vm.prank(owner);
        holderMigrationController.migrateHolder(alice, aliceNewWallet, MIGRATION_REF);
        assertEq(tokenManager.balanceOfOST(aliceNewWallet), 100);
    }

    function testF04CounteredTransferBlocksMigrationAndRejectionClearsBothCounts() public {
        _mintOST(alice, 100);
        _makeValidUser(bob);
        vm.prank(alice);
        uint256 id = ostTransferModule.createSellTransferRequest(alice, bob, 30, 200, TRANSFER_REF);
        vm.prank(bob);
        ostTransferModule.counterTransfer(id, 20, 190, keccak256("counter"));
        _reviewAttemptMigration(alice, aliceNewWallet);
        vm.prank(owner);
        ostTransferModule.adminRejectTransfer(id, keccak256("reject"));
        assertEq(ostTransferModule.activeTransferCount(alice), 0);
        assertEq(ostTransferModule.activeTransferCount(bob), 0);
        assertEq(ostTransferModule.openTransferCount(), 0);
    }

    function testF04ClosingOneOfTwoRequestsDoesNotUnlockMigration() public {
        _mintOST(alice, 100);
        _makeValidUser(bob);
        vm.startPrank(alice);
        uint256 first = ostTransferModule.createSellTransferRequest(alice, bob, 30, 200, TRANSFER_REF);
        uint256 second = ostTransferModule.createSellTransferRequest(alice, bob, 20, 200, keccak256("second-transfer"));
        ostTransferModule.cancelTransfer(first);
        vm.stopPrank();
        assertEq(ostTransferModule.activeTransferCount(alice), 1);
        assertEq(ostTransferModule.openTransferCount(), 1);
        _reviewAttemptMigration(alice, aliceNewWallet);
        vm.prank(bob);
        ostTransferModule.rejectTransfer(second, keccak256("reject-second"));
        assertEq(ostTransferModule.activeTransferCount(alice), 0);
        assertEq(ostTransferModule.openTransferCount(), 0);
    }

    function testF04BuyerWithOpenTransferCannotMigrate() public {
        _mintOST(alice, 100);
        _mintOST(bob, 10);
        vm.prank(alice);
        uint256 id = ostTransferModule.createSellTransferRequest(alice, bob, 30, 200, TRANSFER_REF);
        _reviewAttemptMigration(bob, aliceNewWallet);
        vm.prank(bob);
        ostTransferModule.rejectTransfer(id, keccak256("buyer-reject"));
        assertEq(ostTransferModule.activeTransferCount(bob), 0);
    }

    function testF04PaymentProofBlocksMigration() public {
        uint256 id = _reviewEscrow();
        _reviewPaymentProof(id);
        _reviewAttemptMigration(alice, aliceNewWallet);
    }

    function testF04ValidatedPaymentBlocksMigration() public {
        uint256 id = _reviewEscrow();
        _reviewSellerValidation(id);
        _reviewAttemptMigration(alice, aliceNewWallet);
    }

    function testF04DisputeBlocksMigrationAndResolutionClearsCounts() public {
        uint256 id = _reviewEscrow();
        vm.prank(alice);
        ostTransferModule.markTransferDisputed(id, keccak256("dispute"));
        _reviewAttemptMigration(alice, aliceNewWallet);
        bytes32 hash = ostTransferModule.getAdminResolveTransferActionHash(id, false, keccak256("resolution"), RECEIPT_HASH);
        _approveActionForConsumerByTwoSigners(hash, address(ostTransferModule));
        vm.prank(owner);
        ostTransferModule.adminResolveTransfer(id, false, keccak256("resolution"), RECEIPT_HASH);
        assertEq(ostTransferModule.openTransferCount(), 0);
        vm.prank(owner);
        holderMigrationController.migrateHolder(alice, aliceNewWallet, MIGRATION_REF);
        assertEq(tokenManager.balanceOfOST(aliceNewWallet), 100);
    }

    function testF04EscrowRotationCannotHideOpenRequests() public {
        _mintOST(alice, 100);
        _makeValidUser(bob);
        vm.prank(alice);
        ostTransferModule.createSellTransferRequest(alice, bob, 30, 200, TRANSFER_REF);
        OSTTransferModule replacement = _m8PrepareReplacement();
        vm.prank(owner);
        ostTransferModule.pause();
        vm.prank(owner);
        vm.expectRevert("Old escrow has open transfers");
        tokenManager.rotateOSTEscrowAddress(address(replacement));
    }

    function testF06FakePaymentProofCanBeReclaimedBySellerAfterDeadline() public {
        uint256 id = _reviewEscrow();
        _reviewPaymentProof(id);
        uint256 deadline = ostTransferModule.paymentValidationDeadline(id);
        vm.warp(deadline);
        vm.prank(alice);
        vm.expectRevert("Escrow deadline not reached");
        ostTransferModule.reclaimExpiredEscrow(id);
        vm.warp(deadline + 1);
        vm.prank(bob);
        vm.expectRevert("Only seller can reclaim payment proof escrow");
        ostTransferModule.reclaimExpiredEscrow(id);
        vm.prank(alice);
        ostTransferModule.reclaimExpiredEscrow(id);
        assertEq(tokenManager.balanceOfOST(alice), 100);
        assertEq(ostTransferModule.openTransferCount(), 0);
        vm.prank(alice);
        vm.expectRevert("Escrow is not reclaimable");
        ostTransferModule.reclaimExpiredEscrow(id);
    }

    function testF06AdminProofAlsoHasDeadlineAndCannotResetIt() public {
        uint256 id = _reviewEscrow();
        vm.prank(owner);
        ostTransferModule.adminRegisterBuyerPaymentProof(id, PAYMENT_PROOF_HASH);
        uint256 deadline = ostTransferModule.paymentValidationDeadline(id);
        vm.warp(deadline - 1);
        vm.prank(owner);
        vm.expectRevert("Transfer is not escrowed");
        ostTransferModule.adminRegisterBuyerPaymentProof(id, keccak256("replacement-proof"));
        assertEq(ostTransferModule.paymentValidationDeadline(id), deadline);
        vm.warp(deadline + 1);
        vm.prank(alice);
        ostTransferModule.reclaimExpiredEscrow(id);
        assertEq(tokenManager.balanceOfOST(alice), 100);
    }

    function testF06DisputePreventsAutomaticReturnAfterProofDeadline() public {
        uint256 id = _reviewEscrow();
        _reviewPaymentProof(id);
        vm.prank(bob);
        ostTransferModule.markTransferDisputed(id, keccak256("real-payment-disputed"));
        vm.warp(ostTransferModule.paymentValidationDeadline(id) + 1);
        vm.prank(alice);
        vm.expectRevert("Escrow is not reclaimable");
        ostTransferModule.reclaimExpiredEscrow(id);
        assertEq(tokenManager.balanceOfOST(address(ostTransferModule)), 30);
    }

    function testF06SellerValidationPreventsAutomaticReturn() public {
        uint256 id = _reviewEscrow();
        _reviewSellerValidation(id);
        vm.warp(ostTransferModule.paymentValidationDeadline(id) + 1);
        vm.prank(alice);
        vm.expectRevert("Escrow is not reclaimable");
        ostTransferModule.reclaimExpiredEscrow(id);
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

    function testF07ConfirmedCapitalReversalRequiresMultisigAndReleasesReservation() public {
        (uint256 bsaId, uint256 id) = _reviewCapitalReceived();
        bytes32 reason = keccak256("payment-reversed");
        vm.prank(owner);
        vm.expectRevert("Action belongs to different consumer");
        conversionModule.rejectExercise(id, reason);
        bytes32 hash = conversionModule.getRejectCapitalReceivedExerciseActionHash(id, reason);
        _proposeTestAction(hash, address(conversionModule));
        vm.prank(owner);
        adminMultisig.approveActionForConsumer(hash, address(conversionModule));
        vm.prank(owner);
        vm.expectRevert("Action not approved");
        conversionModule.rejectExercise(id, reason);
        assertEq(conversionModule.pendingExerciseIQSForBSA(bsaId), 30);
        vm.prank(signer2);
        adminMultisig.approveActionForConsumer(hash, address(conversionModule));
        vm.prank(owner);
        conversionModule.rejectExercise(id, reason);
        assertEq(conversionModule.pendingExerciseIQSForBSA(bsaId), 0);
        assertEq(uint256(conversionModule.getExerciseRequest(id).status), uint256(IConversionModule.ExerciseStatus.Rejected));
        assertEq(conversionModule.getExerciseRequest(id).capitalPaymentHash, CAPITAL_PAYMENT_HASH);
        assertEq(tokenManager.balanceOfIQS(alice), 100);
        assertEq(tokenManager.balanceOfOST(alice), 0);
        _approveActionForConsumerByTwoSigners(bsaRegistry.getCancelBSAActionHash(bsaId, reason), address(bsaRegistry));
        vm.prank(owner);
        bsaRegistry.cancelBSA(bsaId, reason);
        assertEq(tokenManager.balanceOfIQS(alice), 0);
    }

    function testF07CapitalReversalBindsReasonAndCannotReverseSettledExercise() public {
        (, uint256 id) = _reviewCapitalReceived();
        bytes32 reason = keccak256("reversal");
        bytes32 hash = conversionModule.getRejectCapitalReceivedExerciseActionHash(id, reason);
        _approveActionForConsumerByTwoSigners(hash, address(conversionModule));
        vm.prank(owner);
        vm.expectRevert("Action belongs to different consumer");
        conversionModule.rejectExercise(id, keccak256("other-reason"));
        bytes32 finalize = conversionModule.getFinalizeExerciseActionHash(id, RECEIPT_HASH);
        _approveActionForConsumerByTwoSigners(finalize, address(conversionModule));
        vm.prank(owner);
        conversionModule.finalizeExercise(id, RECEIPT_HASH);
        vm.prank(owner);
        vm.expectRevert("Invalid status");
        conversionModule.rejectExercise(id, reason);
        assertEq(tokenManager.balanceOfOST(alice), 30);
    }

    function testF07CapitalReversalAfterExpiryBurnsReleasedIQS() public {
        (uint256 bsaId, uint256 id) = _reviewCapitalReceived();
        bytes32 reason = keccak256("expired-capital-reversal");
        vm.warp(bsaRegistry.bsasf(bsaId).expiryDate + 1);
        bytes32 hash = conversionModule.getRejectCapitalReceivedExerciseActionHash(id, reason);
        _approveActionForConsumerByTwoSigners(hash, address(conversionModule));
        vm.prank(owner);
        conversionModule.rejectExercise(id, reason);
        assertEq(conversionModule.pendingExerciseIQSForBSA(bsaId), 0);
        assertEq(tokenManager.balanceOfIQS(alice), 0);
        assertEq(bsaRegistry.expiredIQSBurnedOf(bsaId), 100);
    }

    function testF08PreanchoredGovernanceHashCannotBlockOfficialOutcome() public {
        uint256[] memory answers = new uint256[](1);
        uint256[] memory powers = new uint256[](1);
        answers[0] = 1;
        powers[0] = 10;
        bytes32 result = governanceRegistry.calculateResultHashWithBallotRoot(
            99, VOTE_METADATA_HASH, BALLOT_ROOT, 1, answers, powers,
            IGovernanceRegistry.VotingPopulation.IQSAndOSTHolders, IGovernanceRegistry.VotingPowerSource.IQSAndOST
        );
        bytes32 key = hashRegistry.moduleAnchorKey(address(governanceRegistry), result);
        vm.startPrank(owner);
        hashRegistry.anchorHash(result, "VOTE_RESULT", 99);
        hashRegistry.anchorHash(key, "VOTE_RESULT", 99);
        vm.stopPrank();
        bytes32 hash = governanceRegistry.getRecordOutcomeActionHash(
            99, VOTE_METADATA_HASH, BALLOT_ROOT, 1, answers, powers,
            IGovernanceRegistry.VotingPopulation.IQSAndOSTHolders, IGovernanceRegistry.VotingPowerSource.IQSAndOST
        );
        _approveActionForConsumerByTwoSigners(hash, address(governanceRegistry));
        vm.prank(owner);
        governanceRegistry.recordOutcomeWithBallotRoot(
            99, VOTE_METADATA_HASH, BALLOT_ROOT, 1, answers, powers,
            IGovernanceRegistry.VotingPopulation.IQSAndOSTHolders, IGovernanceRegistry.VotingPowerSource.IQSAndOST
        );
        (bool exists, address submitter,,,) = hashRegistry.getModuleHashRecord(address(governanceRegistry), result);
        assertTrue(exists);
        assertEq(submitter, address(governanceRegistry));
        assertTrue(governanceRegistry.isVoteOutcomeRecorded(99));
    }

    function testF08PreanchoredValuationCannotBlockOfficialPublication() public {
        vm.prank(owner);
        hashRegistry.anchorHash(VALUATION_HASH, "VALUATION", 1);
        bytes32 hash = valuationAnchor.getPublishValuationActionHash(PERIOD_Q3_2026, VALUATION_HASH, METHODOLOGY_HASH, 1, false, 0);
        _approveActionForConsumerByTwoSigners(hash, address(valuationAnchor));
        vm.prank(owner);
        valuationAnchor.publishQuarterlyValuation(PERIOD_Q3_2026, VALUATION_HASH, METHODOLOGY_HASH, 1);
        (bool exists, address submitter,,,) = hashRegistry.getModuleHashRecord(address(valuationAnchor), VALUATION_HASH);
        assertTrue(exists);
        assertEq(submitter, address(valuationAnchor));
    }

    function testF08AnchorRoleCannotOccupyAnotherModuleNamespace() public {
        bytes32 role = accessControl.ROLE_ANCHOR();
        vm.prank(owner);
        accessControl.setRole(role, mallory, true);
        vm.prank(mallory);
        hashRegistry.anchorModuleHash(VALUATION_HASH, "VALUATION", 1);
        (bool exists,,,,) = hashRegistry.getModuleHashRecord(address(valuationAnchor), VALUATION_HASH);
        assertFalse(exists);
        vm.prank(mallory);
        vm.expectRevert("Module hash already anchored");
        hashRegistry.anchorModuleHash(VALUATION_HASH, "VALUATION", 1);
    }

}
