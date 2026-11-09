# Guardian Angel — Stage 4a Notes (public repo + README + Sourcify retry)

Executed 2026-11-10 (WITA). Scope: safety sweep, public GitHub repo + README,
Sourcify verification retry. (Demo video and DoraHacks submission are later
stages with Rev — not done here.)

## Public repo

- **URL:** https://github.com/Revaaa28/guardian-angel — visibility **PUBLIC**
  (verified via `gh repo view`: `guardian-angel | PUBLIC`), README renders
  (rendered-HTML check via the GitHub API contains the README title).
- Initial commit: **`e5b531d`** — "Guardian Angel: anti-drain vault for
  Reactive Omni Buildathon" (99 files). Follow-up commit with the README
  verification wording + these notes: see `git log` on `main`.
- Git identity (local): Revaaa28 <revlyrotty.rr@gmail.com>.
- **Vendoring fix during commit:** `lib/forge-std` and `lib/reactive-lib-omni`
  initially staged as gitlinks (they carried their own `.git`); their `.git`
  dirs were removed and the library contents committed as plain trees, so a
  plain `git clone` → `forge test` works with no submodule step. Pinned
  versions are unchanged (reactive-lib-omni `3ade0dcf…`, forge-std `dc647cc…`).

## Safety sweep (before any commit)

- Grepped all commit candidates (`src/`, `test/`, `*.md`, `foundry.toml`, plus
  staged list review) for private-key / mnemonic / seed material:
  - Only hits: STAGE2_NOTES.md explanatory text ("Private key lives ONLY in
    …0600 file") and `--private-key <burner>` **placeholders** in the
    ready-to-run commands. **No key values anywhere.**
  - All 64-hex strings present are public data: transaction hashes in
    STAGE3_NOTES.md, the pinned library commit hash in BUILD_NOTES.md, and
    the well-known `REACTIVE_IGNORE` constant in the tests.
  - No bare (non-`0x`) 64-hex strings; no `.env` files in the project.
- The wallet key file stays outside the repo at
  `~/workspace/wallets/guardian-angel-testnet-wallet.txt` (chmod 600) — never
  copied in.
- `.gitignore` added: `out/`, `cache/`, `broadcast/` (dry-run residue),
  `.env*`.

## README

Judge-facing README.md written at repo root: problem statement, the
origin → reactive → callback loop, architecture table for
GuardianToken / GuardianVault / GuardianReactive, the Omni patterns used
(AbstractReactive / onlySystem, subscribe topic filters,
requestCallbackV_1_0, address(0) payload placeholder, depositTo reserves on
both sides, coverDebt, timestamp-based cooldown), deployment addresses with
Reactscan / Basescan links and deployment receipts, the full-loop proof
(small-transfer no-op pair + drain origin/reactive/callback trio with links,
`GuardianTriggered(500 GTT, …, 450 GTT)`), final live state (frozen = true,
450 GTT at cold, withdraw reverts `Frozen()`), measured fees (evaluation
≈ 0.0115 lREACT; callback ≈ 0.00000095 ETH), security model + honest
limitations, `forge test` instructions (16/16), and an MIT `LICENSE` file.

## Sourcify verification retry — STILL UNVERIFIED (endpoint unresponsive)

Attempts on 2026-11-10, per contract:

| Contract | Chain | Method(s) | Outcome |
|---|---|---|---|
| GuardianToken `0x638D26a8…ec81` | 84532 | `forge verify-contract --verifier sourcify` (×2); curl POST to `/server/v2/verify/84532/…` with trimmed stdInputJson (3.2 KB, ×2, up to 240 s) | forge: POST repeatedly timed out. curl: request sent in full, **0 bytes received** before timeout |
| GuardianVault `0xAa41E6ef…895f` | 84532 | (same environment; POST path proven dead on the Token — not re-sent to avoid duplicate stalled jobs) | Not verified |
| GuardianReactive `0x638D26a8…ec81` | 5318007 | (same) | Not verified |

Diagnostics:
- `GET https://sourcify.dev/server/v2/contract/{chain}/{address}` responds in
  ~1 s from this VM and reports `"match": null` for all three contracts —
  so read egress works, and no earlier (stage-3 or interrupted) submission
  ever landed.
- The verify **POST** is the dead path: TLS completes (via the VM's egress
  proxy), the body is delivered, and the server never responds — the same
  behavior stage 3 saw with forge. Verbose curl trace recorded in this
  session: "Operation timed out … with 0 bytes received".
- Payloads used for the API attempts were built from the artifacts' own
  compiler metadata (Solc `v0.8.29+commit.ab55807c`, optimizer off,
  evmVersion `osaka`, exact source closures, foundry remappings) and are
  preserved at `/tmp/sourcify-Guardian{Token,Vault,Reactive}.json` on this VM
  (ephemeral path — regenerate from `out/<Contract>.sol/<Contract>.json`
  metadata if needed).
- Because submissions may be processed asynchronously server-side even when
  the response never arrives, a later re-check is one GET per contract:
  `https://sourcify.dev/server/v2/contract/84532/0x638D26a8da9FD4E68de6c5eaB237A4343f43ec81`,
  `…/84532/0xAa41E6ef5C0Ed3b6c5175A258774178bF127895f`,
  `…/5318007/0x638D26a8da9FD4E68de6c5eaB237A4343f43ec81`.
  Any future host with working POST egress to sourcify.dev can complete
  verification in one command per contract, e.g.
  `forge verify-contract --verifier sourcify --chain-id 84532 0x638D…ec81 src/GuardianToken.sol:GuardianToken`
  (Vault constructor args: token, cold, reactive; Reactive: 100 GTT cap,
  cold, 300 — see STAGE3_NOTES.md).

**Bottom line:** repo + README are live and public; Sourcify verification
remains outstanding purely due to the verify endpoint's unresponsiveness
from this build environment — non-blocking for the buildathon (bytecode is
reproducible from the public repo).
