# Guardian Angel — Stage 3 Notes (live deployment + full-loop demo)

Status: **COMPLETE — the full origin → reactive → callback loop ran live on testnet.**
Executed 2026-11-10 (WITA). Deployer/owner = wallet-1 `0x23Db606b54Dee94A2e10Fe65A9Bd5cBf48634F80`.
COLD (sweep destination) = wallet-3 `0x2fd33cE60Df5aC3727726306d0091cA7Ae592A98`.
ATTACKER (demo recipient) = wallet-2 `0xaDB7814d279D75Cf11c80323DF394320b2652B6f`.
Networks: Lasna (5318007, `https://lasna-rpc.rnk.dev/`), Base Sepolia (84532, `https://sepolia.base.org`;
log queries via `https://base-sepolia-rpc.publicnode.com` after the official RPC 403'd a script client).
SYSTEM (Lasna) = `0x8888888888888888888888888888888888888888`; Base Sepolia callback proxy =
`0x476F44b11F5C942c58f4c8E3d0300E5710743585`.

## Deployed contracts

| Contract | Chain | Address |
|---|---|---|
| GuardianToken (GTT) | Base Sepolia | `0x638D26a8da9FD4E68de6c5eaB237A4343f43ec81` |
| GuardianReactive | Lasna | `0x638D26a8da9FD4E68de6c5eaB237A4343f43ec81` |
| GuardianVault | Base Sepolia | `0xAa41E6ef5C0Ed3b6c5175A258774178bF127895f` |

Note: the token and the reactive contract share one address on two different chains — both were
wallet-1's nonce-0 CREATE on their chain (first-ever sends). Harmless, but worth knowing when
reading explorers.

Reactive params (verified on-chain after deploy): cap = 100 GTT (100e18), coldAddress = wallet-3,
cooldown = 300 s, owner = wallet-1, balance 1.5 lREACT, debt 0.

## Step 1–3: deployments

- GuardianToken deploy (Base Sepolia): tx `0xfeebcccf1678f7fb8b499595837a788aa4fc2ae4a30d575eac12c78928800cc7` — verified name/symbol/owner on-chain.
- GuardianReactive deploy (Lasna, `--value 1.5 lREACT`, args cap=100e18, cold=wallet-3, cooldown=300): tx `0x5be7299cde2e605df06a7dc5dbf2f2cc2e1f7e6bbd1ccdfe584516476d824348` (block 7936988, status 1).
- GuardianVault deploy (Base Sepolia, args token, cold=wallet-3, reactive): tx `0x95af58a41be75a78a76947ec12174e949c0b84aa337e914c95d92173662769ea` — verified token/cold/owner/frozen=false on-chain.

## Step 4: wiring (Lasna)

- `setDestination(vault)`: tx `0x2867f3f2d52c9e96f38d43d31cf8fcc388fadc12f98bd8bad71f829978511bc4`
- `watch(token, vault)`: tx `0x2092f5fcf0f1f45c108e85c251d0db970094cb8f1612295dbad2471cef0a3caa`
- Verified afterwards: destination == vault, watchedToken == token, watchedVault == vault.

## Step 5: reserve funding

- Lasna `SYSTEM.depositTo(reactive)` 0.3 lREACT: tx `0x8988b1e6f77a6a144068234b845066a2fb6c11d52f36ffc1ba1ddb9eb620aefd`
- Base Sepolia `proxy.depositTo(vault)` 0.01 ETH: tx `0xf5616765fa296bcd9bb50b97e04eeb8fa4588744f0bef87c217492159b3f9bfe`
- Direct 0.005 ETH to the vault (its `pay()` balance): tx `0xde8099e05ac26c9c7ea119c273fb0c45546d88bdb830f200dd62796a6200cbb1`
- Post-funding: reactive debt 0, vault debt 0, vault ETH balance 0.005.

## Step 6: Sourcify verification — FAILED for all three (network, non-blocking)

All three `forge verify-contract --verifier sourcify` submissions (Token + Vault on chain 84532,
Reactive on chain 5318007) timed out reaching `https://sourcify.dev/server/v2/verify/...` from
this VM (repeated attempts, incl. forge's own retries). No verification was confirmed. The
bytecode on-chain is exactly what `forge build` (Solc 0.8.29, pinned lib) produced; verification
can be re-attempted from any host with working egress to sourcify.dev.

## Step 7: demo setup (Base Sepolia)

- `mint(1000 GTT → wallet-1)`: tx `0x19bda1c9632f94989bf0335915363d190ab239cee6f448c6b6539e8ee7ed77bf`
- `approve(vault, 1000 GTT)`: tx `0xc044f75ecaef80ce87602dbe51b6effbd9fa000fb0276ec95ddb09067bf4157f`
- `vault.deposit(1000 GTT)`: tx `0x6417597f1a7a813086bbf4fee0e7b83c9ff6a737abdded4c5c3f0713190bd25d`
- Vault GTT balance confirmed = 1,000 GTT.

## Step 8: SMALL TEST — below-cap withdraw, guardian stays quiet ✅

- Origin tx (Base Sepolia): `vault.withdraw(wallet-2, 50 GTT)` =
  `0x4c1c5b5cd50d0ae9a4c453fcd1e03becb38feb4b4d3ab5e9acd1ca8f304d6392`
- Reactive tx (Lasna): `0x496191c03de628ba1b66d6ad26c36b7ea61e9ee31cc98df793c85bf978e58120`
  (block 7939332). Lasna reactive deliveries are txs **to the SYSTEM contract** (selector
  `0xcebbda8d`) whose calldata embeds the LogRecord — this tx's input contains the origin tx
  hash, token, vault (topic1), wallet-2 (topic2) and the 50 GTT value. Its receipt has **0 logs:
  no CallbackRequest** — the guardian evaluated and correctly did nothing.
- State after: `lastTrigger` = 0, `frozen` = false, vault GTT = 950. Reserves were charged
  0.0115337 lREACT for the evaluation (0.3 → 0.2884663), matching the brief's fee model.

## Step 9: DRAIN TEST — over-cap withdraw, guardian fires ✅

- **Origin tx** (Base Sepolia, block 56629765): `vault.withdraw(wallet-2, 500 GTT)` =
  `0xdaedf5822294b8a53cfa7c8b31bc67911e51eade729169bb1c32c8bc795bde5c`
- **Reactive tx** (Lasna, block 7939887): `0x7e49b5a463ef6d09cec81ae6c9a366c3ffb45fa1bd5ea331afbd18fe1446ff70`
  — status 1, one log: SYSTEM's `CallbackRequest` (topic0 `0xef94dbc6…`). `lastTrigger` set to
  1794247821, the same timestamp carried into the callback payload.
- **Callback tx** (Base Sepolia, block 56629775):
  `0x9a503565acc7dc93ff5b2cc6b84c0d7169479eae0ee6062a07377b95ed8571a0`
  — from the Reactive Signer `0xF7E866D726658F6C3F14B8EE537fe268a4D91DDb`, **to the callback proxy
  `0x476F44b11F5C942c58f4c8E3d0300E5710743585`**, status 1. It emitted
  `GuardianTriggered(amount_ = 500 GTT, ts_ = 1794247821, sweptAmount_ = 450 GTT)` on the vault.
- Whole loop (origin → callback landed) completed in about a minute.
- `SYSTEM.getCallbacks(0x7e49b5a4…)` (signature `getCallbacks(uint256)` per the Economy docs):
  returned **`[]` on every call** (checked repeatedly over ~20 minutes after delivery). Per the
  docs, validators write these records after delivery and an empty array means "not recorded
  yet", not failure. The delivery is proven independently on-chain: the `CallbackRequest` log in
  the reactive tx, the callback tx itself (below), and the `GuardianTriggered` event + final
  state. Re-checking this getter later is a one-line call if a written record is ever needed.

## Step 10: freeze holds ✅

`cast call vault.withdraw(wallet-2, 1 GTT)` (from wallet-1) on the frozen vault reverts with
`Frozen` (error `Frozen()`, selector `0xa8cab3d1`). Call only — nothing sent.

## Final state (all read on-chain after the loop)

| Item | Value |
|---|---|
| Vault GTT | 0 |
| Cold (wallet-3) GTT | 450 |
| Wallet-2 ("attacker") GTT | 550 (50 small + 500 drain) |
| Vault `frozen` | true |
| Vault ETH balance / debt | 0.005 ETH / 0 (callback fee ≈ 0.00000095 ETH came out of proxy reserves: 0.01 → 0.0099990499696) |
| Reactive balance / reserves / debt | 1.5 lREACT / 0.2613854 lREACT / 0 (two evaluations charged against reserves) |
| Reactive `lastTrigger` | 1794247821 |
| Wallet-1 balances | Sepolia 0.0548935 ETH (untouched), Lasna 0.1469588 lREACT, Base Sepolia 0.0099885 ETH |

## Deviations / surprises

1. Sourcify verification could not be completed from this VM (egress timeouts to
   sourcify.dev) — see step 6. Non-blocking per the stage brief.
2. Reactive deliveries on Lasna are not standalone txs to the reactive contract; they are
   system txs to `0x8888…8888` (selector `0xcebbda8d`) embedding the LogRecord in calldata.
   Finding them = scan for that shape + match the origin tx hash inside the input.
3. The official Base Sepolia RPC (`https://sepolia.base.org`) returned 403 to a bare Python
   client; log queries were run against `https://base-sepolia-rpc.publicnode.com` instead.
   All state-changing sends went through the official RPC without issue.
