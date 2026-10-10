# ADR 0036 — Explicit payee decisions and direction-aware cue rules

Status: Accepted (owner, 2026-10-10). Not yet implemented (T-205, T-211).

## Context

Owner data puts ~96% of a month's spend in `other` and counts only ₹10k as
money in. The categoriser ladder (`lib/enrichment/categorizer.dart:112-209`)
has 29 seed keywords, ignores `direction`/`channel`/`accountHint`, and falls
back to `other` for every unmatched payee, including personal-VPA payments
that [ADR 0011](0011-evidence-backed-assistance.md) forbids treating as
non-spending on identity alone. `other` is `is_spending = 1`, so unresolved
transfers, rent, card-bill and SIP debits inflate spend. See
[categorisation plan](../plans/categorisation-v2.md).

## Decision

1. **Cue rules.** Add a deterministic, direction-aware rule step between user
   rules and the seed map. Inputs are structured fields only (direction,
   channel, account kind, counterparty kind, merchant/VPA tokens, coded body
   cues such as `neft`, `salary_word`, `si_mandate`). Raw SMS text is never
   stored in the rule result or logs. A cue rule may set a category only when
   its evidence set is met (for example salary requires credit direction AND
   a payroll cue AND bank-account/netbanking channel). Cue results carry
   `source = 'cue_rule'`, a rule id, and confidence 0.85; they are never
   `auto`-confirmed as user labels (ADR 0011: silence is not a label).
2. **Explicit payee decisions.** A user answer to "Spending or transfer?" for
   one payee identity is an *explicit user label*. It is stored as a normal
   `rules` row (`counterparty` / `merchant` match) plus `feedback`, applied to
   past rows only through the existing correction preview and guarded Undo
   receipt (ADR 0031, T-177c). The answer "Transfer to a person" sets a
   non-spending category (`transfers_person`); it changes eligibility only
   because the user said so, never because the VPA looks personal.
3. **No amount changes.** Decisions and rules change `category_id`,
   feedback and rules only. Amount, direction, source evidence, duplicate and
   owned-transfer flags are untouched; owned-transfer linking stays derived
   from `payment_sources` + reciprocal pairs.
4. **Category taxonomy changes** (T-211) are seed-additive: ids referenced by
   rows are never deleted or renamed; reparenting is an explicit, idempotent
   migration step. Display names of seeded, non-user-edited rows may change.
5. **Diagnostics** are counts per reason bucket on device, with no payee,
   amount, VPA, phone or message content.

## Consequences

- No schema change is required for decisions (rules/feedback/model_meta are
  reused); deferral state ("Ask later") uses the T-177d model_meta entry.
  If T-205 review shows a table is needed, a follow-up ADR must precede it.
- `Categorizer.categorize` has a CRITICAL planning impact result
  (T-177.md); each change keeps the existing result type and tests.
- Backup/restore: rules and feedback already export; the migration test must
  prove reparented ids round-trip.
- Rollout is behind a feature flag defaulting off until the owner device
  distribution check in the plan passes.
