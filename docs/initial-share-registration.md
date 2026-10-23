# Initial share registration

The initial import records **all existing ordinary shares and all current holders** in the OST ledger. It is available only before OST supply becomes nonzero and can complete once. Later OST issuance continues through the existing exercise flow.

`TokenManager` uses the existing `AdminMultisig` through the one-time `AccessControl.adminSignerController` binding. No additional token operator or administrator role is granted to TokenManager. The deployment script registers TokenManager as a multisig action consumer before locking bootstrap.

## Prepare the complete register

1. Reconcile the signed register extract against all existing shares and current holders. Confirm the declared total independently of the allocation list. All shares belong to the same OST class; do not split the register across calls.
2. Verify each holder's current canonical wallet against the platform's verified identity/wallet records. Resolve wallet migrations before preparing the final list. Whitelisting alone does not prove wallet ownership or the completeness of the company register.
3. Approve the wallets through AccessControl. Every address must be whitelisted, authorized, unfrozen, nonzero, outside the escrow and not a retired wallet. Checksum validation belongs in the client; Solidity receives a 20-byte address and cannot validate its original letter casing.
4. Use strictly increasing numeric address order, keeping each quantity with its address. Duplicate addresses and zero quantities are rejected. Combine holdings for the same verified canonical address before signing the extract.
5. Count the shared permanent IQS/OST slots. Existing slots are reused; new holders consume new slots. Slots at zero balance still count. The union must not exceed 149, and is checked again at execution.
6. Compute SHA-256 over the **exact bytes of the final signed off-chain extract**. Preserve that file unchanged. Do not hash a reformatted copy, a URL, unsigned content or a filename.

PowerShell example:

```powershell
$registerSha256 = "0x" + (Get-FileHash -LiteralPath ".\signed-register.pdf" -Algorithm SHA256).Hash.ToLowerInvariant()
```

Only addresses, integer quantities and opaque hashes belong in transaction inputs and multisig descriptions. Names, emails, phone numbers, document contents and free-text reasons remain off-chain. A hash provides an evidence commitment; the contract cannot inspect the signed extract or establish its completeness. The approving signers attest that it matches the full register and the declared total.

## Request, approve and execute

1. An administrator who is also a current multisig signer calls:

   ```solidity
   requestInitialShareRegistration(holders, quantities, declaredTotal, registerSha256)
   ```

   This validates and commits the full allocation list without changing balances or holder slots. It returns a monotonically increasing attempt ID and emits `InitialShareRegistrationRequested`. Only one attempt can be pending. Ordinary OST minting is blocked while it is pending; IQS operations remain subject to their existing rules and holder cap.

2. Read `getInitialShareRegistrationActionHash(id)` and encode the exact execution call:

   ```solidity
   registerInitialShares(id, holders, quantities, declaredTotal, registerSha256)
   ```

   A signer calls `AdminMultisig.proposeAction` with that action hash, TokenManager as consumer, the execution selector, `keccak256(executionCalldata)`, an opaque description and a valid deadline. Proposal creation is not an approval. Leave enough time before expiry for the 48-hour delay and execution.

3. Two of the three signers approve with `approveActionForConsumer`. If governance currently requires three approvals, all three are required. Each signer reviews the complete extract, canonical addresses, quantities, declared total and SHA-256.

4. Read `initialShareRegistrationReadyAt(id)`. It returns zero without a current valid quorum; otherwise it returns the effective quorum timestamp plus 48 hours. The delay never starts before the request event. Revoking quorum, renewing an expired proposal, changing the signer epoch or changing the configured threshold can invalidate the quorum or move the deadline. Always read the current value before execution.

5. At or after that time, while the proposal remains valid, an administrator submits the exact approved execution call. TokenManager rechecks zero OST supply, every wallet and the holder cap, consumes the approval, credits every balance, updates the OST holder list and supply, and locks the import permanently in **one atomic transaction**. Any revert rolls back all of these changes, including approval consumption.

The action hash includes the chain ID, TokenManager address, attempt ID, allocation commitment, declared total and extract hash. The explicit proposal intent check also requires the exact consumer, selector and calldata hash. Changing any approved allocation, address, total or extract requires a new attempt after Abort.

Initial shares are included in `totalSupplyOSTf()` and therefore in the existing valuation denominator. IQS balances, BSA allocations and existing holder slots are preserved. There is no partial execution or batch continuation function.

## Abort and retry

Before execution, including after the delay has elapsed, propose the separate action returned by:

```solidity
getAbortInitialShareRegistrationActionHash(id, reasonHash)
```

Bind the proposal to TokenManager and the exact calldata for `abortInitialShareRegistration(id, reasonHash)`. The reason must be a nonzero opaque evidence hash. The current configured quorum approves Abort; an administrator can then execute it immediately. Abort has no additional delay and remains available while TokenManager is paused. A single signer cannot abort and can use the existing pause mechanism while seeking the second approval.

Abort changes no balances, preserves the attempt history and clears the pending issuance gate. If OST supply is still zero, a new request gets a fresh ID and requires fresh approval and delay. Old approvals cannot authorize the new attempt. After successful import, neither retry nor Abort can reopen genesis.

## Platform alerts and ABI integration

The contract emits lifecycle events; **email and SMS delivery require the platform integration**. This Solidity change does not implement a Laravel mail/SMS worker. Before enabling this operation in the admin UI:

- Route `InitialShareRegistrationRequested` into the existing all-admin alert outbox and send both email and SMS to every base Admin, including admins who are not signers. Include the chain, contract, attempt ID, extract reference and review/Abort link; keep personal register contents out of the event and message preview.
- Track `ActionApproved` and current `initialShareRegistrationReadyAt(id)` to display the effective delay. A request event alone does not mean the quorum has approved.
- Handle `InitialSharesRegistered` and `InitialShareRegistrationAborted` as terminal outcomes. Cancel pending reminders after Abort. Use the final event for the import outcome rather than interpreting each `MintOST` log as a separate business operation.
- Make event ingestion durable and idempotent, record chain/contract/transaction/log identity, and handle finality and reorgs. Do not rely on an admin browser remaining open to send alerts.
- Verify the alert delivery path on staging before enabling registration. Event emission by itself is not proof that either channel delivered.

Regenerate the backend, bridge and frontend ABIs from the final reviewed source. Update the admin workflow to encode the exact new calls and parameters; existing generic proposal screens alone do not perform register reconciliation or canonical-wallet verification.

## Deployment and verification

These contracts have no upgrade proxy. This source change does not modify an already deployed TokenManager. Deploy the reviewed module set with the updated deployment script and verify its bindings; do not replace a single address in an existing installation without a reviewed migration plan.

Run:

```sh
forge test --match-contract InitialShareRegistrationTest -vv
forge test
forge build --sizes
```

The regression suite checks complete atomic imports, commitment binding, zero supply, wallet eligibility at execution, the permanent shared cap, all 149 holders in one call, delay, revocation, proposal expiry, signer rotation, higher thresholds, Abort, pause behavior and fuzzed balances. Use the final reviewed compiler settings when measuring gas and deployed code size.
