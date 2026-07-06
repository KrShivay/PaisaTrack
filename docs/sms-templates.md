# SMS Templates

Templates live in `assets/templates/*.json`. Do not invent formats; add only
sanitized, real fixture-backed variants (`test/fixtures/sms/<bank>/`).

## IndusInd Bank (`assets/templates/indusind.json`)

Sender pattern: `^[A-Z]{2}-INDUSB(-[A-Z])?$`

- `indusind_upi_debit_v1` — `A/c *XX{account} debited by Rs.{amount} towards {vpa}. RRN {ref}.` (optional `Avl Bal`).
- `indusind_upi_credit_v1` — `A/c *XX{account} credited by Rs.{amount} from/for {vpa}. RRN {ref}.`
- `indusind_upi_autopay_debit_v1` — AutoPay mandate debit, `... towards {vpa} UPI AutoPay, UMN {ref}@upi`.
- `indusind_vpa_debit_v1` / `indusind_vpa_credit_v1` — `VPA "{selfvpa}" linked to A/C No."XXXX{account}" is Dr/Cr with INR.{amount} by VPA "{vpa}", Ref {ref}`.
- `indusind_ach_debit_v1` — netbanking/ACH debit, `IndusInd A/C **{account} Debited; INR {amount} Ref-{ref}.Bal INR {balance}`.

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
