// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/AccessControl.sol";

contract AccessControlOneTxApprovalTest is Test {
    AccessControl internal ac;
    address internal owner = address(0xA0);
    address internal otherAdmin = address(0xA1);
    address internal holder = address(0xB0);
    address internal outsider = address(0xC0);

    function setUp() public {
        vm.prank(owner);
        ac = new AccessControl(owner);
        vm.prank(owner);
        ac.addAdmin(otherAdmin);
    }

    function testAdminApprovesBothInOneCall() public {
        vm.prank(otherAdmin);
        ac.approveHolder(holder);

        assertTrue(ac.isWhiteListed(holder));
        assertTrue(ac.isAuthorized(holder));
        assertFalse(ac.isFrozen(holder));
        assertTrue(ac.onlyValidSender(holder));
        assertFalse(ac.isAdmin(holder));
    }

    function testPartiallyWhitelistedHolderIsCompleted() public {
        vm.prank(owner);
        ac.addToWhiteList(holder);
        vm.prank(otherAdmin);
        ac.approveHolder(holder);
        assertTrue(ac.isWhiteListed(holder));
        assertTrue(ac.isAuthorized(holder));
    }

    function testPartiallyAuthorizedHolderIsCompleted() public {
        vm.prank(owner);
        ac.authorizeAddress(holder);
        vm.prank(otherAdmin);
        ac.approveHolder(holder);
        assertTrue(ac.isWhiteListed(holder));
        assertTrue(ac.isAuthorized(holder));
    }

    function testOutsiderCannotApproveHolder() public {
        vm.prank(outsider);
        vm.expectRevert("Caller is not an admin");
        ac.approveHolder(holder);
        assertFalse(ac.isWhiteListed(holder));
        assertFalse(ac.isAuthorized(holder));
    }

    function testFrozenHolderCannotBeApprovedOrUnfrozenByBatch() public {
        vm.prank(owner);
        ac.freezeAddress(holder);
        vm.prank(otherAdmin);
        vm.expectRevert("Account is frozen");
        ac.approveHolder(holder);
        assertTrue(ac.isFrozen(holder));
        assertFalse(ac.isWhiteListed(holder));
        assertFalse(ac.isAuthorized(holder));
    }

    function testAlreadyApprovedIsNotRepeated() public {
        vm.prank(owner);
        ac.approveHolder(holder);
        vm.prank(otherAdmin);
        vm.expectRevert("Account already approved");
        ac.approveHolder(holder);
    }

    function testZeroAddressRejected() public {
        vm.prank(owner);
        vm.expectRevert("Invalid account");
        ac.approveHolder(address(0));
    }

    function testAccountManagerRoleDoesNotGrantBatchApproval() public {
        // Resolve the external getter before the one-shot prank: otherwise
        // ROLE_ACCOUNT_MANAGER() consumes the prank instead of setRole().
        bytes32 role = ac.ROLE_ACCOUNT_MANAGER();
        vm.prank(owner);
        ac.setRole(role, outsider, true);
        vm.prank(outsider);
        vm.expectRevert("Caller is not an admin");
        ac.approveHolder(holder);
    }
}
