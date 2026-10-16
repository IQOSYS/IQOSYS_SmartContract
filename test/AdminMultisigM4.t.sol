// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/AccessControl.sol";
import "../src/AdminMultisig.sol";

contract M4TestConsumer {
    function consume(IAdminMultisig multisig, bytes32 actionHash) external {
        multisig.consumeApprovedAction(actionHash);
    }

    function consumeWithThreshold(
        IAdminMultisig multisig,
        bytes32 actionHash,
        uint256 requiredApprovals
    ) external {
        multisig.consumeApprovedActionWithRequiredSignatures(
            actionHash,
            requiredApprovals
        );
    }
}

contract AdminMultisigM4Test is Test {
    AccessControl ac;
    AdminMultisig multisig;
    M4TestConsumer consumerA;
    M4TestConsumer consumerB;

    address owner = address(0xA0);
    address signer1 = address(0xA1);
    address signer2 = address(0xA2);
    address signer3 = address(0xA3);
    address signer4 = address(0xA4);

    function setUp() public {
        vm.startPrank(owner);
        ac = new AccessControl(owner);

        // Production invariant: every multisig signer is also an AccessControl admin.
        ac.addAdmin(signer1);
        ac.addAdmin(signer2);
        ac.addAdmin(signer3);

        address[] memory signers = new address[](3);
        signers[0] = signer1;
        signers[1] = signer2;
        signers[2] = signer3;

        multisig = new AdminMultisig(address(ac), signers, 2);

        // One-time binding used by replaceSigner() to rotate admin rights atomically.
        ac.setAdminSignerController(address(multisig));

        consumerA = new M4TestConsumer();
        consumerB = new M4TestConsumer();
        multisig.setActionConsumer(address(consumerA), true);
        multisig.setActionConsumer(address(consumerB), true);
        multisig.lockActionConsumerBootstrap();
        vm.stopPrank();
    }

    function _propose(bytes32 hash, address consumer) internal {
        uint256 deadline = block.timestamp + multisig.ACTION_APPROVAL_VALIDITY();
        vm.prank(signer1);
        multisig.proposeAction(
            hash,
            consumer,
            bytes4(keccak256("TEST_ACTION(bytes32)")),
            keccak256(abi.encode(hash, consumer)),
            "Foundry test fixture - not a production proposal",
            deadline
        );
    }

    function _approveFor(bytes32 actionHash, address consumer) internal {
        _propose(actionHash, consumer);
        vm.prank(signer1);
        multisig.approveActionForConsumer(actionHash, consumer);
        vm.prank(signer2);
        multisig.approveActionForConsumer(actionHash, consumer);
    }

    function testM4WrongConsumerCannotBurnOrdinaryApproval() public {
        bytes32 hash = keccak256("m4-consumer-a-ordinary");
        _approveFor(hash, address(consumerA));

        assertTrue(multisig.isActionApproved(hash));
        assertEq(multisig.getActionConsumer(hash), address(consumerA));

        vm.expectRevert("Action belongs to different consumer");
        consumerB.consume(multisig, hash);

        (uint256 approvals, bool consumed, bool exists) =
            multisig.getApprovalState(hash);
        assertEq(approvals, 2);
        assertFalse(consumed);
        assertTrue(exists);

        consumerA.consume(multisig, hash);
        (, consumed,) = multisig.getApprovalState(hash);
        assertTrue(consumed);
    }

    function testM4WrongConsumerCannotBurnCustomThresholdApproval() public {
        bytes32 hash = keccak256("m4-consumer-a-custom-threshold");
        _approveFor(hash, address(consumerA));

        vm.expectRevert("Action belongs to different consumer");
        consumerB.consumeWithThreshold(multisig, hash, 2);

        assertTrue(multisig.isActionApproved(hash));
        consumerA.consumeWithThreshold(multisig, hash, 2);
        (, bool consumed,) = multisig.getApprovalState(hash);
        assertTrue(consumed);
    }

    function testM4SignersCannotAssignSameHashToDifferentConsumers() public {
        bytes32 hash = keccak256("m4-conflicting-consumer");
        _propose(hash, address(consumerA));

        vm.prank(signer1);
        multisig.approveActionForConsumer(hash, address(consumerA));

        vm.prank(signer2);
        vm.expectRevert("Action bound to different consumer");
        multisig.approveActionForConsumer(hash, address(consumerB));

        vm.prank(signer2);
        multisig.approveActionForConsumer(hash, address(consumerA));

        assertEq(multisig.getActionConsumer(hash), address(consumerA));
        assertTrue(multisig.isActionApproved(hash));
    }

    function testM4LegacyApprovalOnlyWorksForMultisigInternalActions() public {
        bytes32 referenceHash = keccak256("m4-self-registration");
        bytes32 hash = multisig.getSetActionConsumerActionHash(
            address(consumerA),
            false,
            referenceHash
        );

        _propose(hash, address(multisig));
        vm.prank(signer1);
        multisig.approveAction(hash);
        vm.prank(signer2);
        multisig.approveAction(hash);

        assertEq(multisig.getActionConsumer(hash), address(multisig));

        vm.expectRevert("Action belongs to different consumer");
        consumerA.consume(multisig, hash);

        vm.prank(owner);
        multisig.setActionConsumerWithApproval(
            address(consumerA),
            false,
            referenceHash
        );

        assertFalse(multisig.isActionConsumer(address(consumerA)));
        (, bool consumed,) = multisig.getApprovalState(hash);
        assertTrue(consumed);
    }

    function testM4EpochRotationInvalidatesWithoutChangingProposal() public {
        bytes32 hash = keccak256("m4-pre-rotation-approval");
        _approveFor(hash, address(consumerA));

        bytes32 referenceHash = keccak256("m4-replace-signer");
        bytes32 rotationHash = multisig.getReplaceSignerActionHash(
            signer3,
            signer4,
            referenceHash
        );

        _propose(rotationHash, address(multisig));
        vm.prank(signer1);
        multisig.approveAction(rotationHash);
        vm.prank(signer2);
        multisig.approveAction(rotationHash);

        vm.prank(owner);
        multisig.replaceSigner(signer3, signer4, referenceHash);

        assertFalse(multisig.isSigner(signer3));
        assertTrue(multisig.isSigner(signer4));
        assertFalse(ac.isAdmin(signer3));
        assertTrue(ac.isAdmin(signer4));

        assertFalse(multisig.isActionApproved(hash));
        vm.prank(signer1);
        vm.expectRevert("Action bound to different consumer");
        multisig.approveActionForConsumer(hash, address(consumerB));

        vm.prank(signer1);
        multisig.approveActionForConsumer(hash, address(consumerA));
        vm.prank(signer2);
        multisig.approveActionForConsumer(hash, address(consumerA));
        assertEq(multisig.getActionConsumer(hash), address(consumerA));

        vm.expectRevert("Action belongs to different consumer");
        consumerB.consume(multisig, hash);
        consumerA.consume(multisig, hash);
    }
    function testReviewConsumerCannotLowerThresholdToOne() public {
        bytes32 hash = keccak256("minimum-threshold-regression");
        _approveFor(hash, address(consumerA));
        vm.expectRevert("Threshold below multisig minimum");
        consumerA.consumeWithThreshold(multisig, hash, 1);
        assertTrue(multisig.isActionApproved(hash));
        consumerA.consumeWithThreshold(multisig, hash, 2);
    }
}
