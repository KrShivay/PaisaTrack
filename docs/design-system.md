# Design System

This document contains the product rules needed for future UI work.

## Principles

- Calm, private, and trustworthy; spending is information, not an alarm.
- Numbers first, explanations second, controls last.
- One primary action and at most one accent emphasis per screen.
- Original financial evidence remains discoverable without dominating the UI.
- Dark and light themes are equal requirements.

## Foundations

- Use existing `PaisaColors`, `AppSpacing`, typography, category visuals, and
  `formatInr()` helpers.
- Financial figures use tabular numerals and Indian digit grouping.
- Debit/credit color is reserved for amounts and net-flow meaning.
- Transfers and excluded sources use neutral treatment.
- Minimum touch target: 48×48 logical pixels.
- Avoid introducing a chart dependency for simple bars or sparklines.

## Standard states

Every screen must define loading, empty, normal, error, and narrow/large-text
states. Destructive actions require confirmation and a clear consequence.
Swipe and long-press interactions must have visible alternatives.

## Future feature UX

### Payee labels

- Show the user label first and original VPA/merchant evidence second.
- Label/merge flows preview affected transactions and clearly separate rename
  from identity merge.
- Ambiguous identities require explicit selection.

### Accounts and payment sources

- Display nickname plus masked identifier; never show full account numbers.
- Inclusion/exclusion from analytics must be visible and explainable.
- Owned-account transfers receive neutral styling.

### Statement import

- Use a staged flow: choose file → select mapping/account → preview → import →
  reconciliation summary.
- Never write ambiguous rows silently.

### Refunds and reimbursements

- Show the original expense and linked repayments together.
- Present gross, repaid, and net amounts without hiding either transaction.

### Recurring calendar

- Visually distinguish expected, settled, missed, cancelled, and price-changed
  events.
- Reminder SMS creates an expected event, not a transaction.

### Budgets

- Show limit, spent, repayments, remaining, and projected month end.
- Use warning color only near/over the user-defined threshold.
- Budget editing must not resemble transaction editing.

## Accessibility acceptance

- TalkBack order follows visual reading order.
- Icon-only controls have semantic labels/tooltips.
- Amounts and merchant names remain usable at large text sizes.
- Color is never the only status signal.
- Contrast, focus order, keyboard navigation where applicable, and screen-reader
  announcements are checked on-device before release.
