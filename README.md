# 🛡️ Guardian Angel — the anti-drain wallet

**Set it once, and your vault defends itself.** Guardian Angel is an always-on,
fully autonomous wallet guardian built on **Reactive Network (Omni)**: a reactive
smart contract on the **Lasna** testnet watches every outbound transfer from a
vault on **Base Sepolia**. The moment a single transfer exceeds the cap you set,
the guardian fires a cross-chain callback that **freezes the vault and sweeps
everything that's left to your cold address** — no human in the loop, no keeper,
no bot to keep alive. You set the rules once; the network does the rest.

> Built for the **Reactive Omni Buildathon** (DoraHacks), track
> **Set It and Forget It**. The full loop — origin event → reactive evaluation →
> callback → freeze & sweep — has already executed live on testnet; the proof
> transactions are linked below.

---

## The problem

Wallet drains are fast and one-directional. A compromised key, a malicious
approval, or a fat-fingered transfer can empty a hot wallet in a single block —
long before the owner notices, let alone reacts. Conventional defenses are all
reactive in the *human* sense: alerts you might sleep through, monitoring bots
you have to host and babysit, multisigs that slow down everyday use.

What you actually want is a guard that **never sleeps, cannot be phished, and
acts in the same moment the bad transfer lands**. That is exactly what reactive
smart contracts are for: event-driven execution that lives on-chain, not on
someone's server.

## How it works

```
 Base Sepolia (origin)                Lasna (Reactive)              Base Sepolia (destination)
 ┌───────────────────┐   Transfer    ┌────────────────────┐  callback  ┌────────────────────┐
 │  GuardianVault    │ ─── event ──▶ │  GuardianReactive  │ ─────────▶ │  GuardianVault     │
 │  withdraw(500 GTT)│  from vault   │  react(): 500 >    │  via proxy │  freezeAndSweep(): │
 │                   │               │  cap 100 → trigger │            │  freeze + sweep    │
 └───────────────────┘               └────────────────────┘            │  450 GTT → cold    │
                                                                        └────────────────────┘
```

1. **Origin event.** The vault (`GuardianVault`) holds the user's tokens.
   Every withdrawal emits a standard ERC-20 `Transfer` log with the vault as
   sender.
2. **Reactive evaluation.** `GuardianReactive`, deployed on Lasna, subscribes
   to exactly those logs (`Transfer` with `topic1 == vault`). The Reactive
   Network delivers each matching log to its `react()` function. It silently
   ignores ordinary activity — transfers at or below the cap, transfers to the
   cold address itself (the vault's own rescue sweep), and repeat breaches
   inside the cooldown — and **never reverts**, because a reverting reactive
   contract is still billed in full.
3. **Callback.** A genuine breach makes `react()` request a callback via
   `SYSTEM.requestCallbackV_1_0`, addressed to the vault on Base Sepolia with a
   1,000,000 gas limit and a payload whose first argument is the mandatory
   `address(0)` placeholder (the callback proxy overwrites it with the reactive
   contract's address — that is how the vault authenticates the call).
4. **Freeze + sweep.** The callback lands on the vault through the Base Sepolia
   callback proxy. `freezeAndSweep()` checks both guards
   (`onlyServiceProvider` + `onlyCallbackSender`), sets `frozen = true`, and
   transfers the vault's **entire remaining balance** to the cold address. From
   that block on, every `withdraw` reverts with `Frozen()` until the owner
   deliberately unfreezes.

End-to-end, the live drain test below completed the whole loop in **about a
minute**.

## Architecture

| Contract | Chain | Role |
|---|---|---|
| `GuardianToken` (GTT) | Base Sepolia | Minimal dependency-free ERC-20 (18 dp). The asset the vault protects; its canonical 3-topic `Transfer` logs are what the guardian subscribes to. |
| `GuardianVault` | Base Sepolia | Holds the owner's GTT. Owner can `deposit` / `withdraw` while unfrozen. Its `freezeAndSweep` endpoint is an `AbstractCallback` receiver: authenticates the callback proxy and the injected reactive-contract address, freezes, and sweeps everything to the immutable cold address. |
| `GuardianReactive` | Lasna (5318007) | The watchdog. An `AbstractReactive` contract that subscribes to the vault's outbound `Transfer` events, evaluates cap / cold-address / cooldown rules in `react()`, and requests the freeze callback on breach. Owner-tunable `cap` and `cooldown`; exposes `coverDebt()` on both sides. |

### Omni patterns used

- **`AbstractReactive` + `onlySystem`** — `react()` is only callable by the
  Reactive system contract (`0x8888…8888`).
- **`SYSTEM.subscribe(chainId, contract, topic0, topic1, …)`** — topic-filtered
  subscription: only `Transfer` logs *sent by the vault* are delivered.
- **`SYSTEM.requestCallbackV_1_0(CallbackConfiguration_V_1_0{…})`** — the
  current Omni callback API (not the legacy `Callback` event).
- **`address(0)` payload placeholder** — the proxy injects the caller's
  address as the first argument; `GuardianVault` verifies it with
  `onlyCallbackSender(reactive_)` before acting.
- **`depositTo()` reserves on both sides** — reactive-transaction fees are
  prepaid in lREACT on Lasna; callback delivery fees are prepaid in Base
  Sepolia ETH at the callback proxy, billed to the *recipient* (the vault).
- **`coverDebt()` exposed on both contracts** — any debt above zero silently
  halts execution; either side can settle from its own balance and revive.
- **Timestamps, never block counts** — Base Sepolia produces ~200 ms blocks,
  so the cooldown is enforced against `block.timestamp`, per the buildathon
  ground rules.
- **Deployment order is forced by immutable auth**: reactive contract first,
  then the vault (which bakes the reactive address in immutably), then
  `setDestination()` + `watch()` wire the pair together.

Toolchain: Foundry, Solidity **0.8.29**, Reactive contracts library
[`Reactive-Network/reactive-lib-omni`](https://github.com/Reactive-Network/reactive-lib-omni)
pinned at commit `3ade0dcf1d27e67e5783ef807e73a1b9e0c0cce8` (vendored under
`lib/`, remapped as `@reactive/`).

## Live deployment (testnet)

| Contract | Address | Explorer |
|---|---|---|
| GuardianToken (GTT) | `0x638D26a8da9FD4E68de6c5eaB237A4343f43ec81` | [Base Sepolia (Basescan)](https://sepolia.basescan.org/address/0x638D26a8da9FD4E68de6c5eaB237A4343f43ec81) |
| GuardianReactive | `0x638D26a8da9FD4E68de6c5eaB237A4343f43ec81` | [Lasna (Reactscan)](https://lasna.reactscan.net/address/0x638D26a8da9FD4E68de6c5eaB237A4343f43ec81) |
| GuardianVault | `0xAa41E6ef5C0Ed3b6c5175A258774178bF127895f` | [Base Sepolia (Basescan)](https://sepolia.basescan.org/address/0xAa41E6ef5C0Ed3b6c5175A258774178bF127895f) |

(Fun fact: the token and the reactive contract share one address on two
different chains — both were the deployer's nonce-0 CREATE on their chain.)

**Live parameters:** cap = **100 GTT** per transfer · cooldown = **300 s** ·
cold address = `0x2fd33cE60Df5aC3727726306d0091cA7Ae592A98` · callback proxy
(Base Sepolia) = `0x476F44b11F5C942c58f4c8E3d0300E5710743585` · system contract
(Lasna) = `0x8888888888888888888888888888888888888888`.

Deployment receipts:
[Token deploy](https://sepolia.basescan.org/tx/0xfeebcccf1678f7fb8b499595837a788aa4fc2ae4a30d575eac12c78928800cc7) ·
[Reactive deploy](https://lasna.reactscan.net/tx/0x5be7299cde2e605df06a7dc5dbf2f2cc2e1f7e6bbd1ccdfe584516476d824348) ·
[Vault deploy](https://sepolia.basescan.org/tx/0x95af58a41be75a78a76947ec12174e949c0b84aa337e914c95d92173662769ea)

**Source verification:** all three contracts are **verified on Sourcify with
perfect matches** — both runtime and creation bytecode matched for each
(Solc 0.8.29+commit.ab55807c, verified 2026-11-09):
[GuardianToken](https://repo.sourcify.dev/84532/0x638D26a8da9FD4E68de6c5eaB237A4343f43ec81)
(match ID 58939733) ·
[GuardianVault](https://repo.sourcify.dev/84532/0xAa41E6ef5C0Ed3b6c5175A258774178bF127895f)
(match ID 58939894) ·
[GuardianReactive](https://repo.sourcify.dev/5318007/0x638D26a8da9FD4E68de6c5eaB237A4343f43ec81)
(match ID 58940045).
Deployment bytecode is the exact output of `forge build` from this repo
(pinned library), so anyone can also reproduce and compare it. The full
verification log is in [`STAGE4_NOTES.md`](STAGE4_NOTES.md).

## Proof: the full loop, on-chain

The vault was funded with 1,000 GTT, then exercised twice.

### 1️⃣ Ordinary transfer — the guardian stays quiet

A 50 GTT withdrawal (below the 100 GTT cap):

- **Origin tx** — `vault.withdraw(attacker, 50 GTT)`:
  [`0x4c1c5b5c…d6392`](https://sepolia.basescan.org/tx/0x4c1c5b5cd50d0ae9a4c453fcd1e03becb38feb4b4d3ab5e9acd1ca8f304d6392)
- **Reactive tx** — the system delivered the log to `react()` on Lasna:
  [`0x496191c0…58120`](https://lasna.reactscan.net/tx/0x496191c03de628ba1b66d6ad26c36b7ea61e9ee31cc98df793c85bf978e58120)
  Its receipt contains **zero logs — no callback was requested**. `lastTrigger`
  stayed 0, the vault stayed unfrozen. The guardian evaluated and correctly
  did nothing.

### 2️⃣ Drain attempt — the guardian fires

A 500 GTT withdrawal to a fresh "attacker" address:

- **Origin tx** (Base Sepolia) — `vault.withdraw(attacker, 500 GTT)`:
  [`0xdaedf582…de5c`](https://sepolia.basescan.org/tx/0xdaedf5822294b8a53cfa7c8b31bc67911e51eade729169bb1c32c8bc795bde5c)
- **Reactive tx** (Lasna) — `react()` detected the breach and emitted the
  system's `CallbackRequest`:
  [`0x7e49b5a4…ff70`](https://lasna.reactscan.net/tx/0x7e49b5a463ef6d09cec81ae6c9a366c3ffb45fa1bd5ea331afbd18fe1446ff70)
- **Callback tx** (Base Sepolia) — delivered by the Reactive Signer through
  the callback proxy into `freezeAndSweep()`:
  [`0x9a503565…71a0`](https://sepolia.basescan.org/tx/0x9a503565acc7dc93ff5b2cc6b84c0d7169479eae0ee6062a07377b95ed8571a0)
  It emitted
  `GuardianTriggered(amount_ = 500 GTT, ts_ = 1794247821, sweptAmount_ = 450 GTT)` —
  the 500 GTT that left is gone, but the remaining **450 GTT was rescued to the
  cold address** instead of following it.

### Final on-chain state

| Item | Value |
|---|---|
| Vault GTT balance | **0** (swept) |
| Cold address GTT | **450 GTT** ✅ rescued |
| Attacker GTT | 550 (50 test + 500 drain) |
| Vault `frozen` | **true** — a further `withdraw` was verified to revert with `Frozen()` |
| Debt (both sides) | **0** — both contracts remain `active` |

## What it costs to run

Measured on testnet during the live demo:

- **Evaluation** (one delivered log, no action): ≈ **0.0115 lREACT**, charged
  against the reactive contract's prepaid reserves.
- **Callback delivery** (the freeze + sweep): ≈ **0.00000095 ETH**, charged
  against the vault's prepaid reserves at the Base Sepolia proxy.
- Reserves were funded with 0.3 lREACT (`depositTo` on Lasna) and 0.01 ETH
  (`depositTo` at the proxy) — enough for dozens of evaluations and callbacks.

In other words: pennies of testnet value buy a guard that watches your vault
around the clock and acts within about a minute of a breach.

## Security model & limitations

**Security model**

- The vault only accepts freeze orders from one source: a transaction whose
  `msg.sender` is the official Base Sepolia callback proxy **and** whose
  proxy-injected first payload address equals the one immutable
  `GuardianReactive` address. The reactive contract, in turn, only accepts
  `react()` calls from the Reactive system contract.
- The cap check runs in the reactive contract, not in the vault, mirroring how
  a production deployment would separate always-on policy from asset custody.
- The guardian cannot steal anything: its only possible action is "freeze and
  send the remainder to the owner's own cold address". A false trigger is an
  inconvenience (owner unfreezes), never a loss — and the vault's own sweep is
  explicitly filtered so the rescue transfer can never re-trigger the guardian.

**Limitations (honest list)**

- **Testnet demo asset.** GTT is a purpose-built test token; the demo proves
  the Reactive loop, not a production custody product.
- **The breaching transfer itself is not undone.** Reactive contracts react
  *after* an event. The guardian caps the damage (everything still in the
  vault is rescued and the vault freezes) rather than preventing the first
  over-cap transfer.
- **Cap mirroring.** The cap lives in the reactive contract; the vault does
  not independently enforce it on `withdraw`. Changing the cap is an
  owner transaction on Lasna (`setCap`).
- **One watched pair per `watch()` call**, and subscriptions live in the
  Reactive nodes, not in contract storage — they can't be read back on-chain.
- **Funding is operational, not automatic.** If either side's reserves run dry
  and debt accrues, execution pauses until `coverDebt()` settles it. The
  exposed `coverDebt()` and prepaid reserves are the mitigation.
- **Cooldown trade-off.** The 300 s cooldown prevents trigger storms but also
  means a second distinct breach within the window rides on the first freeze —
  acceptable because the first trigger already empties and freezes the vault.

## Run the tests

```bash
forge build
forge test        # 16/16 passing
```

The suite etches mocks onto the *real* system-contract and callback-proxy
addresses, so the production base classes talk to the doubles at their
production addresses. It proves, among other things: the exact six-argument
subscription; silent handling of below-cap, exactly-at-cap, cold-address,
sub-3-topic, and in-cooldown logs; exactly one callback on breach with a
correctly encoded payload (`address(0)` first argument, breached amount,
timestamp, 1,000,000 gas limit, chain 84532); rejection of callbacks from a
non-proxy caller and from the proxy carrying a wrong injected sender; freeze →
`withdraw` reverts → `unfreeze` restores; and `coverDebt()` settlement on both
contracts.

## Repository layout

```
src/    GuardianToken.sol · GuardianVault.sol · GuardianReactive.sol
test/   Foundry tests + mocks (MockSystemContract, MockCallbackProxy)
lib/    reactive-lib-omni (pinned) · forge-std (tests only)
BUILD_NOTES.md / STAGE2_NOTES.md / STAGE3_NOTES.md / STAGE4_NOTES.md
        stage-by-stage engineering log: design decisions, funding, live
        deployment receipts, and verification status
```

## License

MIT — see [`LICENSE`](LICENSE).
