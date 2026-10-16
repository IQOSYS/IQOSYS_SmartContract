// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/AccessControl.sol";
import "../src/AdminMultisig.sol";

contract M7Consumer {
    function execute(IAdminMultisig multisig, bytes32 actionHash) external {
        multisig.consumeApprovedAction(actionHash);
    }
}

contract AdminMultisigM7Test is Test {
    AccessControl ac;
    AdminMultisig multisig;
    M7Consumer consumer;
    M7Consumer otherConsumer;

    address owner = address(0xA0);
    address signer1 = address(0xA1);
    address signer2 = address(0xA2);
    address signer3 = address(0xA3);
    address outsider = address(0xA4);

    bytes32 constant ACTION = keccak256("m7-action");
    bytes32 constant OTHER_ACTION = keccak256("m7-other-action");

    function setUp() public {
        vm.startPrank(owner);
        ac = new AccessControl(owner);
        ac.addAdmin(signer1);
        ac.addAdmin(signer2);
        ac.addAdmin(signer3);
        address[] memory signers = new address[](3);
        signers[0] = signer1;
        signers[1] = signer2;
        signers[2] = signer3;
        multisig = new AdminMultisig(address(ac), signers, 2);
        consumer = new M7Consumer();
        otherConsumer = new M7Consumer();
        multisig.setActionConsumer(address(consumer), true);
        multisig.setActionConsumer(address(otherConsumer), true);
        multisig.lockActionConsumerBootstrap();
        vm.stopPrank();
    }

    function _calldataHash(bytes32 hash) internal view returns (bytes32) {
        return keccak256(abi.encodeWithSelector(
            M7Consumer.execute.selector,
            IAdminMultisig(address(multisig)),
            hash
        ));
    }

    function _propose(bytes32 hash, address target, uint256 deadline) internal {
        vm.prank(signer1);
        multisig.proposeAction(
            hash,
            target,
            M7Consumer.execute.selector,
            _calldataHash(hash),
            "Execute approved operation for M7 regression test",
            deadline
        );
    }

    function testM7CannotApproveUnproposedModuleAction() public {
        vm.prank(signer1);
        vm.expectRevert("Action not proposed");
        multisig.approveActionForConsumer(ACTION, address(consumer));
    }

    function testM7LegacyInternalApprovalAlsoRequiresProposal() public {
        vm.prank(signer1);
        vm.expectRevert("Action not proposed");
        multisig.approveAction(ACTION);
    }

    function testM7ProposalExposesExactPublicIntentAndCanBeConsumed() public {
        uint256 deadline = block.timestamp + 2 days;
        _propose(ACTION, address(consumer), deadline);

        (
            bool exists,
            address proposer,
            address target,
            bytes4 selector,
            bytes32 callHash,
            string memory description,
            uint256 proposedAt,
            uint256 storedDeadline
        ) = multisig.getActionProposal(ACTION);

        assertTrue(exists);
        assertEq(proposer, signer1);
        assertEq(target, address(consumer));
        assertEq(bytes32(selector), bytes32(M7Consumer.execute.selector));
        assertEq(callHash, _calldataHash(ACTION));
        assertEq(description, "Execute approved operation for M7 regression test");
        assertEq(proposedAt, block.timestamp);
        assertEq(storedDeadline, deadline);

        vm.prank(signer1);
        multisig.approveActionForConsumer(ACTION, address(consumer));
        vm.prank(signer2);
        multisig.approveActionForConsumer(ACTION, address(consumer));

        assertTrue(multisig.isActionApproved(ACTION));
        consumer.execute(multisig, ACTION);
        (, bool consumed,) = multisig.getApprovalState(ACTION);
        assertTrue(consumed);
    }

    function testM7ProposalCannotBeReplacedAfterCreation() public {
        uint256 deadline = block.timestamp + 2 days;
        _propose(ACTION, address(consumer), deadline);
        vm.prank(signer1);
        vm.expectRevert("Action already proposed");
        multisig.proposeAction(
            ACTION,
            address(otherConsumer),
            M7Consumer.execute.selector,
            keccak256("different-calldata"),
            "Change the purpose after publication",
            deadline
        );
    }

    function testM7ConsumerCannotBeSwappedAtApproval() public {
        _propose(ACTION, address(consumer), block.timestamp + 1 days);
        vm.prank(signer1);
        vm.expectRevert("Action bound to different consumer");
        multisig.approveActionForConsumer(ACTION, address(otherConsumer));
    }

    function testM7ProposalCannotOutliveMaximumValidity() public {
        // Precompute external getter before prank / expectRevert: the revert
        // must be asserted on proposeAction(), not ACTION_APPROVAL_VALIDITY().
        uint256 tooLate = block.timestamp + multisig.ACTION_APPROVAL_VALIDITY() + 1;
        vm.prank(signer1);
        vm.expectRevert("Invalid proposal deadline");
        multisig.proposeAction(
            ACTION, address(consumer), M7Consumer.execute.selector,
            _calldataHash(ACTION), "Long-lived operation",
            tooLate
        );
    }

    function testM7ProposalCannotBeApprovedAfterItsDeadline() public {
        uint256 deadline = block.timestamp + 1 days;
        _propose(ACTION, address(consumer), deadline);
        vm.warp(deadline + 1);
        vm.prank(signer1);
        vm.expectRevert("Action approval expired");
        multisig.approveActionForConsumer(ACTION, address(consumer));
    }

    function testM7ApprovalExpiresAtProposalDeadlineNotFirstSignaturePlusSevenDays() public {
        uint256 deadline = block.timestamp + 1 days;
        _propose(ACTION, address(consumer), deadline);
        vm.warp(deadline - 5);
        vm.prank(signer1);
        multisig.approveActionForConsumer(ACTION, address(consumer));
        vm.prank(signer2);
        multisig.approveActionForConsumer(ACTION, address(consumer));
        assertTrue(multisig.isActionApproved(ACTION));
        vm.warp(deadline + 1);
        assertFalse(multisig.isActionApproved(ACTION));
        vm.expectRevert("Action not approved");
        consumer.execute(multisig, ACTION);
    }

    function testM7UnauthorisedProposerCannotCreateIntent() public {
        vm.prank(outsider);
        vm.expectRevert("Caller cannot propose");
        multisig.proposeAction(
            ACTION, address(consumer), M7Consumer.execute.selector,
            _calldataHash(ACTION), "Untrusted proposal",
            block.timestamp + 1 days
        );
    }

    function testM7OnlyRegisteredConsumerCanBeProposed() public {
        vm.prank(signer1);
        vm.expectRevert("Consumer not registered");
        multisig.proposeAction(
            ACTION, outsider, M7Consumer.execute.selector,
            _calldataHash(ACTION), "Unknown consumer",
            block.timestamp + 1 days
        );
    }

    function testM7ProposedHashMustBeNonzeroAndCalldataHashMustBePresent() public {
        vm.startPrank(signer1);
        vm.expectRevert("Invalid action hash");
        multisig.proposeAction(
            bytes32(0), address(consumer), M7Consumer.execute.selector,
            _calldataHash(ACTION), "Zero hash", block.timestamp + 1 days
        );
        vm.expectRevert("Calldata hash required");
        multisig.proposeAction(
            ACTION, address(consumer), M7Consumer.execute.selector,
            bytes32(0), "No calldata proof", block.timestamp + 1 days
        );
        vm.stopPrank();
    }

    function testM7SignersCannotApproveDifferentUnproposedHash() public {
        _propose(ACTION, address(consumer), block.timestamp + 1 days);
        vm.prank(signer1);
        vm.expectRevert("Action not proposed");
        multisig.approveActionForConsumer(OTHER_ACTION, address(consumer));
    }
    function testF05NonSignerAdminCannotPropose() public {
        vm.prank(owner);
        vm.expectRevert("Caller cannot propose");
        multisig.proposeAction(ACTION, address(consumer), M7Consumer.execute.selector,
            _calldataHash(ACTION), "Admin without signer status", block.timestamp + 1 days);
    }

    function testF05ExpiredSquattedProposalCanChangeConsumerWithFreshApprovals() public {
        uint256 deadline = block.timestamp + 1 days;
        _propose(ACTION, address(otherConsumer), deadline);
        vm.prank(signer1);
        multisig.approveActionForConsumer(ACTION, address(otherConsumer));
        vm.prank(signer2);
        multisig.approveActionForConsumer(ACTION, address(otherConsumer));
        vm.warp(deadline + 1);
        _propose(ACTION, address(consumer), block.timestamp + 2 days);
        assertFalse(multisig.isActionApproved(ACTION));
        assertFalse(multisig.hasApprovedAction(ACTION, signer1));
        vm.prank(signer1);
        multisig.approveActionForConsumer(ACTION, address(consumer));
        assertFalse(multisig.isActionApproved(ACTION));
        vm.prank(signer2);
        multisig.approveActionForConsumer(ACTION, address(consumer));
        assertTrue(multisig.isActionApproved(ACTION));
        vm.expectRevert("Action belongs to different consumer");
        otherConsumer.execute(multisig, ACTION);
        consumer.execute(multisig, ACTION);
        (, bool consumed,) = multisig.getApprovalState(ACTION);
        assertTrue(consumed);
    }

    function testF05ConsumedHashCannotBeRenewedEvenAfterExpiry() public {
        uint256 deadline = block.timestamp + 1 days;
        _propose(ACTION, address(consumer), deadline);
        vm.prank(signer1);
        multisig.approveActionForConsumer(ACTION, address(consumer));
        vm.prank(signer2);
        multisig.approveActionForConsumer(ACTION, address(consumer));
        consumer.execute(multisig, ACTION);
        vm.warp(deadline + 1);
        vm.prank(signer1);
        vm.expectRevert("Action already consumed");
        multisig.proposeAction(ACTION, address(consumer), M7Consumer.execute.selector,
            _calldataHash(ACTION), "Attempt replay", deadline + 2 days);
    }

    function testF05ProposalCannotChangeAtExactDeadline() public {
        uint256 deadline = block.timestamp + 1 days;
        _propose(ACTION, address(consumer), deadline);
        vm.warp(deadline);
        vm.prank(signer1);
        vm.expectRevert("Action already proposed");
        multisig.proposeAction(ACTION, address(otherConsumer), M7Consumer.execute.selector,
            _calldataHash(ACTION), "Boundary overwrite", deadline + 2 days);
    }

    function testReviewConstructorRejectsSignerWithoutAdminRole() public {
        address[] memory signers = new address[](2);
        signers[0] = signer1;
        signers[1] = outsider;
        vm.expectRevert("Signer is not admin");
        new AdminMultisig(address(ac), signers, 2);
    }

}
