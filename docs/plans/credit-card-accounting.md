# Credit-card accounting plan

Status: proposed. This is a grounded design, not shipped behavior or physical-device acceptance. Implementation must follow groomed T-190 child briefs in [T-190](../tasks/T-190.md). T-190 remains in Backlog.

## Current-state inventory

| Area | Verified current behavior | Missing for card accounting |
|---|---|---|
| Payment sources | [`PaymentSources`](../../lib/data/db/tables/payment_sources_table.dart) stores kind, masked identifier, institution and ownership/activity/analytics flags. [`_backfillPaymentSources`](../../lib/data/db/database.dart) and the insert trigger infer source identity from `account_hint + channel`; both default `is_owned` and `include_in_analytics` to true. | Channel `card` does not identify credit/debit/prepaid/add-on products. Inferred ownership is not user confirmation. |
| Owned transfers | [`PaymentSourceRepository.updateSource`](../../lib/data/repositories/payment_source_repository.dart) calls reconciliation when ownership or active state changes. T-165b rebuilds settled, currency-equal, reciprocal singleton debit/credit pairs through bounded timestamp-index probes; it changes only differing flags, removes stale system-generated `transfer_leg` edges, preserves user links, and performs no writes on an unchanged rerun. | A bank debit alone cannot be allocated to card liability. Card payment allocation, target review and undo remain open in T-190b2. |
| Transaction lifecycle and links | [`TransactionLinks`](../../lib/data/db/tables/transaction_links_table.dart) stores transaction-to-transaction `echo`, `settles`, `reverses`, `refunds`, `repays`, `transfer_leg` and `fulfills` links. [`EventCorrelator.correlate`](../../lib/capture/event_correlator.dart) proposes matches; [`SmsIngestor`](../../lib/capture/sms_ingestion.dart) persists transaction rows, lifecycle values and echo links, but does not persist its proposed non-echo links. | Existing rows and links do not define a canonical card-liability delta or end-to-end allocation projection. |
| Eligibility | [`FinancialEligibility`](../../lib/data/analytics/financial_eligibility.dart) includes settled, nondeleted, nonduplicate, nonexcluded debit rows outside an owned transfer; missing category defaults to spending, explicitly nonspending categories are excluded. | Card refunds, reversals, payments and charges need link-aware net-spend and liability rules shared by all aggregate consumers. |
| Card SMS parsing | [`MessageKindClassifier.classify`](../../lib/capture/message_kind_classifier.dart) recognizes lifecycle cues; [`SmsIngestor`](../../lib/capture/sms_ingestion.dart) stores lifecycle state. [`GenericTransactionParser._hardReject`](../../lib/capture/generic_transaction_parser.dart#L69) rejects refund, reversal, declined, failed, statement and due cues, so those shapes require a matching template rather than generic fallback. | A parsed card debit does not prove a settled purchase or owned credit card. Template coverage and source identity remain reviewable. |
| Templates and fixtures | [`docs/sms-templates.md`](../sms-templates.md) documents card-spend/payment templates and negative cases. [`test/fixtures/sms/README.md`](../../test/fixtures/sms/README.md) defines synthetic `.txt` and `.expected.json` fixtures. | Existing parsing fixtures do not assert card liability, allocation, statement due or undo. |
| Dedup, currency and restore | [ADR 0003](../decisions/0003-dedup-and-counterparty.md) governs duplicate links; [ADR 0017](../decisions/0017-source-currency-fidelity.md) preserves source currency; [ADR 0008](../decisions/0008-bounded-encrypted-backups.md), [ADR 0016](../decisions/0016-backup-domain-state-and-restore-order.md), [ADR 0015](../decisions/0015-durable-sms-disposition.md) and [ADR 0011](../decisions/0011-evidence-backed-assistance.md) govern retention, restore, disposition and correction. | Any proposed card metadata, snapshots, allocations and user decisions need additive schema, backup/reset, correction and undo coverage. |

GitNexus impact for `reconcileOwnedTransfers` on the main-checkout index found two direct callers (`updateSource` and `materialized_projections_test.dart`), LOW risk, and no affected process. Index freshness was not confirmed, so the graph result is navigation-only; current-state claims above were checked against this worktree's source.

## Scenario map

This table is the single definition of each synthetic case and its expected accounting behavior. Amounts are INR unless stated. Fixture IDs are unique and reused by sequences and task acceptance. A `reverses` link nets spending in the original purchase period; a `refunds` link follows the separately decided refund-period rule below. Neither relationship changes the preserved source amount.

| Fixture ID | Scenario and synthetic evidence | Source event / relationship | Net spend | Liability delta / review |
|---|---|---|---|---|
| `cc_domestic_purchase_01` | `XBANK: INR 1,250 spent at SAMPLE MART on card XX1234.` | Settled card debit. | +₹1,250 at transaction date. | +₹1,250; review if source ownership or identity is uncertain. |
| `cc_online_purchase_01` | `XBANK: INR 799 charged online at SHOP.EXAMPLE on XX1234.` | Settled debit; online label is evidence, not instrument proof. | +₹799. | +₹799; review ambiguous source. |
| `cc_rupay_upi_01` | `XBANK: INR 300 paid by UPI using credit card XX1234 to SAMPLE SHOP.` | One card-funded debit only when card funding is explicit. | +₹300 once. | +₹300; review if bank debit may be a second representation. |
| `cc_auth_hold_01`, `cc_settlement_01` | `XBANK: INR 2,000 authorized at HOTEL on XX1234.` then `XBANK: INR 1,850 spent at HOTEL on XX1234.` | Pending hold linked to later settled debit with `settles`; retain both rows. | Hold 0; settlement +₹1,850. | Hold provisional; settlement +₹1,850. Review nonunique/materially different match. |
| `cc_declined_01` | `XBANK: INR 400 transaction declined on card XX1234.` | Failed row if parsed; no purchase event. | 0. | 0; review only if incorrectly emitted as settled debit. |
| `cc_reversal_01` | Settled ₹600 purchase; `XBANK: INR 600 purchase reversed on card XX1234.` | Credit event linked with `reverses` to the original charge. | Purchase period: +₹600 −₹600 = ₹0. | Charge +₹600, reversal −₹600. Review multiple possible originals. |
| `cc_merchant_emi_01` | `XBANK: SAMPLE SHOP purchase INR 12,000 converted to 6 EMIs; fee INR 99 + GST INR 18.` | Purchase plus explicitly stated fee/tax; no fabricated future installments. | Purchase +₹12,000; charges +₹117 when charged. | Liability follows posted charge/fee events; review unclear split or terms. |
| `cc_post_purchase_emi_01` | `XBANK: INR 10,000 on XX1234 converted to 6 monthly instalments.` | Conversion notice may have a linked conversion-credit representation; classify that as EMI conversion credit, never `refunds`. | No second purchase and no spend reduction from conversion credit. | Conversion itself delta 0; installment posting moves principal between unbilled and billed, not total liability. Review uncertain original. |
| `cc_emi_installment_01` | `XBANK: EMI principal INR 1,650; interest INR 120; processing fee INR 50; GST INR 30.` | Explicit principal/interest/fee/tax components only. | Principal 0 incremental; charges +₹200 when charged. | Principal is not a second liability charge; interest/fee/tax +₹200. Review inseparable aggregate. |
| `cc_statement_total_due_01` | `XBANK: Statement XX1234 total due INR 5,400; minimum due INR 540; due 20-Oct-26.` | Snapshot evidence, not a transaction. | 0. | Snapshot only; review conflicting cycle evidence. |
| `cc_payment_netbanking_full_01` | Bank debit ₹5,400 and `XBANK: Payment received INR 5,400 towards XX1234.` | Payment receipt plus bank leg; one allocation to card liability. | 0. | Liability −₹5,400 once; review unknown target/mismatch. |
| `cc_payment_upi_full_01` | `XBANK: UPI INR 5,400 paid to XBANK CARD XX1234.` | Bank debit allocated only with explicit or confirmed target. | 0. | Liability −₹5,400 once. |
| `cc_payment_autopay_01` | `XBANK: Autopay INR 5,400 debited for card XX1234.` | Successful settled debit; a card receipt, if present, represents the same payment event. | 0. | Liability −₹5,400 once, never once for debit and again for confirmation. |
| `cc_payment_minimum_01` | `XBANK: INR 540 received towards card XX1234; minimum due INR 540.` | Allocate only confirmed ₹540 payment, not the reminder amount. | 0. | Liability −₹540; review payment-versus-reminder ambiguity. |
| `cc_payment_partial_01` | `XBANK: INR 2,000 received towards XX1234; total due INR 5,400.` | Partial payment allocation. | 0. | −₹2,000; remaining due ₹3,400 before other events. |
| `cc_payment_over_01` | `XBANK: INR 6,000 received towards XX1234; total due INR 5,400.` | Full evidenced payment, not capped to due. | 0. | −₹6,000; resulting credit balance display needs owner decision. |
| `cc_payment_bounce_01` | ₹540 payment then `XBANK: INR 540 payment returned for XX1234.` | Payment receipt and return; return reverses the payment event. | 0. | −₹540 then +₹540, net zero; separately evidenced bounce fee is a charge. |
| `cc_wallet_load_01` | `XBANK: INR 1,000 loaded to WALLET using XX1234.` | Card-funded wallet load; wallet receipt is counterpart only if confirmed same owned wallet. | +₹1,000 once if charged. | +₹1,000; review merchant purchase vs own-wallet transfer. |
| `cc_cash_advance_01` | `XBANK: INR 5,000 cash advance transferred to bank account XX1234.` | Cash advance is its own liability event; bank receipt is not another card purchase. | Owner decision: propose 0 categorized spend by default. | +₹5,000 liability; review if cash-advance instrument/settlement is unclear. |
| `cc_atm_cash_withdrawal_01` | `XBANK: INR 2,000 cash withdrawal at ATM on card XX1234.` | ATM cash withdrawal is cash advance if issuer evidence confirms credit-card funding. | Owner decision: propose 0 categorized spend by default. | +₹2,000 liability; separately posted interest/fee is a card charge. Review debit/credit-card ambiguity. |
| `cc_xpayapp_payment_01` | `XBANK: INR 1,200 debited for XPAYAPP card bill XX1234.` | Third-party app bank debit names `XPAYAPP`; match to card only by explicit card/reference evidence or user confirmation. | 0 if confirmed own-card bill payment. | Liability −₹1,200 once; otherwise leave unresolved, never infer from app name. |
| `cc_convenience_fee_01`, `cc_merchant_surcharge_01` | `XBANK: SAMPLE SHOP card charge INR 1,000; convenience fee INR 20.` / `XBANK: SAMPLE SHOP surcharge INR 15 on card XX1234.` | Separate actual purchase and fee/surcharge when separately evidenced. | Purchase +₹1,000; fee +₹20 / surcharge +₹15 as `Card charges` if owner approves category. | Liability equals posted components. Review aggregate amount that cannot be split. |
| `cc_rewards_statement_credit_01` | `XBANK: INR 100 reward points redeemed as statement credit to XX1234.` | Posted statement credit; not purchase refund absent an explicit purchase link. | Owner decision: propose excluded from net spend by default. | Liability −₹100 once. Review if credit versus voucher is unclear. |
| `cc_rewards_voucher_01` | `XBANK: 1,000 reward points redeemed for SAMPLE MART voucher.` | Voucher redemption, no card cash credit. | 0. | Liability 0; review value/transaction claim if only points are stated. |
| `cc_bnpl_instalment_01` | `XPAYLATER: INR 900 instalment due for order SAMPLE MART; source XX1234 not present.` | BNPL/provider liability; no card event unless card funding is evidenced. | Count the evidenced underlying purchase once under its actual instrument; installment repayment 0 incremental. | No credit-card liability absent card evidence. Review instrument ambiguity; no card identity inferred from merchant/order. |
| `cc_refund_full_01` | ₹1,200 purchase; `XBANK: INR 1,200 refunded by SAMPLE SHOP to XX1234.` | Credit linked with `refunds`. | Net zero under chosen refund-period view; purchase-date and posting-date views remain distinguishable. | Liability −₹1,200 when posted. |
| `cc_refund_partial_01` | ₹1,200 purchase and ₹300 refund. | Partial `refunds` allocation; cannot exceed purchase. | Net ₹900 under chosen refund-period view. | Liability −₹300 when posted. |
| `cc_refund_after_statement_01` | Statement due ₹1,200; ₹300 refund posts next cycle. | Refund linked to prior purchase; snapshot retained. | Proposed default: net purchase period, with posting-period view also available; owner decision required. | Liability −₹300 when posted; earlier snapshot immutable. |
| `cc_cashback_posted_01`, `cc_cashback_future_01` | Posted ₹100 card credit / `XBANK: INR 100 cashback will be credited to XX1234.` | Posted cashback is a cashback credit; future promise is not a settled event. | Owner decision: propose neither reduces spend unless explicitly linked and approved. | Posted −₹100 liability; future 0. Review reward/refund ambiguity. |
| `cc_forex_usd_01`, `cc_forex_markup_inr_01` | `XBANK: USD 12 spent at SAMPLE STORE on XX1234; forex markup INR 24.` | USD purchase and INR charge are separate currency events. | USD 12 in USD bucket; INR 24 in INR spend bucket if categorized as card charge. | Separate liability currency buckets; no invented FX. Review missing code/amount. |
| `cc_annual_fee_gst_01`, `cc_interest_late_fee_01` | Annual fee ₹500 + GST ₹90; separately evidenced interest/late fee. | Posted fee, interest, finance charge and GST events. | Actual charges count as spend under proposed `Card charges`. | Liability increases by posted amounts; review unsplit statement summary. |
| `cc_fee_reversal_01` | ₹500 fee followed by `XBANK: INR 500 annual fee reversed.` | Credit linked with `reverses` to fee. | Fee period nets to zero, distinct from ordinary refund period attribution. | Fee +₹500 then reversal −₹500. |
| `cc_duplicate_network_merchant_01` | Issuer, network and merchant messages represent one ₹800 purchase. | Keep rows; `echo` only when identity/reference evidence proves same event. | +₹800 once. | Liability +₹800 once; review conflict or multiple candidates. |
| `cc_statement_line_match_01` | Synthetic statement line ₹800 matches existing SMS purchase. | Imported evidence links to existing row; no second transaction. | Remains +₹800. | No extra liability; review ambiguous reference/date/amount. |
| `cc_replacement_card_01` | `XBANK: replacement card issued ending XX9876.` | New source identity linked only with explicit continuity evidence/confirmation. | 0. | No delta; review last-four collision or uncertain account. |
| `cc_addon_card_01` | Primary XX1234 and add-on XX5678. | Preserve per-card source identity; liability grouping requires issuer evidence/confirmation. | Each purchase once. | Grouping decision unresolved until owner/issuer semantics are known. |
| `cc_seq1_refund_350_01` | Sequence-only ₹350 refund for the ₹1,850 hotel settlement. | Linked `refunds` credit. | Sequence 1 purchase-period net spend ₹1,500. | Liability −₹350 once. |
| `cc_seq2_purchase_01`, `cc_seq2_payment_01`, `cc_seq2_statement_01` | ₹1,200 purchase, ₹1,200 full payment with bank debit/card confirmation, and ₹1,200 statement snapshot. | Sequence-specific source rows. | ₹1,200 purchase-period spend. | +₹1,200 −₹1,200 = zero liability; snapshot remains ₹1,200. |
| `cc_seq3_purchase_01`, `cc_seq3_payment_01`, `cc_seq3_refund_01`, `cc_seq3_statement_01` | ₹1,200 purchase and snapshot; ₹300 payment; ₹200 refund. | Sequence-specific source rows with one payment allocation and one `refunds` link. | ₹1,000 net spend. | +₹1,200 −₹300 −₹200 = ₹700 liability; snapshot remains ₹1,200. |
| `cc_seq4_purchase_a_01`, `cc_seq4_purchase_b_01`, `cc_seq4_echo_01` | Two different ₹800 purchases and one issuer/network representation of purchase A. | Two canonical purchases plus one confirmed echo. | ₹1,600 total. | Liability +₹1,600; echo adds zero. |
| `cc_seq6_payment_01`, `cc_seq6_return_01` | ₹540 payment then ₹540 payment return. | Payment receipt and linked payment return. | 0. | −₹540 +₹540 = zero net liability reduction. |

## Liability event classes

Every accepted source event contributes exactly one canonical liability delta. A source observation may be suppressed as an echo of the canonical event, but may never create an additional delta. Links classify the event; they do not create a second application of its amount.

| Canonical event class | Delta to card liability | Source/link rule |
|---|---:|---|
| Purchase charge | `+amount` | Settled purchase once; authorization hold is provisional and contributes zero. |
| Fee/interest charge | `+amount` (`−amount` for a linked reversal) | Posted fee, interest, finance charge, GST, convenience fee or surcharge; only explicit actual charges. A fee reversal stays in this class and reverses that charge once. |
| Payment receipt | `−amount` | Apply one payment allocation. When `repays`/allocation exists, exclude the paired card confirmation and bank debit from generic posted-credit application. |
| Payment return | `+amount` | Reopen liability once for returned payment. Once linked as return/reversal, exclude the return row from generic posted credits. |
| Purchase reversal | `−amount` | Reverse linked purchase charge once. Once `reverses` link exists, exclude reversal credit from generic posted credits. |
| Refund credit | `−amount` | Posted credit linked with `refunds`; once linked, exclude from generic posted credits and net spend only under refund-period rule. |
| Cashback credit | `−amount` | Posted card credit reduces liability once; never a refund without an explicit refund link. Exclude from generic posted credits after classifying it. |
| Rewards statement credit | `−amount` | Points redeemed as a posted card credit; not a refund without an explicit purchase link; excluded from net spend by default pending owner decision. A voucher redemption is not a card credit and has no liability delta. Exclude from generic posted credits after classifying it. |
| EMI conversion credit | `0` total-liability delta | Explicit conversion representation linked to original purchase; never generic credit or refund. Instalment posting transfers principal between unbilled/billed views, not total liability. |
| Cash advance | `+amount` | Cash advance/confirmed credit-card ATM withdrawal raises liability once. Proposed default net-spend category effect is zero, pending owner decision. |

Generic posted credits apply only to settled credit rows that have no canonical class/link/allocation. Once a payment allocation, return/reversal link, refund link, cashback or rewards-credit classification or EMI-conversion link exists, that source credit is excluded from generic posted credits. For a payment represented by both bank debit and card confirmation, the accepted payment event is allocated once; the confirmation is an echo/evidence row and cannot reduce liability again. Reconciliation must be idempotent and enforce one event-to-delta assignment.

Worked checks: sequence 2 is purchase `+₹1,200` and payment `−₹1,200` = zero remaining liability; the card confirmation is excluded after allocation. Sequence 3 is purchase `+₹1,200`, payment `−₹300`, refund `−₹200` = ₹700 liability; payment and refund each apply once. Sequence 6 is payment `−₹540`, return `+₹540` = zero net reduction; the return is excluded from generic credits after its return link.

## Proposed accounting model

### Net-spend, period and liability rules

- **Purchase reversal:** a linked `reverses` credit nets the original purchase spend in the original purchase period, including when the reversal posts later. Assert sequence 1 and `cc_reversal_01` net to zero for a fully reversed purchase. Unlinked credits do not alter spend.
- **Refund:** a linked `refunds` credit is distinct from a reversal. It reduces the linked purchase under a separately selected refund-period policy. Proposed default is purchase-period net spend plus a visible posting-period view; owner approval is required. Assert full/partial and late-refund behavior using `cc_refund_*` fixtures.
- **Fees and other charges:** actual fees/interest/GST count in the period they post under proposed `Card charges`; period/category contract requires owner approval. Fee reversals net the charge in its original period.
- **Cash advances/ATM:** proposed default is not categorized spend, but increases liability. Any posted interest/fee is a `Fee/interest charge`. Owner decision required.
- **Outstanding:** derive from canonical liability deltas by currency; payment, reversal and linked refund cannot be applied twice. Statement snapshots reconcile but do not overwrite history. Available credit is unknown without explicit matching-currency limit evidence.
- **Currency:** retain source currency; no FX invention or cross-currency sums, per [ADR 0017](../decisions/0017-source-currency-fidelity.md).
- **Eligibility:** preserve the current settled/nonduplicate/nonexcluded/nontransfer base in [`FinancialEligibility`](../../lib/data/analytics/financial_eligibility.dart), then apply one link-aware net-spend projection consistently across dashboard, budgets, trends, queries and forecasts.
- **Period fields:** keep transaction date, SMS receive time, statement date and due date distinct. Payment month does not replace purchase period.

### Source, schema, review and restore boundaries

Preserve source rows and their amount, currency, merchant span, account hint, identity and timestamps. Corrections, classification, dedup, transfers, refunds and allocations remain separate audited decisions or links under [ADR 0011](../decisions/0011-evidence-backed-assistance.md). Reuse existing link kinds only when endpoints and meanings fit. Card-level/split allocation or statement-to-transaction relationships require explicitly typed additive relations; never encode a card ID as a transaction FK.

No schema is approved by this plan or [ADR 0020](../decisions/0020-credit-card-accounting.md). Candidates include nullable payment-source instrument type, immutable statement snapshots and typed allocation rows only where current links are insufficient. Any accepted schema change requires additive migration, old-archive compatibility, generated schema, reset/delete, backup/restore, foreign-key, and undo coverage. Follow [ADR 0016](../decisions/0016-backup-domain-state-and-restore-order.md) ordering and [ADR 0008](../decisions/0008-bounded-encrypted-backups.md) retention; new tables must not retain message bodies.

Every user decision needs preview where it changes historical inclusion and durable undo. Undo removes/reverses the selected relationship or decision, rebuilds projections and keeps source rows. Card-payment work may reuse `reconcileOwnedTransfers` after T-165b; T-165b does not allocate payments to a card liability.

For explanations and review, show evidence and the accounting effect in plain language. Start with single-item review. Bulk action remains behind a full affected-row/count/amount preview and one durable grouped undo, and cannot close [PV-04](../tasks/T-172.md).

## Gap map

| Gap | Owner | Required work |
|---|---|---|
| Inferred source identity/ownership; audit must remain read-only | T-190a1/a2 | Audit report only in a1. Put instrument/ownership mutation in a2 with affected-row/totals preview and durable undo. |
| Reconciliation leaves stale `transfer_leg` links | T-190b1 | Closed by T-165b; evidence is recorded in [T-165b](../tasks/T-165b.md). |
| Card payment allocation and confirmation double-application | T-190b2 | Apply one canonical payment event; exclude allocated confirmation/debit from generic credits. |
| Lifecycle/correlation rows and liability classes | T-190c | Persist verified auth/settle/reversal relations and one liability delta per event. |
| Refund/reversal period semantics and T-100 overlap | T-190d | Reuse T-100; reversal nets original period, refund follows owner-selected policy. |
| Card charge, EMI and conversion-credit cases | T-190e1/e2 | Separate actual charge events from conversion credits and principal movements. |
| Statement snapshots and derived balance | T-190f1/f2 | Separate snapshot persistence from liability projection/available-credit view. |
| Review explanations and durable undo | T-190g1/g2 | Single-item review first; grouped action only with preview and full undo. |
| Statement import overlap with T-102 | T-190h1/h2 | Reuse shared importer and add card mapping only after T-102 contract passes. |

These proposals do not close T-100, T-101, T-102, PV-04 or T-164c/d, nor any device gate.

## Fixture layout and sequences

Fixture IDs and expected case behavior live only in the [scenario map](#scenario-map); no fixture IDs are defined outside that map. Put parser fixtures in `test/fixtures/sms/credit_card/cc_<case>_<nn>.txt` and matching `.expected.json`, following [`test/fixtures/sms/README.md`](../../test/fixtures/sms/README.md). Use `XBANK`, `XNET`, `XSHOP`, `XPAYAPP`, `XPAYLATER`, `XX1234`, round amounts and fabricated references only. Sequence definitions reference scenario-map fixture IDs and do not repeat case definitions.

| Sequence | Ordered fixture IDs | Required aggregate assertion |
|---|---|---|
| 1 | `cc_auth_hold_01` → `cc_settlement_01` → `cc_seq1_refund_350_01` | Hold 0; settlement ₹1,850; linked refund ₹350; net spend/liability change ₹1,500. |
| 2 | `cc_seq2_purchase_01` → `cc_seq2_statement_01` → `cc_seq2_payment_01` | Spend remains ₹1,200 in purchase period; liability returns to zero; dated snapshot remains ₹1,200; confirmation/debit cannot repay twice. |
| 3 | `cc_seq3_purchase_01` → `cc_seq3_statement_01` → `cc_seq3_payment_01` → `cc_seq3_refund_01` | Net spend ₹1,000; liability ₹700; prior snapshot remains ₹1,200. Payment and refund each apply once. |
| 4 | `cc_seq4_purchase_a_01` + `cc_seq4_purchase_b_01` + `cc_seq4_echo_01` | Spend ₹1,600 total; only representations of the same purchase echo. |
| 5 | `cc_forex_usd_01` + `cc_forex_markup_inr_01` | USD 12 remains in USD bucket; only ₹24 contributes to INR spend/liability; no FX rate. |
| 6 | `cc_statement_total_due_01` → `cc_seq6_payment_01` → `cc_seq6_return_01` | Statement total ₹5,400/minimum ₹540; liability reduction nets to zero; spend unchanged; return is not also a generic credit. |

## Owner decisions

1. Refund-period default: purchase date, posting date, or both views with one default.
   - Owner answer (2026-10-10): refunds normally arrive 3–5 business days
     after the purchase. Any refund-matching date-range restriction must be
     generous: allow up to 31 days between purchase and refund credit. The
     attribution default (purchase vs posting period) is still to be
     confirmed; the short typical lag favours the proposed purchase-period
     default with a visible posting-period view.
2. Dedicated `Card charges` spending category and its period attribution (proposed posting period).
3. Cash advance/ATM withdrawal spend treatment (proposed no categorized spend; liability still increases).
4. Rewards redemption: statement credit versus voucher and whether/when a posted credit affects net spend (proposed no spend reduction absent explicit purchase link).
5. Cashback treatment, distinct from reward-point redemption.
6. Overpayment display: negative liability/card credit or floor displayed liability at zero.
7. Statement-cycle totals as secondary view alongside transaction-date default.
8. Add-on cards: separate liabilities or shared issuer-confirmed liability group.
9. EMI presentation when issuer gives only a combined installment amount.

Keep unresolved semantics visible in later phases until the owner decides. T-190a1 is a read-only audit and needs no product decision.
