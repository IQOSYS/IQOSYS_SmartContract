// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/AccessControl.sol";
import "../src/AdminMultisig.sol";

contract SignerRotationReviewTest is Test {
    AccessControl ac;
    AdminMultisig multisig;
    address owner = address(0xA0);
    address first = address(0xA1);
    address second = address(0xA2);
    address departing = address(0xA3);
    address replacement = address(0xA4);
    bytes32 constant REF = keccak256("rotation evidence");
    bytes32 constant REASON = keccak256("abort evidence");

    function setUp() public {
        vm.warp(100);
        vm.startPrank(owner);
        ac = new AccessControl(owner);
        ac.addAdmin(first);
        ac.addAdmin(second);
        ac.addAdmin(departing);
        multisig = new AdminMultisig(address(ac), _signers(), 2);
        ac.setAdminSignerController(address(multisig));
        vm.stopPrank();
    }

    function _signers() private view returns (address[] memory values) {
        values = new address[](3);
        values[0] = first;
        values[1] = second;
        values[2] = departing;
    }

    function _propose(bytes32 hash, bytes memory data) private {
        bytes4 selector;
        assembly { selector := mload(add(data, 32)) }
        uint256 deadline = vm.getBlockTimestamp() + 7 days;
        vm.prank(first);
        multisig.proposeAction(hash, address(multisig), selector, keccak256(data), "Public rotation reference", deadline);
    }

    function _approve(bytes32 hash, address signer) private {
        vm.prank(signer);
        multisig.approveAction(hash);
    }

    function _rotation(bytes32 referenceHash) private returns (bytes32 hash) {
        hash = multisig.getReplaceSignerActionHash(departing, replacement, referenceHash);
        _propose(hash, abi.encodeCall(multisig.replaceSigner, (departing, replacement, referenceHash)));
    }

    function _ready(bytes32 referenceHash) private view returns (uint256) {
        return multisig.signerRotationReadyAt(departing, replacement, referenceHash);
    }

    function _execute(bytes32 referenceHash) private {
        vm.prank(owner);
        multisig.replaceSigner(departing, replacement, referenceHash);
    }

    function _quorum() private returns (bytes32 hash, uint256 ready) {
        hash = _rotation(REF);
        _approve(hash, first);
        _approve(hash, second);
        ready = _ready(REF);
    }

    function _abortProposal(bytes32 referenceHash, bytes32 reasonHash) private returns (bytes32 hash) {
        hash = multisig.getAbortSignerRotationActionHash(departing, replacement, referenceHash, reasonHash);
        _propose(hash, abi.encodeCall(multisig.abortSignerRotation, (departing, replacement, referenceHash, reasonHash)));
    }

    function _abort(bytes32 referenceHash, bytes32 reasonHash) private {
        vm.prank(owner);
        multisig.abortSignerRotation(departing, replacement, referenceHash, reasonHash);
    }

    function testDelayStartsAtSecondRemainingSignature() public {
        bytes32 hash = _rotation(REF);
        _approve(hash, first);
        vm.warp(vm.getBlockTimestamp() + 3 days);
        assertEq(_ready(REF), 0);
        _approve(hash, second);
        uint256 ready = _ready(REF);
        assertEq(ready, vm.getBlockTimestamp() + 48 hours);
        vm.expectRevert("Signer rotation delay not elapsed"); _execute(REF);
        vm.warp(ready - 1);
        vm.expectRevert("Signer rotation delay not elapsed"); _execute(REF);
        vm.warp(ready);
        _execute(REF);
        assertFalse(multisig.isSigner(departing));
        assertTrue(multisig.isSigner(replacement));
        assertFalse(ac.isAdmin(departing));
        assertTrue(ac.isAdmin(replacement));
        assertEq(multisig.signerEpoch(), 2);
        (, bool consumed,) = multisig.getApprovalState(hash);
        assertTrue(consumed);
        assertEq(_ready(REF), 0);
    }

    function testDepartingSignatureCannotStartOrAccelerateDelay() public {
        bytes32 hash = _rotation(REF);
        _approve(hash, departing);
        _approve(hash, first);
        vm.warp(vm.getBlockTimestamp() + 48 hours);
        assertEq(_ready(REF), 0);
        vm.expectRevert("Action not approved by remaining signers"); _execute(REF);
        _approve(hash, second);
        assertEq(_ready(REF), vm.getBlockTimestamp() + 48 hours);
        vm.expectRevert("Signer rotation delay not elapsed"); _execute(REF);
    }

    function testRevokeAndReapproveRestartsDelay() public {
        (bytes32 hash, uint256 oldReady) = _quorum();
        vm.warp(oldReady - 1);
        vm.prank(second); multisig.revokeApproval(hash);
        assertEq(_ready(REF), 0);
        _approve(hash, second);
        uint256 ready = _ready(REF);
        assertEq(ready, vm.getBlockTimestamp() + 48 hours);
        vm.warp(oldReady);
        vm.expectRevert("Signer rotation delay not elapsed"); _execute(REF);
        vm.warp(ready); _execute(REF);
    }

    function testExpiredProposalRenewalRestartsDelay() public {
        (bytes32 hash,) = _quorum();
        vm.warp(vm.getBlockTimestamp() + 7 days + 1);
        assertEq(_ready(REF), 0);
        vm.expectRevert("Action not approved by remaining signers"); _execute(REF);
        assertEq(_rotation(REF), hash);
        _approve(hash, first); _approve(hash, second);
        uint256 ready = _ready(REF);
        assertEq(ready, vm.getBlockTimestamp() + 48 hours);
        vm.expectRevert("Signer rotation delay not elapsed"); _execute(REF);
        vm.warp(ready); _execute(REF);
    }

    function testAbortRequiresQuorumAndHasNoDelay() public {
        (bytes32 rotationHash,) = _quorum();
        bytes32 abortHash = _abortProposal(REF, REASON);
        _approve(abortHash, first);
        vm.expectRevert("Action not approved"); _abort(REF, REASON);
        _approve(abortHash, second);
        _abort(REF, REASON);
        assertTrue(multisig.abortedSignerRotations(rotationHash));
        assertEq(_ready(REF), 0);
        assertTrue(multisig.isSigner(departing));
        assertEq(multisig.signerEpoch(), 1);
        (, bool consumed,) = multisig.getApprovalState(abortHash);
        assertTrue(consumed);
        vm.warp(vm.getBlockTimestamp() + 48 hours);
        vm.expectRevert("Signer rotation aborted"); _execute(REF);
        vm.expectRevert("Signer rotation aborted"); _abort(REF, REASON);
    }

    function testAbortAfterDelayStillStopsExecutionAndFreshReferenceNeedsDelay() public {
        (, uint256 ready) = _quorum();
        vm.warp(ready);
        bytes32 abortHash = _abortProposal(REF, REASON);
        _approve(abortHash, first); _approve(abortHash, second); _abort(REF, REASON);
        vm.expectRevert("Signer rotation aborted"); _execute(REF);
        bytes32 next = keccak256("new rotation evidence");
        bytes32 hash = _rotation(next);
        _approve(hash, first); _approve(hash, second);
        vm.expectRevert("Signer rotation delay not elapsed"); _execute(next);
        vm.warp(_ready(next)); _execute(next);
    }

    function testAbortBindsExactAttemptAndReason() public {
        _quorum();
        bytes32 abortHash = _abortProposal(REF, REASON);
        _approve(abortHash, first); _approve(abortHash, second);
        vm.expectRevert("Action belongs to different consumer"); _abort(REF, keccak256("different reason"));
        vm.expectRevert("Action belongs to different consumer"); _abort(keccak256("different attempt"), REASON);
        _abort(REF, REASON);
    }

    function testAbortCannotCancelExecutedRotation() public {
        // Execution changes membership, so an immediate late abort is invalid.
        (, uint256 ready) = _quorum();
        bytes32 abortHash = _abortProposal(REF, REASON);
        _approve(abortHash, first); _approve(abortHash, second);
        vm.warp(ready); _execute(REF);
        vm.expectRevert("Invalid signer rotation"); _abort(REF, REASON);
    }

    function testConsumedAttemptCannotBeAbortedAfterSignerIsRestored() public {
        (, uint256 ready) = _quorum();
        vm.warp(ready); _execute(REF);
        bytes32 backRef = keccak256("restore original signer");
        bytes32 back = multisig.getReplaceSignerActionHash(replacement, departing, backRef);
        _propose(back, abi.encodeCall(multisig.replaceSigner, (replacement, departing, backRef)));
        _approve(back, first); _approve(back, second);
        vm.warp(vm.getBlockTimestamp() + 48 hours);
        vm.prank(owner); multisig.replaceSigner(replacement, departing, backRef);
        bytes32 abortHash = _abortProposal(REF, REASON);
        _approve(abortHash, first); _approve(abortHash, second);
        vm.expectRevert("Signer rotation already executed"); _abort(REF, REASON);
    }

    function testTwoSignerConfigurationCannotRecoverWithOneRemainingSigner() public {
        address[] memory values = new address[](2);
        values[0] = first; values[1] = departing;
        multisig = new AdminMultisig(address(ac), values, 2);
        bytes32 hash = _rotation(REF);
        _approve(hash, first); _approve(hash, departing);
        vm.warp(vm.getBlockTimestamp() + 48 hours);
        assertEq(_ready(REF), 0);
        vm.expectRevert("Insufficient remaining signers"); _execute(REF);
    }

    function testThreeSignatureConfigRequiresThreeToAbort() public {
        _setThreshold(3);
        _quorum();
        bytes32 abortHash = _abortProposal(REF, REASON);
        _approve(abortHash, first); _approve(abortHash, second);
        vm.expectRevert("Action not approved"); _abort(REF, REASON);
        _approve(abortHash, departing); _abort(REF, REASON);
        assertEq(_ready(REF), 0);
    }

    function testSignerEpochChangeInvalidatesOtherRotationDelay() public {
        (bytes32 pending, uint256 oldReady) = _quorum();
        address next = address(0xA5);
        bytes32 referenceHash = keccak256("rotate another signer");
        bytes32 hash = multisig.getReplaceSignerActionHash(first, next, referenceHash);
        _propose(hash, abi.encodeCall(multisig.replaceSigner, (first, next, referenceHash)));
        _approve(hash, second); _approve(hash, departing);
        vm.warp(oldReady);
        vm.prank(owner); multisig.replaceSigner(first, next, referenceHash);
        assertEq(_ready(REF), 0);
        _approve(pending, second); _approve(pending, next);
        assertEq(_ready(REF), vm.getBlockTimestamp() + 48 hours);
        vm.expectRevert("Signer rotation delay not elapsed"); _execute(REF);
        vm.warp(_ready(REF)); _execute(REF);
    }

    function testThreeSignatureConfigKeepsTwoRemainingSignerRecoveryAndDelay() public {
        _setThreshold(3);
        (, uint256 ready) = _quorum();
        assertEq(ready, vm.getBlockTimestamp() + 48 hours);
        vm.expectRevert("Signer rotation delay not elapsed"); _execute(REF);
        vm.warp(ready); _execute(REF);
        assertEq(multisig.requiredSignatures(), 3);
    }

    function _approveThreshold(uint256 threshold) private {
        bytes32 hash = multisig.getSetRequiredSignaturesActionHash(threshold, REF);
        _propose(hash, abi.encodeCall(multisig.setRequiredSignaturesWithApproval, (threshold, REF)));
        _approve(hash, first); _approve(hash, second);
        if (multisig.requiredSignatures() == 3) _approve(hash, departing);
    }

    function _setThreshold(uint256 threshold) private {
        _approveThreshold(threshold);
        vm.prank(owner); multisig.setRequiredSignaturesWithApproval(threshold, REF);
    }

    function testThresholdCannotDropToOneEvenWithQuorum() public {
        _approveThreshold(1);
        vm.prank(owner); vm.expectRevert("Invalid required signatures");
        multisig.setRequiredSignaturesWithApproval(1, REF);
        assertEq(multisig.requiredSignatures(), 2);
    }

    function testThresholdCannotDropToZero() public {
        _approveThreshold(0);
        vm.prank(owner); vm.expectRevert("Invalid required signatures");
        multisig.setRequiredSignaturesWithApproval(0, REF);
        assertEq(multisig.requiredSignatures(), 2);
    }

    function testThresholdMayReturnFromThreeToTwoWithCurrentQuorum() public {
        _setThreshold(3); _setThreshold(2);
        assertEq(multisig.requiredSignatures(), 2);
    }

    function testConstructorRejectsOneSignature() public {
        vm.expectRevert("Invalid required signatures");
        new AdminMultisig(address(ac), _signers(), 1);
    }

    function testConstructorRejectsZeroSignatures() public {
        vm.expectRevert("Invalid required signatures");
        new AdminMultisig(address(ac), _signers(), 0);
    }

    function testNonAdminCannotExecuteOrAbort() public {
        _quorum();
        vm.prank(address(0xBAD)); vm.expectRevert("Caller is not an admin");
        multisig.replaceSigner(departing, replacement, REF);
        vm.prank(address(0xBAD)); vm.expectRevert("Caller is not an admin");
        multisig.abortSignerRotation(departing, replacement, REF, REASON);
    }

    function testAdminRightsFailureRollsBackApproval() public {
        // A separate AccessControl instance has no signer controller binding.
        vm.prank(owner); multisig = new AdminMultisig(address(ac), _signers(), 2);
        (bytes32 hash, uint256 ready) = _quorum();
        vm.warp(ready);
        vm.expectRevert(); _execute(REF);
        (, bool consumed,) = multisig.getApprovalState(hash);
        assertFalse(consumed);
        assertTrue(multisig.isSigner(departing));
        assertFalse(multisig.isSigner(replacement));
    }
}
