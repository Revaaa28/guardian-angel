# Guardian Angel — Stage 2 Notes (funding)

Status as of 2026-11-10 ~00:55 WITA: **wallet created and saved; funding BLOCKED at the
pk910 PoW faucet's captcha wall; all balances still 0; no transactions sent.**
The bridge address for step 4 was verified ahead of time so the rest of stage 2 can run
immediately once the burner holds SepETH.

## Burner wallet (testnet-only)

- Address: `0x23Db606b54Dee94A2e10Fe65A9Bd5cBf48634F80`
- Created with `cast wallet new` (Foundry 1.9.0). Private key lives ONLY in
  `~/workspace/wallets/guardian-angel-testnet-wallet.txt` (chmod 600) — never printed in chat
  or reports. Testnet-only; never use on mainnet, never fund with real assets.
- One key controls the same address on all three chains (Sepolia / Base Sepolia / Lasna).

## Balances (verified on-chain 2026-11-10)

| Asset | Chain | Balance | How obtained |
|---|---|---|---|
| SepETH | Ethereum Sepolia (11155111) | **0** | Not yet — blocked, see below |
| ETH | Base Sepolia (84532) | **0** | Not yet — depends on the L1→L2 bridge (needs SepETH) |
| lREACT | Reactive Lasna (5318007) | **0** | Not yet — conversion needs SepETH or Base Sepolia ETH |

RPCs used for the checks: `https://ethereum-sepolia-rpc.publicnode.com`,
`https://base-sepolia-rpc.publicnode.com` (the official `https://sepolia.base.org` timed out
from this VM), `https://lasna-rpc.rnk.dev/` (chain ID confirmed 5318007 live).

## Task 2 — Sepolia ETH via pk910 PoW faucet: BLOCKED (captcha wall)

The faucet itself is healthy and rich (live `getFaucetStatus`: wallet balance ≈ 6,424 SepETH;
min claim 0.05, max 2.5 SepETH per session; PoW = CryptoNight, difficulty 12, hashrate cap
1,000 H/s). But the live instance config (`GET /api/getFaucetConfig`) has the captcha module
enabled with **`requiredForStart: true`** (provider: pk910's own custom browser captcha served
from `faucets.pk910.de/captcha/`). A direct `POST /api/startSession` with the burner address
returns, verbatim:

```json
{"status":"failed","failedCode":"INVALID_CAPTCHA","failedReason":"captcha check failed: captcha token missing"}
```

So no mining session can be started headlessly at all — the PoW miner never gets to run, and
there is no documented CLI miner for this instance (the PoWFaucet wiki documents browser mining
only). Per the stage-2 instructions the attempt stopped at the captcha wall; the captcha was
not bypassed or auto-solved. Accumulated via this route: **0 SepETH** (hashrate n/a — mining
could not start).

Other keyless routes checked: the other public PoW faucet (pow.zalalena.com) gates on
hCaptcha; Alchemy / QuickNode / Coinbase CDP / Infura faucets all require an account or login,
which stage 2 forbids creating. No genuinely keyless, captcha-free Sepolia or Base Sepolia drip
was found.

### What unblocks this (any one of these)

1. **Human/browser session on sepolia-faucet.pk910.de**: pass the captcha once, mine in the
   browser tab to ≥0.05 SepETH (target ~0.3+), claim to the burner address
   `0x23Db606b54Dee94A2e10Fe65A9Bd5cBf48634F80` (faucets send to the pasted address — the
   burner's key never needs to leave its file). Then steps 3–4 below are pure `cast` calls.
2. Same idea on Chainlink's faucets (faucets.chain.link — Sepolia and Base Sepolia both exist)
   or thirdweb's faucet: browser + wallet connect, send to the burner address.
3. Anyone with spare SepETH/Base Sepolia ETH sends ≥0.2 SepETH directly to the burner address.

Note the stage-2 fallback inside the project itself: lREACT can equally be bought via the
**Base Sepolia** faucet contract (below), so a direct Base Sepolia drip alone also unblocks
everything except the bridge step.

## Task 3 — lREACT conversion: NOT RUN (no funds yet)

Ready to run the moment the burner holds ≥0.05 SepETH:

```
cast send 0x9b9BB25f1A81078C544C829c5EB7822d747Cf434 --value 0.05ether \
  --private-key <burner> --rpc-url <sepolia-rpc>   # → 5 lREACT on Lasna (1 ETH → 100 lREACT)
```

(Or on Base Sepolia: send to `0x2afaFD298b23b62760711756088F75B7409f5967` instead. Hard cap
5 ETH per tx — excess is lost; we are far below it.) Verify afterwards with
`cast balance <burner> --rpc-url https://lasna-rpc.rnk.dev/`.

## Task 4 — Base Sepolia bridge: address VERIFIED, transfer NOT RUN (no funds yet)

**L1StandardBridge (on Ethereum Sepolia) for Base Sepolia:
`0xfd0Bf71F60660E2f608ed56e1659C450eB113120`**

- Source: official Base docs, "Contract Addresses" — L1 Contract Addresses → Ethereum Testnet
  (Sepolia) table (https://docs.base.org/chain/base-contracts, page updated 2026-09-29).
- On-chain cross-check (Ethereum Sepolia, 2026-11-10): contract has code;
  `otherBridge()` → `0x4200000000000000000000000000000000000010` (the L2StandardBridge
  predeploy — matches the docs' Base Sepolia L2 table); `messenger()` →
  `0xC34855F4De64F1840e5686e64278da901e261f20` (the docs' Sepolia L1CrossDomainMessenger).
  All three agree — this is the right bridge.

Ready to run once funded:

```
cast send 0xfd0Bf71F60660E2f608ed56e1659C450eB113120 "depositETH(uint32,bytes)" 200000 0x \
  --value 0.1ether --private-key <burner> --rpc-url <sepolia-rpc>
```

then poll `cast balance <burner> --rpc-url https://base-sepolia-rpc.publicnode.com` until the
0.1 ETH lands on Base Sepolia.

## Transaction hashes

None — no transaction could be sent (all balances are 0 and every funding route is gated).
This section gets filled in as soon as step 2 is unblocked.

## Stage 2 completion (2026-11-10)

Wallet-1 (`0x23Db606b54Dee94A2e10Fe65A9Bd5cBf48634F80`) was funded with 0.05 SepETH
(Google Cloud Web3 faucet claims by Rev). Both remaining stage-2 operations were then
executed from wallet-1 on Ethereum Sepolia (RPC `https://ethereum-sepolia-rpc.publicnode.com`):

1. **lREACT conversion — DONE.** Plain value transfer of 0.02 SepETH to the Sepolia faucet
   contract `0x9b9BB25f1A81078C544C829c5EB7822d747Cf434`.
   - Tx: `0x00af7dc2c2baa51914750cc0ec7653a91aed11862458a7bcb7eb2eb1e83f31bb` (block 12098920, status success)
   - Result: **2.1 lREACT** credited on Lasna (balance verified via `https://lasna-rpc.rnk.dev/`).
     Slightly above the expected 2.0 (0.02 × 100) — the faucet paid a small excess.
2. **Base Sepolia bridge — DONE.** `depositETH(uint32,bytes)` (200000, 0x) with 0.025 SepETH
   to the verified L1StandardBridge `0xfd0Bf71F60660E2f608ed56e1659C450eB113120`.
   - Tx: `0x77da63d4906dc6f69d7f09135ab8f3493a3b8eff971c19787965b94d437e3006` (block 12098922, status success)
   - L2 credit landed in full after ~5 minutes of polling: **0.025 ETH on Base Sepolia**
     (chain 84532 confirmed via both `https://sepolia.base.org` and publicnode).

**Final balances (verified on-chain, wallet-1):**

| Asset | Chain | Balance |
|---|---|---|
| SepETH | Ethereum Sepolia (11155111) | 0.054893510122887295 ETH |
| lREACT | Reactive Lasna (5318007) | 2.1 lREACT |
| ETH | Base Sepolia (84532) | 0.025 ETH |

Note: the Sepolia remainder is higher than these two operations alone would leave
(0.05 − 0.02 − 0.025 − gas ≈ 0.0015 ETH) — additional SepETH arrived in wallet-1 from the
parallel wallet-2 → wallet-1 sweep activity, so the gas buffer is comfortably above target.
Wallet-2 and wallet-3 in the key file were not touched by this completion run, and no
contracts were deployed.
