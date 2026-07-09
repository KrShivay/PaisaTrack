# Generic Fallback Parser — Spec (T-066)

Status: review-ready spec, 2026-07-10, @claude. Implements the second stage of
`ParserCascade` anticipated since Phase 0 ("Later phases can add … fallbacks
while preserving this single parse contract").

## Motivation

Field report (2026-07-10): users with Kotak and Central Bank accounts get zero
parsed transactions. `SmsFilter` allowlists `KOTAKB`/`CENTBK`, so their SMS are
captured and visible on the dev Unparsed screen — but the cascade is
templates-or-`Err` and only axisbk/sbi/indusind/paytmb template packs exist.
Every untemplated bank currently yields 0% parses. Templates fix known banks;
this parser bounds the damage for *every* bank we allowlist but haven't
templated, and cushions template drift when a bank rewords its SMS.

## Position in the cascade

```
ParserCascade.parse(sms):
  1. TemplateMatcher.match(sms)        → hit: return (confidence 0.97, src per template)
  2. GenericTransactionParser.parse(sms) → hit: return (confidence <=0.6, src 'generic')
  3. Err(ParseFailure.unparsed)
```

Templates always win. The generic parser never runs when a template matched,
and its output is distinguishable downstream via `confidence_json.parser =
{c: <=0.6, src: 'generic'}`.

## Extraction layers (all must operate on the raw body; never log it)

1. **Direction**: first match wins, debit keywords checked before credit
   (bodies like "credited to beneficiary … debited from a/c" exist).
   Debit: `debited`, `spent`, `withdrawn`, `paid`, `sent`, `purchase of`,
   `txn of .* at` . Credit: `credited`, `received`, `deposited`, `refund`,
   `reversal`. No direction keyword → no parse.
2. **Amount**: reuse `FieldNormalizer.parseAmount` over the first currency
   token: `(?:INR|Rs\.?|₹)\s*([\d,]+(?:\.\d{1,2})?)`. Indian grouping already
   handled. No amount → no parse. Multiple amounts: take the one nearest the
   direction keyword; the trailing `Avl Bal/Bal:` amount is the balance
   candidate, never the transaction amount.
3. **Account hint**: `(?:a/c|A/C|ac|acct|account)\s*(?:no\.?\s*)?[Xx*]*(\d{3,6})`
   → last-4 form, matching template conventions.
4. **Channel**: keyword map — `UPI`→upi, `IMPS`/`NEFT`/`RTGS`→netbanking,
   `ATM`/`cash`→atm, `POS`/`card`→card; default null.
5. **Counterparty VPA**: `([a-zA-Z0-9._-]+@[a-zA-Z]{2,})` (existing template
   VPA convention); merchant text: token sequence after `at|to|from|towards`
   up to a delimiter (`on`, `.`, `,`, `Ref`), max ~40 chars, trimmed. Low
   confidence in this field is acceptable — merchant enrichment is Phase 3's
   job; when unsure emit null (do not guess aggressively).
6. **Balance**: `(?:Avl(?:\.|bl)?\s*Bal|Balance|Bal)[:\s]*(?:INR|Rs\.?|₹)?\s*([\d,]+(?:\.\d{1,2})?)`
   → `balance_after`, optional.
7. **Ref id**: `(?:Ref(?:\s*No)?|UTR|txn(?:\s*id)?)[:\s#]*([A-Za-z0-9]{6,})`,
   optional.

## False-positive guard (the conjunction)

Parse succeeds only when **direction AND amount AND at least one of
{account hint, channel keyword, VPA}** are present. Rationale: promos and
reminders that slip past `SmsFilter` ("Get Rs.500 cashback!") rarely carry an
account/channel/VPA context signal next to a direction keyword. Additional
hard rejects, checked first (mirrors `SmsFilter` markers, defense in depth):
OTP markers, `will be debited` / `is due` / `due on` (future events, per the
existing declined/future-event fixture law), `requested` (collect requests),
`declined|failed|unsuccessful`.

## Confidence and downstream behavior

`c = 0.6` when all of direction+amount+account/channel present and exactly one
amount token; drop to `0.5` when the amount was disambiguated from multiple
candidates or merchant text is empty. Never exceed 0.6: `DecisionPolicy`'s
ask band is 0.6–0.9 and auto needs >=0.9, so a generic parse can never
silently auto-label — worst case it asks (within budget) or lands
needs_review. This is the safety property; a test must assert it.

## Non-goals

- No per-bank logic (that's what template packs are for — T-067).
- No category inference, no merchant canonicalization (Phase 3).
- No parsing of statement/bill-due/limit notifications (guard rejects).

## Test plan

- Positive: every existing positive fixture (4 banks) parsed with
  `TemplateMatcher` disabled — assert >=80% produce a record whose amount,
  direction, and account hint match the expected JSON (channel/merchant may be
  weaker; assert no *contradictions*, i.e. never a wrong amount or flipped
  direction — wrong-but-present is a bug, absent is acceptable).
- Negative: every existing negative fixture (OTP, promo, declined, future
  autopay, bill-due, statement, KYC) still returns `Err(unparsed)`. Zero
  tolerance here.
- Safety property: a generic parse fed through `DecisionPolicy` never returns
  `auto` (table-driven over the confidence range).
- Cascade precedence: an SMS matching both a template and the generic parser
  returns the template result.
- Once T-065 fixtures land: Kotak + Central positives parse amount+direction
  correctly (they are also T-067's template fixtures — the generic parser
  should already catch most before templates exist; record the actual catch
  rate in the T-066 WORKLOG entry).
