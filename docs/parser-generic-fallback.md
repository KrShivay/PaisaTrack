# Generic Transaction Parser Contract

The generic parser is the conservative fallback after bank templates and before
the optional local-LLM extractor.

## Acceptance gates

A message can become a transaction only when it has:

- an unambiguous debit or credit signal;
- a usable INR amount associated with the transaction;
- transactional context such as account/card hint, UPI/VPA, channel, reference,
  or counterparty; and
- no OTP, promotion, failure, decline, balance-only, reminder, or future-event
  signal.

## Extraction

- Amount selection prefers currency-adjacent transaction amounts and rejects
  balance-only values.
- Direction wording is explicit; unclear messages are rejected.
- Timestamp defaults to the SMS received time unless a valid transaction time
  is present.
- Merchant/counterparty extraction is best-effort and never increases parse
  confidence beyond the fallback cap.
- Account hints remain masked source evidence.

Generic output is capped below silent-accept confidence and therefore enters
review. Templates retain precedence. A parser rejection leaves the source SMS
available for local triage; it does not fabricate a partial transaction.

## Upcoming-payment messages

Bill-due, scheduled-autopay, mandate, and renewal reminders must continue to be
rejected as settled transactions. The recurring-calendar feature may consume
them through a separate expected-event parser and later match the actual debit.

## Required tests

- debit and credit wording variants;
- Indian amount formats and multiple-amount messages;
- balance, OTP, promotion, failure, and future-event rejection;
- template precedence;
- confidence never producing an automatic decision;
- parse and rejection reason remaining mutually exclusive.
