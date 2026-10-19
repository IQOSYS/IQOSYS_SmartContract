// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "./Reaudit20261016.t.sol";

contract AtomicOSTSettlementTest is Reaudit20261016Test {
    function _atomicReady() internal returns (uint256 id, bytes32 hash) {
        id = _reviewEscrow();
        _reviewPaymentProof(id);
        hash = ostTransferModule.getAdminConfirmSellerPaymentAndReleaseActionHash(id, SELLER_RECEIPT_HASH, RECEIPT_HASH);
    }
    function _atomicExecute(uint256 id) internal {
        vm.prank(owner);
        ostTransferModule.adminConfirmSellerPaymentAndRelease(id, SELLER_RECEIPT_HASH, RECEIPT_HASH);
    }
    function testAtomicOneSignerCannotConfirmOrRelease() public {
        (uint256 id, bytes32 hash) = _atomicReady();
        _proposeTestAction(hash, address(ostTransferModule));
        vm.prank(owner); adminMultisig.approveActionForConsumer(hash, address(ostTransferModule));
        vm.expectRevert("Action not approved"); _atomicExecute(id);
        assertEq(uint256(ostTransferModule.transfersf(id).status), 4);
        assertEq(tokenManager.balanceOfOST(bob), 0);
        _consumeState(hash, false);
    }
    function testAtomicTwoSignersConfirmAndReleaseWithOneConsumption() public {
        (uint256 id, bytes32 hash) = _atomicReady();
        _approveActionForConsumerByTwoSigners(hash, address(ostTransferModule));
        vm.recordLogs(); _atomicExecute(id);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 consumed; uint256 confirmations; uint256 releases;
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].emitter == address(adminMultisig) && logs[i].topics[0] == keccak256("ActionConsumed(bytes32,address,uint256)")) consumed++;
            if (logs[i].emitter == address(ostTransferModule) && logs[i].topics[0] == keccak256("SellerPaymentReceiptValidated(uint256,address,bytes32,uint256)")) confirmations++;
            if (logs[i].emitter == address(ostTransferModule) && logs[i].topics[0] == keccak256("OSTTransferReleased(uint256,address,address,uint256,bytes32,uint256)")) releases++;
        }
        assertEq(consumed, 1); assertEq(confirmations, 1); assertEq(releases, 1);
        IOSTTransferModule.OSTTransfer memory transfer = ostTransferModule.transfersf(id);
        assertEq(uint256(transfer.status), 7);
        assertEq(transfer.sellerReceiptHash, SELLER_RECEIPT_HASH);
        assertEq(transfer.receiptHash, RECEIPT_HASH);
        assertEq(tokenManager.balanceOfOST(bob), 30);
        assertEq(ostTransferModule.openTransferCount(), 0);
        _consumeState(hash, true);
    }
    function testAtomicChangingEitherReceiptCannotUseApproval() public {
        (uint256 id, bytes32 hash) = _atomicReady();
        _approveActionForConsumerByTwoSigners(hash, address(ostTransferModule));
        vm.prank(owner); vm.expectRevert();
        ostTransferModule.adminConfirmSellerPaymentAndRelease(id, keccak256("other seller receipt"), RECEIPT_HASH);
        vm.prank(owner); vm.expectRevert();
        ostTransferModule.adminConfirmSellerPaymentAndRelease(id, SELLER_RECEIPT_HASH, keccak256("other settlement receipt"));
        _consumeState(hash, false);
        _atomicExecute(id);
    }
    function testAtomicFailedReleaseRollsBackConfirmationAndConsumption() public {
        (uint256 id, bytes32 hash) = _atomicReady();
        _approveActionForConsumerByTwoSigners(hash, address(ostTransferModule));
        vm.prank(owner); accessControl.freezeAddress(bob);
        vm.expectRevert(); _atomicExecute(id);
        IOSTTransferModule.OSTTransfer memory transfer = ostTransferModule.transfersf(id);
        assertEq(uint256(transfer.status), 4);
        assertEq(transfer.sellerReceiptHash, bytes32(0)); assertEq(transfer.receiptHash, bytes32(0));
        assertEq(tokenManager.balanceOfOST(bob), 0); assertEq(ostTransferModule.openTransferCount(), 1);
        _consumeState(hash, false);
        vm.prank(owner); accessControl.unfreezeAddress(bob);
        _atomicExecute(id);
    }
    function testAtomicRequiresPaymentProofAndNonzeroHashes() public {
        uint256 id = _reviewEscrow();
        vm.expectRevert("Payment proof not registered"); _atomicExecute(id);
        _reviewPaymentProof(id);
        vm.prank(owner); vm.expectRevert("Seller receipt hash required");
        ostTransferModule.adminConfirmSellerPaymentAndRelease(id, bytes32(0), RECEIPT_HASH);
        vm.prank(owner); vm.expectRevert("Receipt hash required");
        ostTransferModule.adminConfirmSellerPaymentAndRelease(id, SELLER_RECEIPT_HASH, bytes32(0));
    }
    function testAtomicSeparateValidationApprovalCannotAuthorizeRelease() public {
        (uint256 id,) = _atomicReady();
        bytes32 oldHash = ostTransferModule.getAdminValidateSellerPaymentActionHash(id, SELLER_RECEIPT_HASH);
        _approveActionForConsumerByTwoSigners(oldHash, address(ostTransferModule));
        vm.expectRevert(); _atomicExecute(id);
        _consumeState(oldHash, false);
        assertEq(uint256(ostTransferModule.transfersf(id).status), 4);
    }
    function testAtomicCannotReplayOrBypassAdminAndPause() public {
        (uint256 id, bytes32 hash) = _atomicReady();
        _approveActionForConsumerByTwoSigners(hash, address(ostTransferModule));
        vm.prank(bob); vm.expectRevert();
        ostTransferModule.adminConfirmSellerPaymentAndRelease(id, SELLER_RECEIPT_HASH, RECEIPT_HASH);
        vm.prank(owner); ostTransferModule.pause();
        vm.expectRevert(); _atomicExecute(id);
        _consumeState(hash, false);
    }
    function testAtomicSettledReceiptCannotBeOverwrittenOrReplayed() public {
        (uint256 id, bytes32 hash) = _atomicReady();
        _approveActionForConsumerByTwoSigners(hash, address(ostTransferModule));
        _atomicExecute(id);
        vm.expectRevert("Payment proof not registered"); _atomicExecute(id);
        vm.prank(owner); vm.expectRevert("Receipt hash already recorded");
        ostTransferModule.adminRecordTransferReceiptHash(id, keccak256("replacement"));
        assertEq(tokenManager.balanceOfOST(bob), 30);
    }
}
