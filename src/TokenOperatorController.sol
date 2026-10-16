// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./ITokenOperatorController.sol";
import "./IAccessControl.sol";
import "./IAdminMultisig.sol";

interface IControlledTokenManager {
    function setTokenOperator(
        address operator,
        bool status
    ) external;
}

/// @title Token Operator Controller
/// @notice Multisig-controlled controller for adding/removing token operator modules.
/// @dev Prevents a single admin from granting themselves token operator rights.
contract TokenOperatorController is ITokenOperatorController {
    IAccessControl public accessControl;
    IAdminMultisig public adminMultisig;
    IControlledTokenManager public tokenManager;

    uint256 private nextChangeId;

    mapping(uint256 => TokenOperatorChange) private changes;

    event TokenOperatorChangeExecuted(
        uint256 indexed changeId,
        address indexed operator,
        bool status,
        bytes32 indexed referenceHash,
        address executedBy,
        uint256 timestamp
    );

    constructor(
        address _accessControl,
        address _adminMultisig,
        address _tokenManager
    ) {
        require(_accessControl != address(0), "Invalid access control");
        require(_adminMultisig != address(0), "Invalid admin multisig");
        require(_tokenManager != address(0), "Invalid token manager");

        accessControl = IAccessControl(_accessControl);
        adminMultisig = IAdminMultisig(_adminMultisig);
        tokenManager = IControlledTokenManager(_tokenManager);
    }

    modifier onlyAdmin() {
        require(
            accessControl.isAdmin(msg.sender),
            "Caller is not an admin"
        );
        _;
    }

    function getSetTokenOperatorActionHash(
        address operator,
        bool status,
        bytes32 referenceHash
    )
        public
        view
        override
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                address(this),
                block.chainid,
                "SET_TOKEN_OPERATOR",
                operator,
                status,
                referenceHash
            )
        );
    }

    function setTokenOperator(
        address operator,
        bool status,
        bytes32 referenceHash
    )
        external
        override
        onlyAdmin
        returns (uint256)
    {
        require(operator != address(0), "Invalid operator");
        require(referenceHash != bytes32(0), "Reference hash required");

        bytes32 actionHash =
            getSetTokenOperatorActionHash(
                operator,
                status,
                referenceHash
            );

        adminMultisig.consumeApprovedAction(
            actionHash
        );

        tokenManager.setTokenOperator(
            operator,
            status
        );

        uint256 changeId =
            nextChangeId++;

        changes[changeId] =
            TokenOperatorChange({
                id: changeId,
                operator: operator,
                status: status,
                referenceHash: referenceHash,
                executedBy: msg.sender,
                executedAt: block.timestamp
            });

        emit TokenOperatorChangeExecuted(
            changeId,
            operator,
            status,
            referenceHash,
            msg.sender,
            block.timestamp
        );

        return changeId;
    }

    function changesf(
        uint256 changeId
    )
        external
        view
        override
        returns (TokenOperatorChange memory)
    {
        return changes[changeId];
    }

    function changeCount()
        external
        view
        override
        returns (uint256)
    {
        return nextChangeId;
    }
}