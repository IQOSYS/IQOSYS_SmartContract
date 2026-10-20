# BSA, IQS and OST register

Last updated: 2026-10-20 (source `feat/amf-ready`, commit `dd07de0`)

## Summary
The contracts keep BSA terms, allocate and exercise IQS rights, issue OST and settle controlled OST transfers. Administrative approvals bind exact operations to their consumer, calldata and chain. Evidence registries anchor valuations, governance outcomes and document hashes without storing the private documents.

This document follows the source at `dd07de0`. Business policy is defined in `AI/project.md`; off-chain requirements are not presented as contract guarantees.

## Who can use it
| Actor | What they can do |
|---|---|
| Reader | Read public contract state and events; no application login is required to read the chain. |
| Eligible holder / participant | Request exercise and use transfer-participant actions subject to whitelist, authorization, freeze, balance and operation-state checks. |
| AccessControl admin | Use permitted registrar, account-management and emergency-entry operations; protected calls also require their exact multisig approval. |
| Multisig signer | Propose, approve or revoke an action; membership and signer epoch are checked on-chain. |
| Scoped module | Use only its bound account-manager, anchor, emergency, operator or migration-controller capability. |
| Owner Safe | Exercise AccessControl owner authority, including role administration. Ownership acceptance is separate from application admin access. |

## How it works
### BSA registration and IQS awards
1. `BSARegistry.recordBSA` validates the holder, hashes, positive strike/allocation and future expiry, then consumes the exact approved registration action.
2. A holder cannot have another active BSA. The registry creates the record and adds its unawarded allocation to BSA escrow accounting; it does not mint `maxIQS`.
3. `creditIQS` consumes its own approved action, checks remaining entitlement and credits whole IQS to the holder. Off-chain margin evidence is not independently inspected by Solidity.
4. Cancellation consumes a cancellation approval, rejects pending exercises, removes unawarded allocation and burns the BSA's unexercised awarded IQS atomically.
5. Expiry views exclude elapsed allocation immediately. `syncBSAStatus` updates stored status and burns eligible expired, unreserved IQS; a view call itself never burns a balance.

### Exercise and OST issuance
1. A holder requests exercise against an eligible BSA and available IQS. Pending exercise reservations prevent the same entitlement being reused.
2. An admin approves the request and confirms the capital-payment hash after off-chain payment checks.
3. Approved `finalizeExercise` binds the request and receipt hash, burns exercised IQS, records BSA conversion accounting and mints the same quantity of OST in one transaction.
4. Cancellation/rejection release reservations as allowed by the current state. Rejection after capital confirmation consumes its separate approval; it does not execute a fiat refund.

### OST transfer and atomic settlement
1. A request records seller, buyer, whole OST quantity, agreed EUR-cent price and reference hashes. The implementation retains buy/sell/counter methods; they are not permission to build an order book or matching service.
2. Participant acceptance or the approved admin path locks already-issued OST in the dedicated escrow. Counters record open transfers and each involved wallet.
3. Buyer payment proof and seller-payment evidence have separate meanings. `adminRegisterBuyerPaymentProof` is a single-admin recording path, not a two-signature settlement.
4. `adminConfirmSellerPaymentAndRelease` consumes one approval binding the transfer and both receipt hashes. It emits payment confirmation and releases OST to the buyer in the same transaction. Release failure rolls back both confirmation and approval consumption.
5. The older seller-validation plus release-only methods remain state-gated and independently approval-gated. Their existence must not be described as the required default combined flow.
6. Dispute resolution has an exact approved intent covering the destination decision and evidence. Token return never implies that a bank payment was refunded.

### Timeout reclaim and receipts
- An untouched `Escrowed` lock is reclaimable after `ESCROW_TIMEOUT`, seven days, by any caller. OST always returns to the recorded seller.
- After payment proof, only the seller can reclaim after `paymentValidationDeadline`; `PAYMENT_VALIDATION_TIMEOUT` is seven days. Disputed or already seller-validated transfers do not use that timeout path.
- Reclaim does not depend on the transfer module's pause check. Other downstream token/permission checks can still prevent a transfer; a pause must not be described as universally preventing or permitting recovery.
- Terminal exercise and transfer receipt hashes are first-write only. A second setter call reverts even for the same hash.
- A returned transfer can receive its first receipt hash through `adminRecordTransferReceiptHash`, using one admin. That value then cannot be corrected. This is the accepted post-release review item, not an implemented multi-admin amendment flow.

### Proposals and proposal replacement
1. `proposeAction` binds consumer, selector, calldata hash, description and deadline. Proposing does not approve.
2. Eligible signers approve the current proposal. Ordinary validity is bounded by `ACTION_APPROVAL_VALIDITY`, seven days; signer rotation invalidates prior-epoch approvals.
3. Only the intended registered consumer can consume the approved action. Consumption is single-use.
4. Replacement votes bind the expected proposal fingerprint, version, signer epoch and replacement fields. One replacement vote does not change the proposal. Quorum replacement clears execution approvals, so the corrected proposal needs fresh signatures.
5. A consumed action cannot be revived by replacement or by rewriting its off-chain record.

### Holder migration and Abort
1. The exact intent includes old wallet, new wallet and a nonzero evidence-reference hash. Required approval count is at least two and respects a higher configured threshold.
2. `getActionQuorumReachedAt` determines the effective quorum time. `migrateHolder` waits 48 hours from that time, not from creation of an application record.
3. Migration moves BSA ownership and IQS/OST balances atomically through the bound controller. Both wallets must meet the migration constraints, including no open OST transfers; owner/admin/operator/escrow wallets are excluded.
4. The holder slot moves to the new wallet and the old wallet is retired. Historical BSA, exercise and receipt evidence must remain interpretable after the move.
5. A separate approved `abortHolderMigration` permanently cancels that attempt before execution. It has no extra 48-hour delay and does not move tokens. A new attempt needs a fresh reference, signatures and delay.

### Valuation, governance and evidence
- `ValuationAnchor` publishes immutable hash records. Corrections are new records linked to an existing anchor in the same period.
- `GovernanceRegistry.recordOutcomeWithBallotRoot` commits the weighted result, population, power source and signed-ballot root. It does not validate all ballot signatures or recompute the off-chain tally. Legacy APIs without a ballot root revert.
- Official valuation/governance records use `HashRegistry` module-scoped anchors. Generic document anchoring and linked supersession do not replace that official proof.
- Emergency scopes can be paused by an authorized admin or emergency module. Resuming requires the approved emergency-controller action, including for governance.

## Business rules
| Rule | Current implementation / boundary |
|---|---|
| Eligibility | Off-chain policy restricts BSA/IQS to Exec Partners' companies. Contract validity checks establish wallet permissions, not company identity. |
| IQS transferability | Ordinary inter-wallet IQS transfer is disabled. Authorized wallet recovery is a separate controlled operation. |
| Supply | IQS has no fixed economic issuance cap in this revision (`uint256` numeric limit). OST starts at zero; there is no automatic treasury allocation. |
| Units | Whole IQS/OST. Strike and sale price are EUR cents per OST; premium/capital are total EUR cents. |
| Holder restriction | `MAX_REGISTERED_HOLDERS` is 149 shared permanent wallet slots. Zero balance does not free a slot; authorized migration moves it. The custody address is excluded from beneficial-holder listings. |
| BSA-signature count | `recordBSA` does not reserve a TokenManager holder slot. The platform must separately apply the approved below-150 rule at BSA signature/offer time. |
| Valuation supply | `totalSupplyOSTf() + totalSupplyIQS() + totalIQSInEscrow()`. Transfer-escrow OST is already in issued supply. Unawarded expired allocation is excluded by the BSA view. |
| Business valuation | Quarterly admin valuation and BSA premium methodology are off-chain; the contracts anchor supplied hashes. |
| Key/operator changes | Quorum/control checks are operation-specific. Only holder migration has the explicit 48-hour timer in these controller functions; no universal rotation timer is assumed. |

## API endpoints
None. This repository exposes Solidity interfaces, not HTTP endpoints. The following are contract entry points; the bridge and Laravel routes belong to the platform repository.

| Module | Main entry points | Authority / purpose |
|---|---|---|
| [IQOS](../../src/IQOS.sol) | Public module references | Aggregator; does not forward business calls |
| [TokenManager](../../src/TokenManager.sol) | `balanceOfIQS`, `balanceOfOST`, `totalSupplyOSTf` | Custom ledger; privileged writes are restricted to their controllers/operators |
| [AccessControl](../../src/AccessControl.sol) | `approveHolder`, `setRole`, `replaceSignerAdmin` | Account and scoped-role controls; signer-admin replacement is controller-bound |
| [AdminMultisig](../../src/AdminMultisig.sol) | `proposeAction`, `approveActionForConsumer`, `revokeApproval`, `approveProposalReplacement` | Intent-bound approvals and replacement votes |
| [BSARegistry](../../src/BSARegistry.sol) | `recordBSA`, `creditIQS`, `cancelBSA`, `syncBSAStatus` | BSA and rights lifecycle; sync is not an admin-only method |
| [ConversionModule](../../src/ConversionModule.sol) | `requestExercise`, `confirmCapitalReceived`, `finalizeExercise` | Exercise reservation, capital evidence and OST issue |
| [OSTTransferModule](../../src/OSTTransferModule.sol) | `adminCreateAgreedSellTransferAndLockEscrow`, `adminConfirmSellerPaymentAndRelease`, `reclaimExpiredEscrow` | Controlled sale, atomic settlement and timeout return |
| [HolderMigrationController](../../src/HolderMigrationController.sol) | `migrateHolder`, `migrationReadyAt`, `abortHolderMigration` | Delayed recovery and quorum Abort |
| [TokenOperatorController](../../src/TokenOperatorController.sol) | `setTokenOperator` | Approved operator change |
| [ValuationAnchor](../../src/ValuationAnchor.sol) | `publishQuarterlyValuation`, `publishCorrectionValuation` | Official valuation evidence |
| [GovernanceRegistry](../../src/GovernanceRegistry.sol) | `recordOutcomeWithBallotRoot` | Official result and ballot-root commitment |
| [HashRegistry](../../src/HashRegistry.sol) | `anchorHash`, `getModuleHashRecord`, `supersedeHash` | Document and module evidence; exact signatures are in the interfaces |
| [EmergencyController](../../src/EmergencyController.sol) | `pauseAll`, `unpauseAll` and scoped variants | Pause and approved resume |

Read the matching `src/I*.sol` interface and implementation for full signatures and state prerequisites. Function names alone do not establish authorization.

## Data
- `BSARecord`: holder, term/reference hashes, strike, allocation, award/conversion counters, premium, expiry, status and timestamps.
- `IQSExerciseRequest`: BSA, holder, amount, strike, capital due, evidence hashes, reservations and lifecycle timestamps.
- `OSTTransfer`: parties, quantity, price, state, escrow deadline and reference/agreement/payment/receipt/resolution hashes.
- Multisig storage: signer set/epoch, proposal binding/version, approvals, quorum timing, replacement votes and consumption.
- Other records: valuation/correction anchors, governance result/ballot roots, document lineage, migrations and operator changes.
- Names, identity documents, contract/PDF bytes and bank details are not required on-chain. The application keeps private evidence and retention rules off-chain. Linked wallets and hashes are not automatically anonymous or erasable.

Exercise statuses are `None`, `Requested`, `Approved`, `Rejected`, `CapitalReceived`, `Settled`, `Cancelled`. OST transfer statuses are defined in `src/IOSTTransferModule.sol`; applications must use the current enum mapping rather than a legacy trading enum.

## Frontend
None in this repository. Platform admin and holder screens use Laravel and the bridge. Abort guidance must say quorum is required; UI choices cannot override on-chain state, permissions or delay.

## Background jobs and notifications
None. Contracts execute only on transactions or reads; time passing does not send a notification or automatically execute a migration. The platform owns identity re-proofing, the required key-change email/SMS alerts, expiry synchronization, shareholder projections and reconciliation jobs.

## External services
No outbound HTTP, KMS, bank, mail, SMS or 2FA service is called by Solidity. Deployment and integration use an EVM JSON-RPC provider. On-chain governance roots and evidence hashes commit to externally prepared data without validating its entire real-world meaning.

## Configuration
- `foundry.toml`: compiler 0.8.20, Shanghai, optimizer enabled with 200 runs, via IR; RPC aliases `amoy` and `polygon`.
- Deployment variable names: `PRIVATE_KEY`, `OWNER_SAFE`, `ADMIN_SIGNER_1`, `ADMIN_SIGNER_2`, `ADMIN_SIGNER_3`, `POLYGON_AMOY_RPC_URL`, `POLYGON_MAINNET_RPC_URL`, `POLYGONSCAN_API_KEY`. Never put values here.
- `script/Deploy.s.sol` configures admins, roles, module bindings, operators, consumers and bootstrap locks, then initiates owner transfer. The intended Safe must separately accept ownership.
- The deployed module set and source-derived ABIs must match the selected chain. A successful simulation does not prove all broadcast configuration transactions succeeded.

## Security and GDPR
- Follow exact authorization and consumer checks, reentrancy guards and state transitions. A valid signature or current admin role alone does not authorize every operation.
- Preserve approval domain separation and write-once receipt evidence. Document supersession is distinct from editing terminal financial evidence.
- The register has no general proxy upgrade path. Several bindings are one-time setters. Escrow rotation does not move custody: it requires drained old escrow, no open transfers, a paused old module and a valid empty new module.
- Neither application 2FA nor verified identity is enforced by the EVM itself. Do not publish private evidence, secret material or identifying text in calldata/events.

## Tests
- `test/AccessControlOneTxApproval.t.sol`: account approval and authority checks.
- `test/AdminMultisigM4.t.sol`, `test/AdminMultisigM7.t.sol`: consumer binding, signer lifecycle and multisig regressions.
- `test/IQOSTokenTest.t.sol`: token, BSA, exercise and transfer behavior.
- `test/Reaudit20261016.t.sol`: cross-module regression cases.
- `test/AtomicOSTSettlement.t.sol`: combined settlement, exact approval inputs and rollback behavior.
- The reported review of `dd07de0` approved the contract with 278 tests including independent checks. Foundry was not rerun for this documentation-only package. Future results must identify their tested revision.

## Known limitations and open issues
- Off-chain identity/company eligibility, holder counting at BSA signature, margin collection, bank confirmation, valuation methodology, ballot verification and 2FA remain application responsibilities.
- The approved policy's general key/operator delay and notification requirements are not all encoded as timers in this source. Confirm the end-to-end policy without describing a nonexistent on-chain timer.
- One-admin first-write receipt recording after reclaim is the accepted non-blocking post-release follow-up. Abort quorum guidance is an admin-UI follow-up.
- Audit approval applies to `dd07de0`. Later commits, deployment receipts, accepted ownership and bridge/ABI compatibility require their own review or verification. No issue numbers or deployed readiness are inferred here.
