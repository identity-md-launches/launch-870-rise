# Rise (RISE)

Rise is a community meme token with plain ERC-20 transfers. Its constructor mints exactly
**1,000,000,000 RISE**, with **18 decimals**, to `msg.sender`. The on-chain supply is
`1000000000000000000000000000` minor units. There are no constructor arguments.

The production contract is [`src/Rise.sol`](src/Rise.sol), built on the vendored OpenZeppelin
ERC-20 implementation. It has no owner, transfer tax, mint after construction, external burn,
blacklist, pause, seizure, upgrade, initialization, or recovery function. There are no token
callbacks, external contract calls, oracle reads, timestamps, or chain-specific addresses.

## Build and test

Prerequisites: Foundry and Solidity **0.8.26**. Compiler selection is pinned by version in
`foundry.toml`; dependencies and their licenses are included under `lib/` for offline verification.

```sh
forge build
forge test
forge fmt --check
```

Verified locally with Foundry 1.8.3 and solc 0.8.26: build, all 32 reported tests (including
both invariant properties), and formatting passed. A fresh source-only copy also passed
`forge build --offline`, `forge test --offline --threads 4`, and formatting with an empty
process environment, no cached artifacts and no `.imd/` inputs. Vendored checksums matched.

The build uses the Paris EVM target, optimizer with 200 runs, and `bytecode_hash = "none"`.
Paris is a conservative EVM-compatible target that avoids requiring PUSH0. No FFI, filesystem
permissions, RPC endpoints, environment variables, or wallet keys are needed by the tests.

- `test/Rise.t.sol`: metadata, constructor mint event, exact transfers, allowances, zero/full/max
  values, failure atomicity, contract recipients, absent administrative entry points, opcode
  restrictions, and three fuzz properties (512 cases each).
- `test/LaunchFlow.t.sol`: CREATE2 factory ownership, duplicate deployment rejection, 90%/10%
  allocation, distributor claim transfers, and both pool token transfer directions.
- `test/RiseInvariant.t.sol`: randomized transfers, approvals and delegated transfers among five
  holders, checked against a separate balance/allowance model (128 sequences of depth 64 for each
  of two invariants).

The launch flow fixture tests ERC-20 movements only. It does not implement Uniswap, liquidity
pricing, trading fees, or Merkle proofs. The supplied protected test additionally requires the
network's ProjectFactory support contracts, Uniswap v4 dependencies and resolved launch inputs;
it is an external admission check, not a standalone test in this repository.

## Launch allocation and assumptions

The intended entry point is the network's **`ProjectFactory.launchCustom`**. The factory must
deploy Rise itself, receive the whole supply, then complete the following allocation:

| Destination | Share of total supply | RISE | Minor units |
| --- | ---: | ---: | ---: |
| Single liquidity pool | 90% (`poolBps = 9000`) | 900,000,000 | 900000000000000000000000000 |
| Network MerkleDistributor | 10% (network-controlled) | 100,000,000 | 100000000000000000000000000 |
| Creator wallet | 0% | 0 | 0 |

The remaining 10% is interpreted using the supplied network launch definition: 2% of total
supply for accepted contributors and 8% for connected paired seats. The network computes the
recipient set, Merkle root and claims; Rise does not implement a second distributor.

The constructor deliberately does not allocate tokens or seed a pool: the admission check
requires the factory to hold 100% immediately after construction. The factory must transfer
the distributor share and seed the 90% pool allocation atomically. Direct deployment by a
wallet would put all tokens in that wallet and **would not fulfill the launch allocation**.
The token alone cannot force its initial holder to provide liquidity.

The name is **Rise**, following the explicit token-name field; the symbol is **RISE**.
The supplied [social reference](https://x.com/surfcoderepeat/status/2107650558039658980) could not
be fetched (HTTP 403); no additional mechanics were inferred from it.

## Deployment parameters and responsibilities

| Parameter | Value or responsibility |
| --- | --- |
| Contract artifact | `src/Rise.sol:Rise` |
| Constructor arguments | `[]` (empty ABI encoding) |
| Name / symbol / decimals | `Rise` / `RISE` / `18` |
| `totalSupply` | `1000000000000000000000000000` |
| Application contracts | `[]` |
| `economics.poolBps` | `9000` |
| Creator remainder | Exactly zero tokens |
| `economics.remainderTo` | Network-provided requester address; no tokens allocated to it |
| Paired currency default | Native ETH (`address(0)`); no pair was specified |
| Pool fee default | `3000` (0.30% trading fee), set by the pool, not Rise |
| Tick spacing default | `60` |
| Opening market-cap default | `10000000000000000000` wei (10 ETH, fully diluted); planning assumption, not a valuation claim |
| Chain / factory / PoolManager / launch number | Supplied and verified by the network deployer; none were included in this assignment |
| Pool price / ticks / liquidity / hook | Derived and validated by the network from actual addresses, currency ordering and launch economics |

The unspecified economic values above are explicit planning defaults. They are not embedded
in the token bytecode. The network's separate manifest step owns `launch.json` and must resolve
the target chain and deployment addresses before admission. Use no substitute addresses from
the background L2 tables. This project requires a chain that accepts standard solc EVM bytecode;
a chain requiring a different compiler, such as zkSync Era, is outside this build profile.

For the ETH default, opening price is `10 ETH / 1,000,000,000 RISE = 0.00000001 ETH/RISE`.
Both use 18 decimals. The deployment system must derive `sqrtPriceX96` using the actual
`currency1/currency0` ordering and align the single-sided liquidity range to the pool tick spacing.
Do not reuse a price from a different pair or from reversed currency ordering.

To inspect the local deployment artifact without sending a transaction:

```sh
forge inspect src/Rise.sol:Rise abi
forge inspect src/Rise.sol:Rise bytecode
```

The network operator is responsible for deploying through the factory, matching the compiled
artifact and constructor arguments, verifying sources on the selected chain, checking the
distributor funding, and checking the actual seed and a buy/sell through the PoolManager. A
single-sided concentrated-liquidity seed may round down and leave dust: the operator must
account for it under the network's pool policy and ensure it is not forwarded to the creator.
The 90% figure is the pool allocation, not a claim that AMM rounding can always consume every
minor unit. The creator's allocation remains zero.

Liquidity position custody, locks, fee collection and withdrawal rights belong to the network
pool/factory policy. This token does not lock liquidity or guarantee its permanence. No deployment,
broadcast, funded wallet access, or on-chain pool creation is performed by this project.

## ERC-20 behavior and review notes

Transfers and approvals return `true` on success and revert with OpenZeppelin custom errors
on failure. Zero-amount transfers are allowed between nonzero addresses. Self-transfers preserve
balances. Transfers to the zero address revert, so they cannot burn supply. An approval replaces
the previous value; finite allowances decrease on `transferFrom`, while `uint256.max` remains an
infinite allowance. Users should approve only intended spenders/amounts and manage allowance
changes carefully; standard approval ordering can expose both old and new allowances to a spender.

`Transfer` events describe mints and transfers. `Approval` is emitted by `approve`; this vendored
implementation does not emit it for allowance consumption in `transferFrom`. Indexers should read
`allowance` when needed. ERC-20 transfers do not notify recipients. Assets sent to Rise itself
cannot be recovered, and ordinary native-ETH payments revert.

The implementation has no administrative trust role once deployed. The initial factory controls
the supply only as its holder until it executes the launch allocation. The small token wrapper and
vendored ERC-20 logic have been reviewed for reachable mint/burn functions, transfer fees, external
calls and administrative control. Tests are not an independent security audit. The network must
obtain its independent adversarial review before release; Slither and Mythril have not been run.

Dependency versions, licenses, upstream URLs and checksums are recorded in
[`lib/DEPENDENCIES.md`](lib/DEPENDENCIES.md).
