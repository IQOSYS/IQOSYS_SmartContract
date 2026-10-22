// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/AccessControl.sol";
import "../src/AdminMultisig.sol";
import "../src/TokenManager.sol";
import "../src/OSTTransferModule.sol";

contract InitialShareRegistrationTest is Test {
    AccessControl ac;
    AdminMultisig multisig;
    TokenManager tm;
    OSTTransferModule escrow;
    address owner = address(0xA0);
    address first = address(0xA1);
    address second = address(0xA2);
    address third = address(0xA3);
    address alice = address(0x1001);
    address bob = address(0x1002);
    // SHA-256 digests of the fixture evidence, precomputed outside prank/expectRevert.
    bytes32 constant REGISTER_SHA256 = hex"c4d54bb5d6eb0e339221aa2ac8a061c59f4aeecce8d0abdda550b624e0823377";
    bytes32 constant REASON = hex"e2d986efcc790bee0df18852581041d8521aeff52ceb26b55ddb1bf9ce171582";

    function setUp() public {
        vm.warp(100);
        vm.startPrank(owner);
        ac = new AccessControl(owner);
        ac.addAdmin(first); ac.addAdmin(second); ac.addAdmin(third);
        address[] memory signers = new address[](3);
        signers[0] = first; signers[1] = second; signers[2] = third;
        multisig = new AdminMultisig(address(ac), signers, 2);
        ac.setAdminSignerController(address(multisig));
        tm = new TokenManager(address(ac));
        escrow = new OSTTransferModule(address(ac), address(tm), address(multisig));
        tm.setTokenOperator(address(escrow), true);
        tm.setTokenOperator(owner, true);
        tm.setOSTEscrowAddress(address(escrow));
        multisig.setActionConsumer(address(tm), true);
        ac.setRole(ac.ROLE_ACCOUNT_MANAGER(), address(tm), true);
        ac.setRole(ac.ROLE_EMERGENCY(), owner, true);
        ac.approveHolder(alice); ac.approveHolder(bob);
        vm.stopPrank();
    }

    function _list() private view returns (address[] memory holders, uint256[] memory amounts) {
        holders = new address[](2); amounts = new uint256[](2);
        holders[0] = alice; holders[1] = bob; amounts[0] = 40; amounts[1] = 60;
    }

    function _request(address[] memory holders, uint256[] memory amounts, uint256 total, bytes32 digest)
        private returns (uint256)
    {
        vm.prank(first);
        return tm.requestInitialShareRegistration(holders, amounts, total, digest);
    }

    function _request() private returns (uint256) {
        (address[] memory holders, uint256[] memory amounts) = _list();
        return _request(holders, amounts, 100, REGISTER_SHA256);
    }

    function _propose(bytes32 hash, bytes memory data, address consumer) private {
        bytes4 selector;
        assembly { selector := mload(add(data, 32)) }
        vm.prank(first);
        multisig.proposeAction(hash, consumer, selector, keccak256(data), "Opaque genesis register reference", block.timestamp + 7 days);
    }

    function _approve(bytes32 hash, address signer, address consumer) private {
        vm.prank(signer); multisig.approveActionForConsumer(hash, consumer);
    }

    function _data(uint256 id, address[] memory holders, uint256[] memory amounts, uint256 total, bytes32 digest)
        private view returns (bytes memory)
    {
        return abi.encodeCall(tm.registerInitialShares, (id, holders, amounts, total, digest));
    }

    function _approveRegistration(uint256 id) private returns (bytes32 hash) {
        (address[] memory holders, uint256[] memory amounts) = _list();
        hash = tm.getInitialShareRegistrationActionHash(id);
        _propose(hash, _data(id, holders, amounts, 100, REGISTER_SHA256), address(tm));
        _approve(hash, first, address(tm)); _approve(hash, second, address(tm));
    }

    function _execute(uint256 id) private {
        (address[] memory holders, uint256[] memory amounts) = _list();
        vm.prank(owner); tm.registerInitialShares(id, holders, amounts, 100, REGISTER_SHA256);
    }

    function _ready(uint256 id) private view returns (uint256) { return tm.initialShareRegistrationReadyAt(id); }

    function _abortProposal(uint256 id, bytes32 reason) private returns (bytes32 hash) {
        hash = tm.getAbortInitialShareRegistrationActionHash(id, reason);
        _propose(hash, abi.encodeCall(tm.abortInitialShareRegistration, (id, reason)), address(tm));
    }

    function _abort(uint256 id, bytes32 reason) private {
        vm.prank(owner); tm.abortInitialShareRegistration(id, reason);
    }

    function _assertUnconsumed(bytes32 hash) private view {
        (, bool consumed,) = multisig.getApprovalState(hash); assertFalse(consumed);
        assertEq(tm.totalSupplyOSTf(), 0);
        assertEq(tm.balanceOfOST(alice), 0); assertEq(tm.balanceOfOST(bob), 0);
        assertFalse(tm.initialShareRegistrationLocked());
    }

    function testCompleteAtomicRegistrationAfterSecondSignatureAndPermanentLock() public {
        uint256 id = _request();
        assertEq(id, 1); assertEq(_ready(id), 0);
        assertEq(tm.totalSupplyOSTf(), 0); assertEq(tm.registeredHolderCount(), 0);
        ITokenManager.InitialShareRegistration memory request = tm.initialShareRegistrations(id);
        assertEq(request.declaredTotal, 100); assertEq(request.registerSha256, REGISTER_SHA256);
        assertEq(request.holderCount, 2); assertEq(request.requestedBy, first);
        (address[] memory holders, uint256[] memory amounts) = _list();
        bytes32 hash = tm.getInitialShareRegistrationActionHash(id);
        _propose(hash, _data(id, holders, amounts, 100, REGISTER_SHA256), address(tm));
        _approve(hash, first, address(tm));
        vm.warp(block.timestamp + 1 days); assertEq(_ready(id), 0);
        vm.expectRevert("Action not approved"); _execute(id);
        _approve(hash, second, address(tm));
        uint256 ready = _ready(id); assertEq(ready, block.timestamp + 48 hours);
        vm.warp(ready - 1); vm.expectRevert("Initial registration delay not elapsed"); _execute(id);
        vm.warp(ready); _execute(id);
        assertEq(tm.totalSupplyOSTf(), 100); assertEq(tm.balanceOfOST(alice), 40); assertEq(tm.balanceOfOST(bob), 60);
        assertEq(tm.registeredHolderCount(), 2); assertTrue(tm.hasHolderSlot(alice)); assertTrue(tm.hasHolderSlot(bob));
        (address[] memory registered, uint256[] memory balances) = tm.getOSTHolders();
        assertEq(registered, holders); assertEq(balances, amounts);
        assertTrue(tm.initialShareRegistrationLocked()); assertEq(tm.pendingInitialShareRegistrationId(), 0);
        assertEq(tm.initialShareRegistrations(id).executedAt, ready); assertEq(_ready(id), 0);
        (, bool consumed,) = multisig.getApprovalState(hash); assertTrue(consumed);
        vm.expectRevert("Initial registration locked"); _execute(id);
        vm.expectRevert("Initial registration locked"); _request();
        vm.expectRevert("Initial registration locked"); _abort(id, REASON);
    }

    function testRequestEmitsAlertWithNoBalancesOrSlotsChanged() public {
        vm.recordLogs(); uint256 id = _request();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1); assertEq(logs[0].emitter, address(tm));
        assertEq(logs[0].topics[0], keccak256("InitialShareRegistrationRequested(uint256,bytes32,bytes32,bytes32,uint256,uint256,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(id)); assertEq(logs[0].topics[2], tm.getInitialShareRegistrationActionHash(id));
        assertEq(logs[0].topics[3], REGISTER_SHA256);
        assertEq(tm.totalSupplyOSTf(), 0); assertEq(tm.registeredHolderCount(), 0);
    }

    function testOneApprovalCannotRegisterEvenAfter48Hours() public {
        uint256 id = _request(); (address[] memory holders, uint256[] memory amounts) = _list();
        bytes32 hash = tm.getInitialShareRegistrationActionHash(id);
        _propose(hash, _data(id, holders, amounts, 100, REGISTER_SHA256), address(tm));
        _approve(hash, first, address(tm)); vm.warp(block.timestamp + 48 hours);
        vm.expectRevert("Action not approved"); _execute(id); _assertUnconsumed(hash);
    }

    function testNormalIssuanceIsBlockedDuringPendingGenesisAndResumesAfterCompletion() public {
        uint256 id = _request();
        vm.prank(owner); vm.expectRevert("Initial registration pending"); tm.mintOSTTo(alice, 1, REGISTER_SHA256);
        _approveRegistration(id); vm.warp(_ready(id)); _execute(id);
        vm.prank(owner); tm.mintOSTTo(alice, 1, REGISTER_SHA256);
        assertEq(tm.totalSupplyOSTf(), 101); assertTrue(tm.initialShareRegistrationLocked());
    }

    function testNonzeroOSTSupplyRejectsGenesisWithoutLockingOrCreatingAttempt() public {
        vm.prank(owner); tm.mintOSTTo(alice, 1, REGISTER_SHA256);
        vm.expectRevert("Initial registration requires zero OST supply"); _request();
        assertEq(tm.initialShareRegistrationCount(), 0); assertEq(tm.pendingInitialShareRegistrationId(), 0);
        assertFalse(tm.initialShareRegistrationLocked()); assertEq(tm.totalSupplyOSTf(), 1);
    }

    function testSumMustMatchDeclaredTotal() public {
        (address[] memory holders, uint256[] memory amounts) = _list();
        vm.expectRevert("Initial register total mismatch"); _request(holders, amounts, 99, REGISTER_SHA256);
        vm.expectRevert("Initial register total mismatch"); _request(holders, amounts, 101, REGISTER_SHA256);
    }

    function testMalformedEmptyDuplicateZeroAndUnsortedInputsRevert() public {
        address[] memory empty = new address[](0); uint256[] memory noAmounts = new uint256[](0);
        vm.expectRevert("Invalid initial holder count"); _request(empty, noAmounts, 1, REGISTER_SHA256);
        (address[] memory holders, uint256[] memory amounts) = _list();
        vm.expectRevert("Initial register length mismatch"); _request(holders, noAmounts, 100, REGISTER_SHA256);
        vm.expectRevert("Declared total required"); _request(holders, amounts, 0, REGISTER_SHA256);
        vm.expectRevert("Register SHA-256 required"); _request(holders, amounts, 100, bytes32(0));
        amounts[1] = 0; vm.expectRevert("Initial quantity required"); _request(holders, amounts, 40, REGISTER_SHA256);
        amounts[1] = 60; holders[1] = alice;
        vm.expectRevert("Initial holders must be unique and sorted"); _request(holders, amounts, 100, REGISTER_SHA256);
        holders[0] = bob; holders[1] = alice;
        vm.expectRevert("Initial holders must be unique and sorted"); _request(holders, amounts, 100, REGISTER_SHA256);
        holders[0] = address(0); holders[1] = bob;
        vm.expectRevert("Initial holders must be unique and sorted"); _request(holders, amounts, 100, REGISTER_SHA256);
    }

    function testOverflowCannotMakeDeclaredSumAppearValid() public {
        (address[] memory holders, uint256[] memory amounts) = _list();
        amounts[0] = type(uint256).max; amounts[1] = 1;
        vm.expectRevert(stdError.arithmeticError); _request(holders, amounts, 1, REGISTER_SHA256);
    }

    function testFrozenUnapprovedAndUnauthorizedWalletsRevert() public {
        vm.prank(owner); ac.freezeAddress(bob);
        vm.expectRevert("Sender is frozen"); _request();
        vm.startPrank(owner); ac.unfreezeAddress(bob); ac.revokeAuthorization(bob); vm.stopPrank();
        vm.expectRevert("Sender not authorized"); _request();
        vm.startPrank(owner); ac.authorizeAddress(bob); ac.removeFromWhiteList(bob); vm.stopPrank();
        vm.expectRevert("Sender not white-listed"); _request();
    }

    function testEscrowCannotBeRegisteredAsBeneficialHolder() public {
        address[] memory holders = new address[](1); holders[0] = address(escrow);
        uint256[] memory amounts = new uint256[](1); amounts[0] = 100;
        vm.expectRevert("Invalid canonical holder"); _request(holders, amounts, 100, REGISTER_SHA256);
    }

    function testRetiredWalletCannotReturnThroughGenesisEvenIfReapproved() public {
        vm.startPrank(owner);
        tm.mintIQSTo(alice, 1, REGISTER_SHA256);
        tm.setWalletMigrationController(owner);
        tm.adminMigrateWallet(alice, address(0x1003), REASON);
        ac.unfreezeAddress(alice);
        ac.approveHolder(alice);
        vm.stopPrank();
        assertTrue(tm.retiredHolderWallet(alice));
        vm.expectRevert("Invalid canonical holder"); _request();
    }

    function testExistingFullHolderRegisterDoesNotDoubleCountImportedHolders() public {
        vm.startPrank(owner);
        tm.mintIQSTo(alice, 1, REGISTER_SHA256); tm.mintIQSTo(bob, 1, REGISTER_SHA256);
        for (uint256 i; i < 147; i++) {
            address holder = address(uint160(0x3000 + i)); ac.approveHolder(holder); tm.mintIQSTo(holder, 1, REGISTER_SHA256);
        }
        vm.stopPrank(); assertEq(tm.registeredHolderCount(), 149);
        uint256 id = _request(); _approveRegistration(id); vm.warp(_ready(id)); _execute(id);
        assertEq(tm.registeredHolderCount(), 149); assertEq(tm.totalSupplyOSTf(), 100);
    }

    function testBootstrapMustRegisterTokenManagerAsMultisigConsumer() public {
        // Bootstrap permissions are still open in this isolated fixture.
        vm.prank(owner); multisig.setActionConsumer(address(tm), false);
        vm.expectRevert("TokenManager consumer not registered"); _request();
    }

    function testAbortWithoutRegistrationApprovalsReleasesPendingIssuanceGate() public {
        uint256 id = _request(); bytes32 hash = _abortProposal(id, REASON);
        _approve(hash, first, address(tm)); _approve(hash, second, address(tm)); _abort(id, REASON);
        assertEq(tm.initialShareRegistrationReadyAt(id), 0);
        vm.prank(owner); tm.mintOSTTo(alice, 1, REGISTER_SHA256);
        assertEq(tm.totalSupplyOSTf(), 1); assertFalse(tm.initialShareRegistrationLocked());
        vm.expectRevert("Initial registration requires zero OST supply"); _request();
    }

    function testRequestCannotOverwriteAnotherPendingManifest() public {
        uint256 id = _request();
        vm.expectRevert("Initial registration pending"); _request(); assertEq(tm.pendingInitialShareRegistrationId(), id);
    }

    function testApprovalBindsAllHoldersQuantitiesDeclaredTotalAndSignedExtractHash() public {
        uint256 id = _request(); bytes32 hash = _approveRegistration(id); vm.warp(_ready(id));
        (address[] memory holders, uint256[] memory amounts) = _list();
        amounts[0] = 39; amounts[1] = 61;
        vm.prank(owner); vm.expectRevert("Initial registration data mismatch"); tm.registerInitialShares(id, holders, amounts, 100, REGISTER_SHA256);
        amounts[0] = 40; amounts[1] = 60; holders[1] = address(0x1003);
        vm.prank(owner); vm.expectRevert("Initial registration data mismatch"); tm.registerInitialShares(id, holders, amounts, 100, REGISTER_SHA256);
        holders[1] = bob;
        vm.prank(owner); vm.expectRevert("Initial registration data mismatch"); tm.registerInitialShares(id, holders, amounts, 101, REGISTER_SHA256);
        vm.prank(owner); vm.expectRevert("Initial registration data mismatch"); tm.registerInitialShares(id, holders, amounts, 100, bytes32(hex"8ed65cf34fdfc8bf3289f10523490a79cd1c1639ff4a4e25522d6228c877108f"));
        _assertUnconsumed(hash); _execute(id);
    }

    function testPartialImportCannotConsumeApprovedWholeRegister() public {
        uint256 id = _request(); bytes32 hash = _approveRegistration(id); vm.warp(_ready(id));
        address[] memory holders = new address[](1); holders[0] = alice;
        uint256[] memory amounts = new uint256[](1); amounts[0] = 40;
        vm.prank(owner); vm.expectRevert("Initial registration data mismatch"); tm.registerInitialShares(id, holders, amounts, 40, REGISTER_SHA256);
        _assertUnconsumed(hash); assertEq(tm.pendingInitialShareRegistrationId(), id);
    }

    function testEligibilityIsRecheckedAtExecutionWithoutPartialMintOrApprovalConsumption() public {
        uint256 id = _request(); bytes32 hash = _approveRegistration(id); vm.warp(_ready(id));
        vm.prank(owner); ac.freezeAddress(bob);
        vm.expectRevert("Sender is frozen"); _execute(id);
        _assertUnconsumed(hash); assertEq(tm.registeredHolderCount(), 0);
        assertEq(tm.initialShareRegistrations(id).executedAt, 0);
        vm.prank(owner); ac.unfreezeAddress(bob); _execute(id);
    }

    function testWrongProposedCalldataCannotExecuteEvenWithQuorum() public {
        uint256 id = _request(); bytes32 hash = tm.getInitialShareRegistrationActionHash(id);
        (address[] memory holders, uint256[] memory amounts) = _list();
        _propose(hash, _data(id, holders, amounts, 101, REGISTER_SHA256), address(tm));
        _approve(hash, first, address(tm)); _approve(hash, second, address(tm)); vm.warp(_ready(id));
        vm.expectRevert("Initial registration intent mismatch"); _execute(id); _assertUnconsumed(hash);
    }

    function testRevocationAndReapprovalRestartsDelay() public {
        uint256 id = _request(); bytes32 hash = _approveRegistration(id); uint256 oldReady = _ready(id);
        vm.warp(oldReady - 1); vm.prank(second); multisig.revokeApproval(hash); assertEq(_ready(id), 0);
        _approve(hash, second, address(tm)); assertEq(_ready(id), block.timestamp + 48 hours);
        vm.warp(oldReady); vm.expectRevert("Initial registration delay not elapsed"); _execute(id);
        vm.warp(_ready(id)); _execute(id);
    }

    function testExpiredApprovalCannotExecuteAndRenewalNeedsNewDelay() public {
        uint256 id = _request(); _approveRegistration(id); vm.warp(block.timestamp + 7 days + 1);
        assertEq(_ready(id), 0); vm.expectRevert("Action not approved"); _execute(id);
        _approveRegistration(id); assertEq(_ready(id), block.timestamp + 48 hours);
        vm.expectRevert("Initial registration delay not elapsed"); _execute(id);
        vm.warp(_ready(id)); _execute(id);
    }

    function testPreapprovalCannotSkip48HoursAfterTheRequestAlert() public {
        (address[] memory holders, uint256[] memory amounts) = _list();
        bytes32 allocationsHash = keccak256(abi.encode(holders, amounts));
        bytes32 hash = keccak256(abi.encode(address(tm), block.chainid, "INITIAL_SHARE_REGISTRATION", uint256(1), allocationsHash, uint256(100), REGISTER_SHA256));
        _propose(hash, _data(1, holders, amounts, 100, REGISTER_SHA256), address(tm));
        _approve(hash, first, address(tm)); _approve(hash, second, address(tm)); vm.warp(block.timestamp + 48 hours);
        uint256 id = _request(); assertEq(tm.getInitialShareRegistrationActionHash(id), hash);
        assertEq(_ready(id), block.timestamp + 48 hours);
        vm.expectRevert("Initial registration delay not elapsed"); _execute(id);
        vm.warp(_ready(id)); _execute(id);
    }

    function testAbortNeedsSeparateQuorumAndIsImmediateEvenWhilePaused() public {
        uint256 id = _request(); bytes32 registrationHash = _approveRegistration(id);
        bytes32 abortHash = _abortProposal(id, REASON); _approve(abortHash, first, address(tm));
        vm.expectRevert("Action not approved"); _abort(id, REASON);
        _approve(abortHash, second, address(tm)); vm.prank(owner); tm.pause();
        vm.recordLogs(); _abort(id, REASON); Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs[logs.length - 1].topics[0], keccak256("InitialShareRegistrationAborted(uint256,bytes32,bytes32,address,uint256)"));
        assertTrue(tm.initialShareRegistrations(id).aborted); assertEq(_ready(id), 0);
        assertEq(tm.pendingInitialShareRegistrationId(), 0); _assertUnconsumed(registrationHash);
        vm.prank(owner); tm.unpause();
        vm.expectRevert("Initial registration not pending"); _execute(id);
    }

    function testAbortAfterDelayPreventsExecutionAndRetryUsesFreshActionAndDelay() public {
        uint256 id = _request(); bytes32 oldHash = _approveRegistration(id); vm.warp(_ready(id));
        bytes32 abortHash = _abortProposal(id, REASON); _approve(abortHash, first, address(tm)); _approve(abortHash, second, address(tm));
        _abort(id, REASON); vm.expectRevert("Initial registration not pending"); _execute(id);
        uint256 retry = _request(); assertEq(retry, id + 1);
        bytes32 newHash = _approveRegistration(retry); assertNotEq(newHash, oldHash);
        assertEq(_ready(retry), block.timestamp + 48 hours);
        vm.expectRevert("Initial registration delay not elapsed"); _execute(retry);
        vm.warp(_ready(retry)); _execute(retry);
    }

    function testAbortBindsAttemptAndReasonAndCannotBeReplayed() public {
        uint256 id = _request(); bytes32 abortHash = _abortProposal(id, REASON);
        _approve(abortHash, first, address(tm)); _approve(abortHash, second, address(tm));
        vm.expectRevert("Initial registration intent mismatch"); _abort(id, bytes32(hex"c11123b4c19a06f31f8514afb588b6b7af1d5601ae44bdbde19cea3eb4328c63"));
        vm.expectRevert("Reason hash required"); _abort(id, bytes32(0));
        _abort(id, REASON); vm.expectRevert("Initial registration not pending"); _abort(id, REASON);
        (, bool consumed,) = multisig.getApprovalState(abortHash); assertTrue(consumed);
    }

    function testOnlySignerAdminCanRequestAndOnlyAdminCanExecuteOrAbort() public {
        (address[] memory holders, uint256[] memory amounts) = _list();
        vm.prank(alice); vm.expectRevert("Caller is not an admin"); tm.requestInitialShareRegistration(holders, amounts, 100, REGISTER_SHA256);
        vm.prank(owner); vm.expectRevert("Caller is not a signer"); tm.requestInitialShareRegistration(holders, amounts, 100, REGISTER_SHA256);
        uint256 id = _request(); _approveRegistration(id); vm.warp(_ready(id));
        vm.prank(alice); vm.expectRevert("Caller is not an admin"); tm.registerInitialShares(id, holders, amounts, 100, REGISTER_SHA256);
        vm.prank(alice); vm.expectRevert("Caller is not an admin"); tm.abortInitialShareRegistration(id, REASON);
    }

    function testPausedTokenManagerCannotStartOrExecuteGenesis() public {
        vm.prank(owner); tm.pause(); vm.expectRevert(); _request();
        vm.prank(owner); tm.unpause(); uint256 id = _request(); bytes32 hash = _approveRegistration(id); vm.warp(_ready(id));
        vm.prank(owner); tm.pause(); vm.expectRevert(); _execute(id); _assertUnconsumed(hash);
    }

    function testExactly149HoldersRegisterInOneAtomicCall() public {
        address[] memory holders = new address[](149); uint256[] memory amounts = new uint256[](149);
        vm.startPrank(owner);
        for (uint256 i; i < 149; i++) { holders[i] = address(uint160(0x2000 + i)); amounts[i] = i + 1; ac.approveHolder(holders[i]); }
        vm.stopPrank(); uint256 total = 149 * 150 / 2;
        uint256 id = _request(holders, amounts, total, REGISTER_SHA256); bytes32 hash = tm.getInitialShareRegistrationActionHash(id);
        _propose(hash, _data(id, holders, amounts, total, REGISTER_SHA256), address(tm));
        _approve(hash, first, address(tm)); _approve(hash, second, address(tm)); vm.warp(_ready(id));
        vm.prank(owner); uint256 before = gasleft(); tm.registerInitialShares(id, holders, amounts, total, REGISTER_SHA256);
        uint256 used = before - gasleft(); emit log_named_uint("149-holder registration execution gas", used);
        assertLt(used, 20_000_000);
        assertEq(tm.registeredHolderCount(), 149); assertEq(tm.totalSupplyOSTf(), total);
        for (uint256 i; i < 149; i++) assertEq(tm.balanceOfOST(holders[i]), amounts[i]);
        (address[] memory registered,) = tm.getOSTHolders(); assertEq(registered.length, 149);
    }

    function test150HoldersCannotBeRequested() public {
        address[] memory holders = new address[](150); uint256[] memory amounts = new uint256[](150);
        vm.expectRevert("Invalid initial holder count"); _request(holders, amounts, 150, REGISTER_SHA256);
    }

    function testExistingIQSHoldersReuseSlotsAndIQSSupplyIsUnchanged() public {
        vm.prank(owner); tm.mintIQSTo(alice, 50, REGISTER_SHA256);
        uint256 id = _request(); _approveRegistration(id); vm.warp(_ready(id)); _execute(id);
        assertEq(tm.registeredHolderCount(), 2); assertEq(tm.totalSupplyIQS(), 50); assertEq(tm.balanceOfIQS(alice), 50);
        assertEq(tm.totalSupplyOSTf(), 100);
    }

    function testPermanentSlotsCountEvenAfterIQSBalanceIsZero() public {
        vm.startPrank(owner);
        for (uint256 i; i < 148; i++) {
            address holder = address(uint160(0x3000 + i)); ac.approveHolder(holder);
            tm.mintIQSTo(holder, 1, REGISTER_SHA256); tm.burnIQS(1, holder);
        }
        vm.stopPrank(); assertEq(tm.totalSupplyIQS(), 0); assertEq(tm.registeredHolderCount(), 148);
        vm.expectRevert("Holder cap reached"); _request();
        assertEq(tm.totalSupplyOSTf(), 0); assertFalse(tm.initialShareRegistrationLocked());
    }

    function testCapRecheckedAtExecutionAndFailurePreservesEntireRegisterAndApprovals() public {
        uint256 id = _request(); bytes32 hash = _approveRegistration(id);
        vm.startPrank(owner);
        for (uint256 i; i < 148; i++) {
            address holder = address(uint160(0x3000 + i)); ac.approveHolder(holder); tm.mintIQSTo(holder, 1, REGISTER_SHA256);
        }
        vm.stopPrank(); vm.warp(_ready(id)); vm.expectRevert("Holder cap reached"); _execute(id);
        _assertUnconsumed(hash); assertEq(tm.registeredHolderCount(), 148);
        assertFalse(tm.hasHolderSlot(alice)); assertFalse(tm.hasHolderSlot(bob));
    }

    function testSignerRotationInvalidatesPendingQuorumAndRestartsDelay() public {
        uint256 id = _request(); _approveRegistration(id); address next = address(0xA4);
        bytes32 hash = multisig.getReplaceSignerActionHash(third, next, REASON);
        _propose(hash, abi.encodeCall(multisig.replaceSigner, (third, next, REASON)), address(multisig));
        _approve(hash, first, address(multisig)); _approve(hash, second, address(multisig));
        vm.warp(block.timestamp + 48 hours); vm.prank(owner); multisig.replaceSigner(third, next, REASON);
        assertEq(_ready(id), 0); vm.expectRevert("Action not approved"); _execute(id);
        bytes32 registrationHash = tm.getInitialShareRegistrationActionHash(id);
        _approve(registrationHash, first, address(tm)); _approve(registrationHash, next, address(tm));
        assertEq(_ready(id), block.timestamp + 48 hours);
        vm.expectRevert("Initial registration delay not elapsed"); _execute(id);
        vm.warp(_ready(id)); _execute(id);
    }

    function testHigherConfiguredThresholdIsHonoredForExecutionAndAbort() public {
        bytes32 thresholdHash = multisig.getSetRequiredSignaturesActionHash(3, REASON);
        _propose(thresholdHash, abi.encodeCall(multisig.setRequiredSignaturesWithApproval, (3, REASON)), address(multisig));
        _approve(thresholdHash, first, address(multisig)); _approve(thresholdHash, second, address(multisig));
        vm.prank(owner); multisig.setRequiredSignaturesWithApproval(3, REASON);
        uint256 id = _request(); bytes32 hash = _approveRegistration(id); assertEq(_ready(id), 0);
        vm.expectRevert("Action not approved"); _execute(id);
        _approve(hash, third, address(tm)); assertEq(_ready(id), block.timestamp + 48 hours);
        bytes32 abortHash = _abortProposal(id, REASON);
        _approve(abortHash, first, address(tm)); _approve(abortHash, second, address(tm));
        vm.expectRevert("Action not approved"); _abort(id, REASON);
        _approve(abortHash, third, address(tm)); _abort(id, REASON);
    }

    function testFuzzWholeRegisterBalancesEqualDeclaredTotal(uint64 seed, uint8 countSeed) public {
        uint256 count = bound(uint256(countSeed), 1, 20);
        address[] memory holders = new address[](count); uint256[] memory amounts = new uint256[](count); uint256 total;
        vm.startPrank(owner);
        for (uint256 i; i < count; i++) {
            holders[i] = address(uint160(0x4000 + i)); amounts[i] = uint256(seed) + i + 1;
            total += amounts[i]; ac.approveHolder(holders[i]);
        }
        vm.stopPrank(); uint256 id = _request(holders, amounts, total, REGISTER_SHA256);
        bytes32 hash = tm.getInitialShareRegistrationActionHash(id);
        _propose(hash, _data(id, holders, amounts, total, REGISTER_SHA256), address(tm));
        _approve(hash, first, address(tm)); _approve(hash, second, address(tm)); vm.warp(_ready(id));
        vm.prank(owner); tm.registerInitialShares(id, holders, amounts, total, REGISTER_SHA256);
        assertEq(tm.totalSupplyOSTf(), total); assertEq(tm.registeredHolderCount(), count);
        for (uint256 i; i < count; i++) assertEq(tm.balanceOfOST(holders[i]), amounts[i]);
    }
}
