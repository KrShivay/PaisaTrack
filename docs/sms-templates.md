# SMS Templates

## Implemented registries

Bundled deterministic templates currently include SBI, Axis, Central Bank,
Kotak, HDFC, ICICI, IndusInd, and Paytm sender families. HDFC and ICICI have
sanitized fixture coverage under `test/fixtures/sms/hdfcbk/` and
`test/fixtures/sms/icicib/`.

Sender recognition is still incomplete: Android filters unknown senders before
Dart sees them, and no release-safe unknown-sender counter exists yet. T-108's
remaining scope is diagnostics and additional evidence-backed bank coverage,
not the already-landed HDFC/ICICI templates.

Templates live in `assets/templates/*.json`. Do not invent formats; add only
sanitized, real fixture-backed variants (`test/fixtures/sms/<bank>/`).

## Provenance and confidence (ADR 0005)

Both a template entry and its fixture expected JSON may include
`"provenance": "public"`. Public (silver-tier) templates are capped at 0.85
confidence, below the 0.9 silent-auto threshold, until the trust ledger promotes
them from confirmation evidence. Omit the field for device (gold-tier) fixtures;
that is the backward-compatible default and retains the 0.97 template
confidence. Never label an invented or unsourced fixture as either tier.

## Kotak Mahindra Bank (`assets/templates/kotak.json`)

Sender patterns cover DLT `KOTAKB`/`KOTAKD` IDs and Kotak's RCS display
name. The public fixtures are sourced from the PennyWiseAI Kotak parser corpus
and a public SMS classification dataset; every fixture records its immutable
source URL.

- `kotak_upi_sent_bank_ac_v1` / `kotak_upi_received_bank_ac_v1` — Kotak
  account UPI sends and receipts with VPA, date, and UPI reference.
- `kotak_upi_sent_short_v1` — newer short/RCS UPI alerts with a named payee.
- `kotak_imps_received_v1` — IMPS receipt linked to a masked mobile.
- `kotak_account_debit_v1` — account debit with available balance.
- `kotak_card_spent_v1` — credit-card spend with merchant and available limit.
- OTP and insufficient-limit notices are pinned as negative fixtures.

All templates have public provenance and therefore remain capped at 0.85 until
device confirmations promote them through the trust ledger.

## Central Bank of India (`assets/templates/centbk.json`)

Sender pattern: `^[A-Z]{2}-?CENTBK(?:-[A-Z])?$`. Fixtures come from two public
SMS datasets and retain a source URL in each expected JSON file.

- `centbk_dbt_credit_v1` — dated DBT/DBTL credit notice.
- `centbk_account_credit_v1` / `centbk_account_debit_v1` — compact CBoI
  account alert with transaction amount, total balance, and clear balance.
- KYC completion is a same-sender negative fixture.

All Central Bank templates carry public provenance and the 0.85 confidence cap.

## IndusInd Bank (`assets/templates/indusind.json`)

Sender pattern: `^[A-Z]{2}-INDUSB(-[A-Z])?$`

- `indusind_upi_debit_v1` — `A/c *XX{account} debited by Rs.{amount} towards {vpa}. RRN {ref}.` (optional `Avl Bal`).
- `indusind_upi_credit_v1` — `A/c *XX{account} credited by Rs.{amount} from/for {vpa}. RRN {ref}.`
- `indusind_upi_autopay_debit_v1` — AutoPay mandate debit, `... towards {vpa} UPI AutoPay, UMN {ref}@upi`.
- `indusind_vpa_debit_v1` / `indusind_vpa_credit_v1` — `VPA "{selfvpa}" linked to A/C No."XXXX{account}" is Dr/Cr with INR.{amount} by VPA "{vpa}", Ref {ref}`.
- `indusind_ach_debit_v1` — netbanking/ACH debit, `IndusInd A/C **{account} Debited; INR {amount} Ref-{ref}.Bal INR {balance}`.
- `indusind_neft_credit_v1` — NEFT credit (salary, MF redemptions, penny-drops), `Your IndusInd Account XXXXXXXX{account} has been credited for INR {amount} towards N/{ref}/{ifsc}/{merchant} . Call ...`. `{merchant}` captures the remitter segment (e.g. `SAL JUN 26 RAPIPAY`) so seed categorization sees it; `{ref}` is the bare NEFT ref token (statement-desc containment). No balance in this shape; ts falls back to receive time. Fixtures: `indusb_neft_01..06`.
- `indusind_ach_credit_v1` — netbanking/ACH credit (dividends), mirror of the debit shape: `IndusInd A/C **{account} Credited; INR {amount} Ref-{ref}.Bal INR {balance}`. `{ref}` keeps the full `ACH CR INW PAY/...` string. Fixtures: `indusb_achcr_01..07`.
- Known gap: IMPS/P2A credits (`Your account XXXXXXX{account} is credited by Rs.{amount} on {date} received from account .../... (IMPS Ref no. {ref})`) — only 3 real occurrences in the full SMS history, below the ≥5 fixture-first bar; committed as negative fixtures `indusb_imps_p2a_gap_01..03` instead of templated.
- Known gap: quarterly SB interest credits generate **no SMS** since 2023 (statement `Int.Pd` rows are statement-only); the last-seen 2023 legacy wording is pinned as negative fixture `indusb_interest_legacy_gap_01`. Also observed: one dividend (2026-04-21 VARUN, ₹5.50) produced no SMS while 7 comparable ones did — small ACH credits are not reliably notified.

## State Bank of India (`assets/templates/sbi.json`)

Sender pattern: `^[A-Z]{2}-SBIUPI(-[A-Z])?$`; dates use `ddMMMyy` (e.g. `08Oct23`).

- `sbi_upi_debit_v1` — `Rs{amount} debited@SBI UPI frm A/cX{account} on {date} RefNo {ref}.`
- `sbi_upi_debit_named_v1` — `A/c X{account}-debited by Rs{amount} on {date} transfer to {merchant} Ref No {ref}.`
- `sbi_upi_debit_dearupi_v1` — `Dear UPI user A/C X{account} debited by {amount} on date {date} trf to {merchant} Refno {ref}.`
- Known gap: real "credited ... against reversal of txn" messages seen only twice — insufficient volume for a template; committed as negative fixtures instead of fabricated.

## Paytm Payments Bank (`assets/templates/paytmb.json`)

Sender pattern: `^[A-Z]{2}-PAYTMB(-[A-Z])?$`; masked account is always `91XX{account}`.

- `paytmb_p2p_paid_v1` — `You have paid Rs.{amount} via a/c 91XX{account} to {merchant} on {date}. Ref:{ref}. ...` (`dd-MM-yyyy`).
- `paytmb_paid_merchant_v1` — `Paid Rs.{amount} via a/c 91XX{account} [to] {merchant} on {date}. Ref No: {ref} Check payment history ...` (`dd-MM-yyyy`).
- `paytmb_credit_received_v1` — `Rs.{amount} received from {merchant} in [your Paytm Payments Bank|PPBL] a/c 91XX{account}. UPI Ref: {ref} ...` (no date group; falls back to received timestamp).
- Known gap: single real "Automatic payment of Rs.X done to ..." occurrence — folded into negatives, not templated.
- Normalizer trap covered by negative fixtures: "Rs.X is added back to your Paytm Payments bank a/c ... has failed" (a failed refund, not a credit) and future-tense autopay/money-request messages.

## Axis Bank (`assets/templates/axisbk.json`)

Sender pattern matches `AXISBK`/`AxisBk`/`AxisBK` senders with optional 2-letter
prefix and `-S` suffix; dates use `dd-MM-yy`.

- `axisbk_card_spent_v1` — multiline: `Spent {USD|INR} {amount}\nAxis Bank Card no. XX{account}\n{date} {time} IST\n{merchant}\nAvl Limit: INR {limit}\n...`.
- `axisbk_card_payment_received_v1` — `Payment of INR {amount} has been received towards your Axis Bank Credit Card XX{account} on {date} - Axis Bank`.
- Normalizer trap covered by negative fixtures: declined-transaction notices, bill-due reminders, statement-generated notices, and "cashback ... will be credited in your next statement" (future credit, not an actual transaction).
