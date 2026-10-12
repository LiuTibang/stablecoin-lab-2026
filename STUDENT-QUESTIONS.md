# STUDENT-QUESTIONS.md — Discussion questions (submit with your repo)

Answer directly under each question. 150–300 words each — **reasoning over length**.

---

## A. Permission design

**A1.** The vault holds `MINTER_ROLE`, so it can `burn` any user's balance. Explain why that is a risk, then write out how you would change `Vault` and `SimpleStablecoin` to remove it.

MINTER_ROLE currently combines issuance and destruction authority. Any holder can call burn(from, amount) against an arbitrary address without that holder's consent. The deployed vault exposes only caller-based redemption, so an ordinary user cannot simply select another victim through Vault.redeem. Nevertheless, granting this role gives the vault address excessive authority, and a compromised authorized contract or another privileged holder can destroy balances. Burning also reduces totalSupply, so a backing invariant can still pass while users suffer confiscation.

I would separate minting from burning. SimpleStablecoin would retain a narrowly assigned mint role and provide burn(amount) for the caller's own tokens plus burnFrom(owner, amount) that spends the owner's allowance before burning. Vault.redeem would call burnFrom(msg.sender, amount), then transfer collateral to that same caller. Users would explicitly approve the vault for redemption; allowances should be limited to the intended amount. Every unrestricted privileged burn entry point must be removed, otherwise the bypass remains. Tests should cover absent and insufficient allowances, allowance consumption, successful redemption, and rollback when collateral transfer fails. Governance must still secure mint-role assignments because consent-based burning cannot prevent unbacked issuance.

**A2.** In this contract `DEFAULT_ADMIN_ROLE`, `MINTER_ROLE` and `PAUSER_ROLE` all go to the same address. How would you split them in production, and who holds each?

Production should separate the authority to change permissions, issue tokens, and stop operations. DEFAULT_ADMIN_ROLE should belong to a governance multisignature with independent signers and a timelock for routine role changes. Its responsibility is appointing or revoking operational roles, not everyday minting. Administrative recovery procedures and signer rotation should be documented, with monitoring of every grant and revocation.

MINTER_ROLE should belong only to the approved collateral vault contracts whose issuance rules are enforced on-chain. The initial deployer should relinquish its direct mint role after configuration and verification. Otherwise an administrator's everyday wallet remains an alternative issuance route that bypasses deposits. Additional issuers, if necessary, should have separate limits and explicit accounting.

PAUSER_ROLE should belong to a security response multisignature able to act quickly during an exploit. A different governance process should authorize recovery and unpausing; that distinction requires changing the current contract because both functions presently use the same role. Independent signers reduce correlated compromise, while monitoring and issuance limits reduce damage before response. Separation does not eliminate trust: the administrator can still grant new privileges, and an abusive pause can block users' exits.

---

## B. Pausing and redemption

**B1.** `_update` is the single entry point for every balance change, so `pause()` freezes transfers, minting and redemption together. If you wanted "pause transfers but **allow redemption**", how would you change it? Give the approach — full code not required.

The present whenNotPaused modifier on _update rejects every token balance change, including burns. Vault.redeem therefore fails during a pause even though its collateral transfer would otherwise be valid. To pause only transfers, I would replace the unconditional modifier with a conditional check: reject the update when paused and both from and to are nonzero. Ordinary transfers and transferFrom then stop, while a burn, identified by to == address(0), can proceed. Calling super._update must remain mandatory so normal ERC-20 accounting still applies.

Minting needs an explicit policy. If the intended emergency mode also stops issuance, reject updates with from == address(0) while paused, or enforce an independent issuance pause in mint. Allowing redemption should not inadvertently allow new supply. Burns must still satisfy authorization; removing a pause check does not justify arbitrary balance destruction.

The vault should burn only the redeeming user's authorized tokens and send collateral to that user atomically. Tests should demonstrate paused transfers and issuance reverting, redemption succeeding, and failed burns or collateral transfers reverting the entire transaction. Finally, an underlying collateral token can itself freeze transfers, so permitting sUSD burns alone does not guarantee a working exit.

**B2.** In 2008, when a money-market fund "broke the buck", redemptions were frozen for days. In 2023 USDC depegged to $0.87 after a reserve bank failed, but redemptions were **not** shut. Compare the two responses — what does closing the redemption channel, or leaving it open, do to a stablecoin?

Closing redemption removes the direct route from a claim to its backing. Holders can still trade a transferable token, but buyers must estimate recovery value and waiting time rather than rely on immediate conversion at par. Discounts can deepen because arbitrageurs cannot buy cheaply and redeem promptly. Suspension can reduce forced sales and protect remaining investors from an unfair first-mover advantage, yet it also leaves investors unable to access their money.

The Reserve Primary Fund suffered losses associated with Lehman securities and suspended redemption payments in September 2008. USDC's March 2023 episode instead involved uncertainty about bank reserves and access to settlement. Circle maintained its commitment to one-dollar redemption, with normal processing resuming on Monday; weekend banking constraints and backlogs mean this was not uninterrupted instant redemption. Keeping a credible exit supported arbitrage once settlement resumed, but confidence also depended on reserve recovery and official protection of bank depositors.

These examples distinguish solvency from liquidity. An open channel cannot sustainably redeem worthless backing at par, and a temporary closure does not itself prove assets are insufficient. A stablecoin needs credible reserves, accessible liquidity, and clear crisis rules together.

Sources: [SEC](https://www.sec.gov/divisions/investment/guidance/reservefundmmffaq.htm), [Circle](https://www.circle.com/pressroom/3-3-billion-of-usdc-reserve-risk-removed-dollar-de-peg-closes), [Circle operations](https://www.circle.com/blog/march-15-update-on-usdc-operations).

---

## C. Depeg analysis

**C1.** Under what conditions does this coin depeg? Distinguish at least two classes of cause, and say how each one shows up in the invariant `totalCollateral() >= totalSupply()`.

One cause is insufficient backing. If an authorized attacker mints without depositing, totalSupply increases while totalCollateral stays unchanged, so totalCollateral() >= totalSupply() becomes false. A theft or unexpected loss of collateral can cause the same numerical failure. With the price-sensitive Ex5 vault, a falling collateral price can destroy economic backing even when its token quantity remains constant; the relevant comparison must use conservative collateral value rather than raw token units.

A second cause is an unavailable redemption channel. Pausing sUSD, freezing the collateral token, censorship, or operational failure can prevent conversion while the quantity invariant remains true. Holders may sell below par because obtaining the backing is delayed or uncertain. The assertion proves accounting coverage, not timely access.

A third issue is the collateral's own dollar value. The core vault compares two six-decimal quantities and assumes one USDC represents one dollar. If USDC depegs, the invariant can pass while sUSD is worth less than one dollar economically. Liquidity shortages, transaction costs, and confidence shocks can also create temporary market deviations. Therefore monitoring should combine quantity coverage, reserve valuation, redemption availability, and market liquidity; a passing invariant alone cannot prove a market peg.

**C2.** Suppose an attacker bribes their way to `MINTER_ROLE`, mints 1,000,000 sUSD out of nothing and redeems it all. Describe the flow of funds, and name the step that could have stopped them.

After obtaining MINTER_ROLE, the attacker calls stable.mint(attacker, 1_000_000e6). No collateral enters the vault because the token's mint function does not require a deposit. Supply rises by one million sUSD, and the backing inequality fails immediately if the system was previously exactly backed. The attacker then calls vault.redeem, which burns the attacker's tokens and transfers the same number of MockUSDC units from existing reserves to the attacker.

Full redemption requires at least one million USDC already in the vault. If less is present, redeeming the entire amount reverts at InsufficientCollateral. The attacker can instead redeem smaller amounts up to available reserves. Existing holders then share the remaining collateral shortage; burning the attacker's newly issued tokens does not repair their losses because reserves leave at the same time.

The decisive preventive control is the privilege assignment: an attacker must never receive unrestricted mint authority. Remove unnecessary deployer mint rights and secure role administration with independent signers, delayed changes, and monitoring. An unauthorized mint is rejected by onlyRole, but that guard deliberately accepts a bribed authorized holder. Vault-level backing checks can limit immediate reserve extraction, while issuance caps and collateral-aware minting provide additional defenses. Monitoring the invariant after minting detects damage; it does not itself prevent a transaction.

---

## D. Toward RWA

**D1.** Right now the collateral is `MockUSDC` and `totalCollateral()` just reads an on-chain balance — simple and reliable. If the collateral were **US Treasuries**, could this invariant still be written that way? What new problems appear?

Treasuries cannot be counted by reading an ERC-20 balance and assuming each unit equals one dollar of immediately available collateral. A tokenized Treasury position may represent fund shares or a legal claim against a custodian. Its dollar value depends on price, accrued interest, fees, maturities, and whether the issuer actually owns unencumbered securities. Rising yields can reduce market value before maturity even when contractual repayment remains expected.

I would express backing as conservative, independently verified net asset value, after liabilities and risk haircuts, compared with redeemable stablecoin supply. On-chain holdings might identify claims, but an oracle or attestation must connect those claims to off-chain positions and current valuations. Stale data, fabricated attestations, double pledging, and custodian insolvency become new failure modes. Ownership and bankruptcy treatment require legal verification beyond a smart-contract assertion.

Liquidity also needs a separate constraint. Securities may be valuable but unavailable during market closures or settlement delays. A cash buffer, redemption queue, and limits on immediate withdrawals should reflect this mismatch. Independent custody reconciliation and audits complement oracle checks. The resulting invariant is conditional on trustworthy data and enforceable ownership; it is no longer a complete proof obtained from one on-chain token balance.

**D2.** If the collateral were **a building**, how would you put it inside this vault? Which off-chain roles or legal structures would you have to introduce?

A building cannot physically enter a smart contract. A legal entity, commonly a special-purpose vehicle, would hold title, and tokens would represent a defined interest in that entity or a secured claim against it. The vault could custody those tokens, but its enforceable rights must be specified: owning a token does not automatically transfer land title or give holders a right to foreclosure proceeds.

The arrangement needs a title registry or conveyancing process, legal counsel, an independent trustee or security agent, property management, insurance, valuation professionals, and an administrator connecting lawful ownership records to token issuance. Depending on jurisdiction and the offering, transfer restrictions and investor eligibility checks may also be required. Documents should address liens, taxes, maintenance costs, governance, default, and bankruptcy remoteness.

A reliable value feed would use conservative appraisals and account for debt and sale expenses. Appraisals are infrequent and can lag market stress. Redemption cannot promise immediate one-dollar cash merely because the vault holds property tokens: selling a building may take months and require court or registry procedures. A cash reserve, queued redemptions, and explicit loss allocation are necessary. The smart contract manages claims and accounting, while legal institutions enforce ownership and liquidation off-chain.

---

## E. Tests (Tier 1 required — this is Ex4)

Turn the red tests green in `test/exercises/01_LoopTasks.t.sol` to cover the scenarios below, and write your test function names here:

| Scenario | Your test function name |
|---|---|
| Minting by a non-minter reverts | `test_Ex4_Mint_RevertsForNonMinter` |
| Transfers revert while paused | `test_Ex4_Pause_BlocksTransfers` |
| **Redemption** reverts while paused | `test_Ex4_Pause_BlocksRedeem` |
| An attacker cannot burn someone else's balance | `test_Ex4_AttackerCannotBurnOthersBalance` |
| ...but the vault holding `MINTER_ROLE` can | `test_Ex4_VaultHoldsTheKey_CanBurnAnyonesBalance` |

That last pair is meant to be read together: the guard is written correctly, but the key was handed to the vault. Keep it in mind when you answer A1.

Now write one more scenario you consider **most likely to be attacked**, and say why you picked it:

The highest-priority additional scenario is a compromised minter draining legitimate reserves. Seed the vault through an honest user's deposit, grant MINTER_ROLE to an attacker as the threat assumption, mint unbacked sUSD, then redeem it against the honest user's collateral. Assert the exact reserve transfer and the remaining honest supply's backing deficit. This is an exploit-demonstration test of the current design, not a claim that the attack should revert today. I chose it because a privileged issuance bypass defeats otherwise correct deposit/redeem arithmetic. A hardened version should add a separate regression test proving the unauthorized issuance or withdrawal is blocked. This scenario is proposed here; Ex0–Ex4 tests were preserved unchanged.
