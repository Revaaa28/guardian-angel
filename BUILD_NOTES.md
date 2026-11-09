# Guardian Angel — Build Notes (Stage 1: local only)

Reactive Omni Buildathon (DoraHacks), track **Set It and Forget It**. Stage 1 is contracts +
local Foundry tests only — nothing deployed, no wallets created, nothing pushed.
Status: `forge build` clean (Solc 0.8.29), `forge test` **16/16 passing**.

## Toolchain & pinned dependencies

| Item | Pin |
|---|---|
| Foundry | forge 1.9.0 (commit 6056c5845d34205a83cf7108042adb137325c9df) |
| Solc | **0.8.29** (pinned via `solc_version` in `foundry.toml`) |
| Reactive contracts library | **Reactive-Network/reactive-lib-omni**, commit **`3ade0dcf1d27e67e5783ef807e73a1b9e0c0cce8`** — vendored at `lib/reactive-lib-omni/`, remapped as `@reactive/` → `lib/reactive-lib-omni/` |
| forge-std (tests only) | commit `dc647cc030d9d65910d8f1172a0cde48d7106e32`, at `lib/forge-std/` |

The brief left the library repo name UNVERIFIED; it is resolved here. The docs' GitHub links for
`AbstractReactive`, `ISystemContract`, `AbstractCallback`, `AbstractPayer` and `IPayable` all point
into **Reactive-Network/reactive-lib-omni** (`src/base/…`, `src/interfaces/…`), which matches the
documented `@reactive/src/…` import paths exactly. The older `reactive-smart-contract-demos` repo
was *not* used as the library (it is the demos repo, and pre-Omni in places).

Key constants (from the research brief / docs, re-verified at build time):

- System contract `SYSTEM` = `0x8888888888888888888888888888888888888888` (hardcoded inside
  `AbstractReactive`; same on mainnet and Lasna). Lasna chain ID 5318007.
- Base Sepolia: chain ID **84532**, callback proxy **`0x476F44b11F5C942c58f4c8E3d0300E5710743585`**
  (hardcoded in `GuardianVault` as its `AbstractCallback` service provider).
- `REACTIVE_IGNORE` = `0xa65f96fc951c35ead38878e0f0b7a3c744a6f5ccc1476b313353ce31712313ad`.

## Contracts

### `src/GuardianToken.sol` — Guardian Test Token (GTT)
Minimal hand-rolled ERC-20 with zero external dependencies: name "Guardian Test Token", symbol
GTT, 18 decimals, standard `transfer` / `approve` / `transferFrom` / `balanceOf` / `allowance`,
and an owner-only `mint`. It exists so the vault protects a real ERC-20 whose `Transfer` logs
have the canonical 3-topic shape the reactive contract subscribes to, and so stage-2 transfers
are fully under our control on testnet.

### `src/GuardianVault.sol` — the vault (Base Sepolia)
An `AbstractCallback` contract that holds the owner's GTT. The owner funds it with `deposit()`
(transferFrom) and can `withdraw()` while unfrozen. Its callback endpoint
`freezeAndSweep(address reactive_, uint256 amount_, uint256 ts_)` is guarded exactly per the
Callback Contracts docs — `onlyServiceProvider` (caller must be the Base Sepolia callback proxy)
plus `onlyCallbackSender(reactive_)` (the proxy-injected first address must be the
GuardianReactive contract, stored immutably at construction). On trigger it sets `frozen = true`,
transfers its **entire** remaining GTT balance to the immutable `coldAddress`, and emits
`GuardianTriggered(amount_, ts_, sweptAmount)`. `unfreeze()` is owner-only; `coverDebt()` exposes
`AbstractPayer._coverDebt()` because the proxy bills this contract (in Base Sepolia ETH) per
callback delivery; native funding arrives via the payable `receive()` inherited from
`AbstractPayer`.

### `src/GuardianReactive.sol` — the watchdog (Lasna)
An `AbstractReactive` contract with a payable constructor taking `(cap, coldAddress, cooldown)`.
`watch(token, vault)` (owner-only) subscribes via `SYSTEM.subscribe` to Base Sepolia (84532)
`Transfer` logs of the token whose **topic1 equals the vault** — i.e. only transfers *sent by* the
vault. `react()` never reverts; it silently ignores logs with fewer than 3 topics, transfers at or
below `cap`, transfers whose recipient is the cold address (the vault's own sweep — this is what
stops the guardian from re-triggering on its own rescue), and breaches inside the cooldown
window. A genuine breach records `lastTrigger` and calls `SYSTEM.requestCallbackV_1_0` with
chainId 84532, the destination vault, gasLimit 1,000,000, and payload
`freezeAndSweep(address(0), value, block.timestamp)` — first argument the mandatory `address(0)`
placeholder the proxy overwrites. `setDestination()` / `setCap()` / `setCooldown()` are
owner-only; `coverDebt()` is exposed for lREACT fee settlement.

### Tests (`test/`, 16 passing)
`MockSystemContract` is etched onto the real system-contract address `0x8888…8888` and
`MockCallbackProxy` onto the real Base Sepolia proxy address, so the production base classes talk
to the doubles at their production addresses. Proven: `watch()` subscribes with the exact six
arguments; `react()` ignores below-cap (incl. exactly-at-cap), cold-address, <3-topic, and
in-cooldown logs; a genuine breach requests exactly one callback whose payload decodes to
`freezeAndSweep` with `address(0)` first arg, the breached amount, and the current timestamp,
addressed to the vault on chain 84532 with gasLimit 1,000,000; `freezeAndSweep` reverts for a
non-proxy caller (`NotAuthorized`) and for the proxy carrying a wrong injected sender
(`CallbackNotAuthorized`), and on the happy path freezes + sweeps the full balance to cold;
`withdraw` reverts while frozen and works after `unfreeze()`; `coverDebt()` settles a mocked
debt on both contracts.

## Deviations from the brief / docs pattern (with reasons)

1. **Subscription is created by `watch()` after deployment, not in the constructor.** The task
   design requires it: the subscription's topic1 is the vault's address, and the vault cannot
   exist before the reactive contract (its immutable callback sender *is* the reactive
   contract). Note the brief's deploy-order section already forces this shape (reactive →
   callback → setter); `watch()` is the subscription step of that same order.
2. **`react()` guards `log_.data.length < 32` before `abi.decode`.** The brief mandates
   never-revert (reverts are billed in full); a short/malformed payload would otherwise make
   `abi.decode` revert. The guard is a silent fall-through, consistent with the brief's rule.
3. **`react()` also falls through when `destination` is unset.** Requesting a callback to
   `address(0)` would be rejected `NotAContract` yet still burn fees; until `setDestination()`
   is called there is nowhere legitimate to call. Unreachable in the stage-2 wiring order.
4. **Ownership is hand-rolled** (`owner` + `onlyOwner` in each contract). The pinned
   reactive-lib-omni ships no Ownable; the docs' `onlyOwner` example presumes one. Adding
   OpenZeppelin for two modifiers was judged unnecessary dependency weight for stage 1.
5. **`deposit()` is permissionless** (it pulls the caller's own tokens via transferFrom, so it
   cannot take anyone else's funds). The task marks only `withdraw` / `unfreeze` as owner-only;
   left as specified.
6. **No explicit `receive()` override in either contract.** `AbstractPayer.receive()` is already
   payable and inherited; an override would need `override(AbstractPayer, IPayer)` and adds no
   behavior. Both contracts accept native funds as deployed.
7. **Lint warnings (non-blocking)** from forge's default lints: unchecked ERC-20 transfer
   returns (our own token always returns true or reverts — checked-by-construction),
   event-after-call ordering in `freezeAndSweep` (state is set before the transfer; the emit is a
   report, kept last deliberately), and `block.timestamp` comparison (mandated by the buildathon
   ground rules — timestamps, not block counts).

## Stage-2 checklist (deployment & wiring — NOT done in stage 1)

Prereqs: a funded deployer on both chains — lREACT on Lasna (buy via the Base Sepolia faucet
contract `0x2afaFD298b23b62760711756088F75B7409f5967`, **max 5 SepETH per tx, excess is lost**)
and test ETH on Base Sepolia. Re-verify the Origins & Destinations table (proxy address) and the
Lasna RPC (`https://lasna-rpc.rnk.dev/`) against the live docs before deploying.

1. **Deploy `GuardianToken`** on Base Sepolia (any time before step 3). Mint demo GTT to the owner.
2. **Deploy `GuardianReactive`** on Lasna (chain 5318007), constructor `(cap, coldAddress,
   cooldown)`, **payable — fund with lREACT at deployment** (`--value`) so the first reactive
   transactions are covered.
3. **Deploy `GuardianVault`** on Base Sepolia (84532), constructor `(token, coldAddress,
   reactiveAddress)`, **fund with test ETH at deployment** — callbacks are billed to the vault.
   Double-check the reactive address: it is baked in immutably; a mistake means redeploying the
   vault.
4. **Wire the reactive side:** `GuardianReactive.setDestination(vaultAddress)`, then
   `GuardianReactive.watch(tokenAddress, vaultAddress)`.
5. **Fund both sides' reserves** via `depositTo` (never send funds directly to the system
   contract — that credits your EOA, not the contract):
   - `SYSTEM.depositTo(reactiveAddress)` on Lasna (lREACT) — covers reactive-transaction fees.
   - `proxy.depositTo(vaultAddress)` on the Base Sepolia callback proxy (test ETH) — covers
     callback delivery fees.
   - Keep both contracts' own balances topped up too, and confirm `coverDebt()` is callable so
     either side can be revived if it ever goes inactive (debt > 0 silently stops everything).
6. **Fund the vault with GTT:** owner approves + `deposit(amount)` on the vault.
7. **Verify both Reactive-side and destination contracts on Sourcify**
   (`forge verify-contract --verifier sourcify --chain-id 5318007 …` for Lasna).
8. **Prove the loop and capture the evidence trio:** make an over-cap outbound GTT transfer from
   the vault (e.g. owner `withdraw` above cap — note the withdraw itself emits the watched
   Transfer), then collect (a) the origin tx on sepolia.basescan.org, (b) the reactive tx on
   lasna.reactscan.net showing `CallbackRequest`, (c) the callback tx on Basescan delivering
   `freezeAndSweep` through the proxy; cross-check with `SYSTEM.getCallbacks(reactiveTxHash)`
   (empty `err` = success). Confirm the vault shows `frozen == true` and the cold address holds
   the swept GTT.
9. Sanity-check Reactscan shows `GuardianReactive` as `active` (not blacklisted for debt) before
   recording the demo video.
