# UI Gaps and Redesign Conformance

Status: proposal (2026-07-26). Companion to `docs/sms-intelligence-design.md`,
which covers the data pipeline; this document covers the interface.

Source of truth for intended design:
`design/App screens exploration/design_handoff_paisatrack_redesign/README.md`
(high-fidelity, ten screens, light and dark) and
`PaisaTrack Redesign.dc.html`.

Eight issues, each verified against the current source. Six are regressions or
omissions against the existing handoff; two (profile, assistant search) are new
scope the handoff does not cover and are specified here.

---

## U1 — Category icons are the generic fallback everywhere

**Severity: high.** This is the most visible defect in the app and the cheapest
to fix.

`BloomCategoryTile` takes `categoryId` (drives the hue) and `iconName` (drives
the glyph) as *separate* parameters:

```dart
final hue  = CategoryVisuals.color(categoryId);
final icon = CategoryVisuals.icon(iconName);   // null → Icons.category_outlined
```

Every call site passes `categoryId` and **none** passes `iconName`:

| Call site | Line |
|---|---|
| `dashboard_widgets.dart` (category bars) | 698 |
| `dashboard_widgets.dart` (today list) | 1037 |
| `transactions_screen.dart` (activity rows) | 614 |
| `weekly_review_screen.dart` (sort card) | 515 |
| `weekly_review_screen.dart` (list mode) | 770 |
| `insights_screen.dart` (top categories) | 714 |
| `transaction_detail_screen.dart` (head row) | 185 |
| `recurring_screen.dart` | 407 |

So `CategoryVisuals.icon(null)` returns `fallbackIcon` — `Icons.category_outlined`
— on every list row in the app. Colours are correct, which is why the bug reads
as "icons look wrong" rather than "icons are missing": each row is correctly
tinted but carries the same generic glyph.

The data is already available. `TransactionRepository` populates `categoryIcon`
(lines 843 and 880) from `category?.icon`, and the seed JSON carries real
Material identifiers (`restaurant`, `delivery_dining`, `emoji_food_beverage`, …).
The value is fetched, then dropped before it reaches the widget.

`recurring_screen.dart:407` has a second, distinct defect: it passes
`categoryId: series.kind`, where `kind` is a recurrence classification
(`subscription`, `emi`), not a category id — so the hue is wrong there too and
falls through to `fallbackColor`.

**Fix.** Pass `iconName` at every call site from the already-loaded
`categoryIcon`. Then remove the silent-null failure mode: make `BloomCategoryTile`
resolve the icon from `categoryId` when `iconName` is absent, so a missing
parameter degrades to the *right* icon rather than the generic one. Add a widget
test asserting that a food-category row renders `Icons.restaurant`, not
`Icons.category_outlined` — the absence of that assertion is why this shipped.

---

## U2 — Category picker is a constrained sheet, not full screen

`CategoryPickerSheet` is a bottom sheet with
`ConstrainedBox(maxHeight: 640)` and an autofocused search field. With the
keyboard open on a 402×874 device, the visible result list collapses to a few
rows, and the seed taxonomy is large and hierarchical (parents plus indented
children), so searching means scrolling a viewport barely taller than the
keyboard.

**Fix.** Promote it to a full-screen route (`showBloomFullScreenSheet` or a
`PageRoute` with the sheet's grab-handle and back affordance preserved, per the
handoff's rule that every secondary screen has a visible exit). Keep the existing
Suggested / Recent / All sections and hierarchical ordering — those are good.
Add: sticky search header, section headers that persist while scrolling, and
result count. Retain swipe-down-to-dismiss so the interaction still feels like a
sheet.

This screen also becomes the target of the "More…" chip specified in handoff §08,
so it needs to hold up as a primary surface rather than an overflow.

---

## U3 — The source SMS is not visible

`transaction_detail_screen.dart` has a "Technical details & SMS provenance"
disclosure (line 524) that expands to show *parsed* fields — channel, status, ref
id, VPA, balance, confidence — and, only under `kDebugMode`, `confidenceJson`.

**The raw message body is never shown to a user in any build.**

The handoff already specifies the intended treatment (§08 Transaction detail):

> **Provenance**: 12px/700 label "WHERE THIS CAME FROM"; radius 18 `#F1FBF6` +
> 1px `#C9EEDD` block containing the raw SMS in mono 11px `#4E7A69`
> (1.6 line-height), then a 24px `#0E7A56` "Parsed locally" badge and 11px
> "Template match · 99%".

So this is an unimplemented part of the accepted design, not a new request.

**Fix.** Render the raw body from `raw_sms` for the linked `smsId`, in release
builds, as a first-class section rather than behind a "technical details"
disclosure. Three constraints:

1. **Retention.** `raw_sms` is purged after 30 days
   (`AppConstants.rawSmsRetentionDays`), so the section must degrade to
   "Original message no longer stored — kept for 30 days" rather than showing an
   error or an empty box. This is a normal state, not a failure.
2. **Masking.** Show the body as stored. It already contains masked account
   tails from parse time; do not re-derive or unmask anything.
3. **Screenshot and lock.** The body is the most sensitive string in the app.
   It should be excluded from any future home widget (T-091) and covered by app
   lock (T-090).

This section is also where `docs/sms-intelligence-design.md` §9 "explain-this-charge"
lands: once T-131 stores evidence spans, the same block highlights the exact
substrings the amount and date were read from. Building the container now and
adding highlighting later is the right order.

---

## U4 — Category change is behind a button, not the category itself

In `transaction_detail_screen.dart` the category row (line 243) renders the
label as inert text and puts `onTap: _changeCategory` on a separate 12×6px
"Change" pill (line 273).

Two problems: the obvious tap target — the category name and its coloured tile —
does nothing, and the actual target is a small pill well below the 48dp minimum
that T-128 is already chasing.

**Fix.** Make the whole category row the control: tile + name + a trailing
chevron, one `InkWell`, ≥48dp, with a `Semantics` label of
"Category, Food & Dining, double tap to change". Drop the "Change" pill.

The handoff's §08 goes further and puts inline category *chips* in the detail
sheet — selected chip in the full category hue, alternatives in `#F1EFFB`, and a
final "More…" chip opening the picker. That is the better end state: the common
case (one of three or four likely categories) becomes a single tap with no sheet
at all. Recommend implementing the chips, with the whole-row tap as the fallback
for the "More…" path.

---

## U5 — Assistant suggested questions were dropped in the redesign

Commit `5207874` ("feat(assistant): implement Bloom Ask PaisaTrack experience")
replaced a curated, categorised prompt catalogue with four hardcoded strings.

Before, `assistant_screen.dart` held `_allCategories` — **44 questions across 7
groups**, browsable by group:

| Group | Questions |
|---|---|
| Spending | 8 |
| Breakdowns | 6 |
| Subscriptions & Bills | 6 |
| Income & Savings | 6 |
| Trends & Compare | 6 |
| Insights & Alerts | 5 |
| Merchants & Fees | 7 |

After, `_PresetQuestions` (line 314) is:

```dart
final presets = [
  'How much on Swiggy this month?',
  'Can I afford a ₹5,000 dinner?',
  'Show food vs shopping',
  "What's my burn rate?",
];
```

Two of those four are not reliably answerable: `IntentValidator` supports
totals, category breakdowns, merchant lookups, upcoming recurring,
month-over-month comparison, and active insights. "Can I afford a ₹5,000 dinner?"
has no matching intent kind and will refuse. The catalogue that was deleted was
written *against* the supported intents and mostly succeeds — so the regression
cost both discoverability and answer rate.

**Fix.**

1. **Restore the catalogue**, moved out of the widget into
   `lib/intelligence/assistant/prompt_catalogue.dart` so it can be unit-tested
   against `IntentValidator`. Recovery source: `git show 5207874^:lib/features/assistant/assistant_screen.dart`.
2. **Add a test that every catalogue entry validates to a supported intent.**
   This is what prevents the catalogue and the classifier drifting apart again,
   and it is the mechanism the user is really asking for with "all the optimised
   queries".
3. **Add search over the catalogue** — a search field on the empty state
   filtering across all 44 by keyword, with group headers preserved. Typing
   "subscription" surfaces the six subscription prompts.
4. **Follow the handoff's composer treatment** (§07): three rotating suggestion
   chips above the input, drawn from the catalogue, with the full searchable list
   reachable from the empty state — "a rotating 3-visible chip row … instead of a
   42-item tray". Both surfaces read from one catalogue.

Entries should be pruned or rewritten where they no longer match supported
intents, and the four current presets kept only if they pass the validator test.

---

## U6 — Ask PaisaTrack does not match the design

`assistant_screen.dart` diverges from handoff §07 in ways that are structural,
not cosmetic. Current versus specified:

| Aspect | Design (§07) | Current |
|---|---|---|
| Surface | Always dark `#0E0C1A` sheet | Follows theme — light in light mode |
| Presentation | Full-height sheet opened from the nav Ask orb | `Scaffold` with an `AppBar` |
| Header | 34px mascot, title, emerald "On-device · no internet used" sub, ✕ right | **Title rendered twice** — once in the `AppBar` (line 106) and again in a header row (line 140); sub reads "Natural language financial search" |
| Privacy line | 11px emerald sub-line under the title | A separate pill badge below the header |
| Assistant bubble | `#191630` + 1px `#262244`, radius `20 20 20 6` | Radius `4 18 18 18` — the tail is on the wrong corner |
| User bubble | `#6D5AE6`, radius `20 20 6 20`, max 78% | Radius `18 18 18 4`, `left: 40` margin |
| Inline chart | 52px bars, category-hue highlight, mono axis, rule, explanatory line | Not implemented |
| Follow-up chips | Under each bubble; action chips in emerald | Not implemented |
| Verdict answers | Lead with 14px/600 emerald line, then 13px reasoning | Not implemented — plain text |
| Composer | 52px pill, 40px **emerald gradient** send button with ink ↑ | 48px pill, 36px flat **violet** circle, white ↑ |
| Suggestion chips | 30px rotating row above the input | Absent |
| Thinking state | Three 6px violet dots, 600ms stagger | `BloomSkeleton` bar |
| Model missing | Gold bubble offering "Download the … brain" with size and progress | Plain error sentence |
| No answer | Sentence plus two reframing chips | Plain error sentence |

The duplicated title is a straightforward bug — both the `AppBar` and the header
row render "Ask PaisaTrack", so it appears twice on screen.

**Fix.** Rebuild against §07: drop the `AppBar` and present as a dark
full-height draggable sheet from the nav orb; single header with mascot, title,
emerald privacy sub, and ✕; corrected bubble radii and widths; emerald gradient
send button; dot-pulse thinking state; and the three specified terminal states
(model missing, no answer, refusal) as designed rather than as generic error
text.

Sequence this after U5 so the composer is built once, with the catalogue already
in place.

---

## U7 — No profile section

The handoff has ten screens and no profile; this is new scope, so it needs
definition before implementation.

**Constraint.** PaisaTrack has no account, no server, and no identity
(ADR 0002, `docs/privacy.md`). A "profile" here cannot mean a user record. It
should mean *local personalisation plus a mirror of what the app knows about
you* — which is genuinely useful and fits the privacy story rather than
straining it.

**Proposed contents.**

| Section | Contents | Source |
|---|---|---|
| Identity (local) | Display name used by the Home greeting ("Hey Shivay"), mascot accent colour | New settings keys; the handoff's Home header already assumes a name exists |
| Your habits | Streak, transactions sorted, average sort time, categories in use, months of history | `streakProvider`, existing repositories |
| Money shape | Typical monthly income and spend, top three categories, commitment load | `dashboard_repository`, `recurring_detector` |
| Data footprint | Transactions stored, messages retained, database size, model installed and size, last backup | Existing settings + `model_meta` |
| Privacy posture | "No account · No cloud · No ads", permissions currently granted, one-tap link to capture controls (T-144) and erase (T-124) | Existing |

**Placement.** Not a fifth tab — the handoff fixes four destinations plus the Ask
orb, and adding a tab would break that model. Reach it from the Home header
mascot (a natural, discoverable target that currently does nothing) and from the
top of Settings. Present it as a draggable sheet like every other secondary
screen.

**Explicitly out of scope:** avatars from photos, any identifier that could
correlate across installs, and anything that implies an account exists.

---

## U8 — Shared conventions these fixes depend on

Three small pieces of shared work, worth doing once rather than five times:

1. **A full-screen sheet route.** U2, U3, U6, and U7 all need "full-height,
   draggable, grab handle, visible back or ✕". The handoff mandates it for every
   secondary screen. Build `showBloomFullScreenSheet` once.
2. **Minimum touch targets.** U4's "Change" pill is one instance of a pattern
   T-128 is already tracking. Fixing the category row should use the same
   ≥48dp helper.
3. **Category icon test coverage.** U1 shipped because no test asserts a
   specific glyph. A golden or widget test per surface that renders a category
   tile closes the class of bug, not just the instance.

---

## U9 — Skip is a one-way ratchet; there is no way back

The Sort screen has a skip action, but it cannot be undone or revisited, and the
cause is structural rather than a missing button.

`weekly_review_screen.dart` holds two pieces of state:

```dart
double _dragDx = 0.0;
final int _currentIndex = 0;          // final, and never anything but 0
final Set<String> _skippedIds = {};   // in-memory, session-scoped
```

The card view renders `activeItems[safeIndex]` where
`safeIndex = _currentIndex.clamp(...)` — and `_currentIndex` is `final int = 0`.
So the deck **always shows the first item**. Advancing works only as a side
effect of removal:

```dart
final activeItems = items.where((i) => !_skippedIds.contains(i.id)).toList();
```

Skipping adds the id to `_skippedIds`, the item drops out of `activeItems`, and
a different transaction shifts into position 0. There is no cursor to move
backwards, so "previous" is not merely unimplemented — it is unrepresentable in
the current state model. Skipped items are also lost for the session and only
return on app restart.

The handoff (§04) specifies skip as a first-class, recoverable action — a 56px
"Skip" (↺) control and swipe-left — sitting beside Accept and Choose, and the
whole screen is framed as a deck with cards flying out and the next straightening.
A deck implies a position, not a filter.

**Fix — replace the filter with a cursor.**

1. **Ordered queue plus index.** Keep one stable, ordered `List<ReviewItem>` for
   the session and a mutable `int _cursor`. Skip advances the cursor; it does not
   remove the item. Resolved items (confirmed or recategorised) are removed;
   skipped ones stay in the list with a `skipped` flag.
2. **Back navigation.** A "previous" affordance and a swipe-right-to-go-back
   gesture move the cursor backwards through everything already seen — skipped or
   resolved — so a mis-swipe is one gesture to recover, matching the handoff's
   10-second undo philosophy for other destructive actions.
3. **Wrap at the end.** When the cursor reaches the end with skipped items
   remaining, offer "N skipped — review them?" rather than showing Inbox Zero.
   Inbox Zero should mean *resolved*, not *dismissed*; today a user who skips
   everything sees the celebration screen, which is misleading.
4. **Persist across sessions.** Move skip state out of the widget into
   `reviewViewProvider` (or settings) so closing the app does not silently
   resurrect a queue the user deliberately deferred, and so "skipped" survives a
   process death mid-sort.
5. **Position indicator.** The segment progress bar in §04 already implies a
   position — with a real cursor it can show current position, resolved, and
   skipped distinctly rather than only counting down.

This also removes a latent bug: because `_currentIndex` is `final`, the
`clamp(0, activeItems.length - 1)` and the `_dragDx` drag state are effectively
dead code paths for anything other than the first card.

---

## U10 — Sort cannot edit anything except the category

The Sort card exposes exactly three actions (`weekly_review_screen.dart`
lines 192–228):

| Action | Effect |
|---|---|
| Change category (gold) | `_recategorizeItem` — opens the category picker |
| Skip (neutral) | `_skipItem` — see U9 |
| Keep (emerald) | `_confirmItem` — accepts the guess |

The card body itself is not a tap target, and nothing on the screen routes to
`TransactionDetailScreen`. So while sorting, the user cannot correct the
merchant name, amount, date, payment source, description, or notes — and cannot
mark the row as a transfer, refund, or duplicate. The only editable attribute is
the one the screen was built around.

This matters more than it first appears, because Sort is where the user is
actually *looking* at the problematic rows. A misparsed merchant
(`PAYTM-4429JK`) or a wrong payment source is most visible precisely at the
moment the app asks "what category is this?" — and the answer is often "none of
them, the parse is wrong". Today the only way to act on that is to abandon the
sort, open Activity, search for the transaction, and open its detail sheet,
which loses the sort position entirely (U9).

The handoff's §04 card is explicitly informational about these fields — it shows
merchant, amount, timestamp, and "HDFC ••4821 · UPI · from SMS" — but does not
specify them as editable, so this is a genuine gap in the design rather than a
missed implementation detail.

**Fix.**

1. **Make the card open the detail sheet.** Tapping the card body (merchant,
   amount, or the source line) opens `TransactionDetailScreen` as a sheet over
   Sort, preserving the cursor. Dismissing returns to the same card with any
   edits applied.
2. **Add an inline "Not right?" affordance** on the card for the common
   corrections — wrong merchant, wrong amount, not a spend (transfer/refund),
   duplicate — so the frequent cases do not require a full detail round trip.
3. **Preserve position across the round trip.** This depends on U9's cursor;
   with the current always-zero index, returning from a detail sheet cannot
   restore where the user was.
4. **Re-run the guess after an edit.** If the merchant is corrected, the
   classifier's suggestion for the card should refresh before the user accepts
   it — otherwise they confirm a guess based on the old, wrong merchant.

Point 4 is the one with real data consequences: confirming a category writes
feedback, rules, and learned aliases in one transaction
(`docs/architecture.md`), so accepting a guess derived from a bad merchant
string teaches the wrong rule and propagates it to future messages.

---

## Priority and sequence

| Order | Item | Ticket | Why here |
|---|---|---|---|
| 1 | Category icons | T-146 | Highest visibility, smallest diff, data already present |
| 2 | Category row tap target | T-148 | Small, ships with U1's file |
| 3 | Full-screen sheet convention | T-152 | Unblocks three later items |
| 4 | Category picker full screen | T-145 | Depends on T-152 |
| 5 | Source message view | T-147 | Depends on T-152; container for later evidence spans |
| 6 | Assistant catalogue and search | T-150 | Restores a regression; must precede the composer rebuild |
| 7 | Ask design conformance | T-151 | Largest; builds the composer once |
| 8 | Skip and go back | T-153 | Independent; small state refactor, clear user value |
| 9 | Edit from Sort | T-154 | Depends on T-153's cursor to restore position |
| 10 | Profile | T-149 | New scope, no dependency, lowest risk to defer |

## References

- `design/App screens exploration/design_handoff_paisatrack_redesign/README.md` — screen specs §01–§10
- `design/App screens exploration/PaisaTrack Redesign.dc.html` — primary visual reference
- `docs/design-system.md` §6 — category visual rules
- `docs/sms-intelligence-design.md` §9 — explain-this-charge, which extends U3
