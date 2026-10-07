# RISE test coverage

These tests build on the accepted suite and exercise the deployed `Rise` contract through
its public API. They use the existing vendored dependencies and require no network, forks,
environment variables, token storage edits, or generated inputs from `.imd/`.

| File | Coverage |
| --- | --- |
| `Rise.t.sol` | Exact constructor mint and metadata, events, zero/one/full/maximum amounts, arbitrary nonzero recipients, direct and delegated transfers, failure atomicity, absent administrative entry points, and forbidden runtime opcodes. |
| `RiseAllowanceBoundary.t.sol` | Finite maximum versus infinite allowances, replacement/idempotence, reduction/revocation, owner and spender isolation, replay after exhaustion, failure then funded retry, allowance preservation on direct transfers, zero transfers, and self-transfer overdrafts. |
| `RiseInvariant.t.sol` | Random sequences across five holders with independent balance and allowance ledgers; fixed supply, exact balances, allowance isolation/consumption, and rollback after rejected calls. |
| `LaunchFlow.t.sol` | Existing CREATE2 deployment, constructor ownership, duplicate-deployment rejection, 90%/10% allocation, claims, and both pool token transfer directions. |

The two unit/fuzz suites each request 1,000 runs per fuzz property through inline Foundry
configuration. The invariant suite requests 256 sequences of depth 96 for each property,
with unexpected handler reverts treated as failures. Only nine action selectors on the
handler are targeted; getters and the token itself are not random call targets.

Every holder starts funded and an allowance ring includes finite and infinite approvals.
The handler mixes transfers, arbitrary-sized approvals, valid and invalid delegated spends,
revocation followed by an unauthorized spend, rejected direct/delegated transfers, invalid
approvals, and complete-balance round trips. Rejected calls must return the expected custom
error and leave the ledgers unchanged. The round trip also checks the intermediate balances
and supply, so an outbound fee cannot be hidden by the return leg. The invariant checks every
tracked owner/spender pair, including pairs unrelated to the latest operation.

Assumptions and limits:

- Supply is exactly `1_000_000_000e18`; the entire initial balance belongs to the constructor's
  caller. The factory performs launch allocation after deployment.
- The launch definition assigns 90% to the pool, 10% to the network distributor, and zero to
  the creator. The existing fixture tests those exact token movements.
- Standard behavior includes replacement approvals, zero-value transfers between nonzero
  addresses, and infinite allowance at `uint256.max`. `uint256.max - 1` is finite. Assertions
  about custom errors follow the vendored implementation.
- Only holders and their approved spenders may move funds. Self-transfers must still satisfy
  balance and allowance checks. Transfers do not migrate a holder's approvals to a recipient.
- The factory, Merkle distributor, Uniswap v4 manager, and resolved launch inputs are not
  present here. The supplied protected integration test covers the actual pool seed and
  swaps externally; local tests do not establish AMM price, fees, liquidity custody, or
  Merkle claim correctness.

Run from the repository root:

```sh
forge build --offline --out test/scratch/out --cache-path test/scratch/cache
forge test --offline --out test/scratch/out --cache-path test/scratch/cache
```

The flags keep disposable compiler output and caches inside the allowed scratch directory.
The submitted tests also run with ordinary `forge build` and `forge test`.
