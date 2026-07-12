# PaisaTrack Design System

Binding UI/UX conventions for all screens and widgets. Implemented in
`lib/core/theme/` (`app_tokens.dart`, `app_theme.dart`, `paisa_colors.dart`,
`category_visuals.dart`). Any visual value not taken from these files is a
review defect.

## 1. Principles

1. **Calm confidence.** The app handles money and reads private SMS; the UI
   must feel quiet, precise, and trustworthy. No decoration that competes with
   numbers. One accent moment per screen, maximum.
2. **Numbers are the interface.** Amounts get the strongest type on every
   screen; everything else supports them. All money renders with tabular
   figures (`AppTheme.tabularFigures`) so columns align.
3. **Dark-first.** The brand anchor is the app icon: near-black green, emerald,
   gold. Dark is the default theme; light is a full equal variant derived from
   the same tokens — never a half-maintained afterthought.
4. **Confidence is visible, never noisy.** Auto-labeled transactions look
   normal. `needs_review` gets a quiet warning chip. Only failures use error
   red. The user should sense the system's certainty without reading about it.
5. **Interruption budget applies to UI too.** Max 2 ask-notifications per day
   (PLAN §7.5), no badgering banners, no confirmation dialogs for reversible
   actions — use undo snackbars instead.

## 2. Color

Tokens: `AppColorTokens` in `lib/core/theme/app_tokens.dart`.

| Role              | Dark      | Light     | Usage                                              |
| ----------------- | --------- | --------- | -------------------------------------------------- |
| Background        | `#0B1210` | `#F6FAF8` | Scaffold                                           |
| Surface           | `#141D1A` | `#FFFFFF` | Cards, nav bar                                     |
| Surface raised    | `#1B2724` | `#EEF5F2` | Chips, elevated tiles                              |
| Primary (emerald) | `#34D399` | `#0E9F6E` | CTAs, active nav, selection                        |
| Accent (gold)     | `#E8B54D` | `#E8B54D` | Insight highlights, achievements — sparingly       |
| Info (royal blue) | `#3B82F6` | `#3B82F6` | Informational accents (matches illustration tiles) |
| Credit            | `#3DDC97` | `#0E9F6E` | Received amounts only                              |
| Debit             | `#F48A8A` | `#D64545` | Spent amounts only                                 |
| Warning           | `#FBBF24` | `#B45309` | needs_review, degraded permission, price creep     |
| Error             | `#F87171` | `#DC2626` | Failures only                                      |

Hard rules:

- Debit/credit colors apply to **amount text and direction indicators only**,
  never to whole rows, backgrounds, or icons. A screen full of red rows reads
  as alarm; spending is normal, not an emergency.
- Debit ≠ error. Debit is desaturated rose; error red is reserved for actual
  failures (parse errors, load failures).
- Read semantic colors via `PaisaColors.of(context)` (theme extension with a
  safe fallback), never `Colors.red`/`Colors.green`.
- Gold appears at most once per screen. It marks moments (insight found,
  goal hit), not chrome.

## 3. Typography

System font (Roboto on Android) — free, no bundled font dependency. Use the
Material 3 `TextTheme` from `AppTheme`; the scale below maps roles to usage:

| Role         | Size/weight                   | Usage                                                                 |
| ------------ | ----------------------------- | --------------------------------------------------------------------- |
| Hero amount  | 32 / w700, tabular            | Dashboard month net                                                   |
| Card amount  | 20 / w600, tabular            | Summary cards, list trailing amounts                                  |
| Screen title | 22 / w700, -0.3 tracking      | AppBar                                                                |
| Body         | 16 / w400                     | Explanations, notices                                                 |
| Secondary    | 14 / w400, `onSurfaceVariant` | Subtitles, timestamps                                                 |
| Label/chip   | 12 / w500                     | Chips, nav labels, section headers (UPPERCASE +0.5 tracking optional) |

Every `Text` showing money sets
`style: ...copyWith(fontFeatures: AppTheme.tabularFigures)`.

Currency format: `₹` prefix, two decimals. Indian digit grouping
(`₹1,00,000.00`) arrives with a shared `formatInr()` helper in Phase 2 — it
changes rendered strings, so it lands together with its widget-test updates,
not ad hoc per screen.

## 4. Spacing, shape, elevation

- 4pt grid: `AppSpacing` 4 / 8 / 12 / 16 / 24 / 32. Screen edge padding 16
  (`AppSpacing.screen`).
- Radius: `AppRadius` — 8 chips, 12 cards, 16 sheets/buttons, 24 hero tiles.
- Elevation: none. Depth comes from surface tone steps
  (`surfaceContainerLow` → `High`) and 1px `outlineVariant` borders, not
  shadows. This keeps dark mode clean and light mode flat-modern.
- Touch targets ≥ 48dp. Primary buttons are full-width, 52dp tall
  (already in `filledButtonTheme`).

## 5. Money & status semantics

- Debits render `-₹…` in `PaisaColors.debit`; credits `+₹…` in
  `PaisaColors.credit`. The sign is always present in lists.
- Transaction status: `auto` — no adornment. `needs_review`/`asked` — small
  warning-tinted chip. `confirmed` — no adornment (confirmation is the normal
  state, not an achievement).
- Transfers and cash withdrawals (excluded from spending aggregates, PLAN §5)
  render amounts in neutral `onSurface`, not debit red.
- Empty states are designed, not blank: brand illustration (48–120dp) +
  one-line explanation + one action. Never a bare centered string on a new
  screen (existing bare strings are grandfathered until their screens are
  reworked in Phase 2).

## 6. Iconography

Two tiers, never mixed:

1. **Brand illustrations** (`assets/icons/*.png`, via `AppIllustrations`):
   glossy 3D tiles. Hero use only — onboarding, empty states, feature intros,
   at 48–120dp. Never in lists, tabs, buttons, or app bars.
2. **Material icons**: all functional UI. Outlined variant for inactive nav /
   secondary actions, filled for active/selected. Category icons come from
   `CategoryVisuals.icon(name)` mapping the seed JSON identifiers.

Category tiles in lists: 40dp circle, `CategoryVisuals.color(id)` at 15%
alpha background, full-strength icon, 20dp icon size. Category hues are fixed
across themes so users build recognition (see `category_visuals.dart` for the
18 seed assignments).

User-created categories choose from the fixed Material icon catalog exposed by
`CategoryVisuals.iconOptions`. Creation preselects an icon with the local,
deterministic `suggestIcon(name)` keyword rules; the user may override it in the
same dialog and edit it later. Suggestions are conveniences, never model output:
unknown text uses the generic category icon. The initial curated vocabulary
covers smoking, family transfers, health, housing, personal care, tea/coffee,
investments/redemptions, bike service, connectivity/recharge, AI subscriptions,
salary/dividends/stocks, cannabis, and alcohol.

Asset debt (flagged): the PNGs are 1254×1254 and ~1.4 MB each (~14 MB total).
Before Phase 5 release, resize to ≤512px and re-compress (target ≤150 KB each)
or move to WebP.

## 7. Motion

- `AppDurations.fast` (150ms): state changes, chip toggles, color transitions.
- `AppDurations.standard` (250ms): navigation transitions, list insertions,
  expansion.
- Easing: `Curves.easeOutCubic` in, `Curves.easeIn` out.
- A newly captured transaction appearing on the dashboard may use a single
  subtle entrance (fade + 8dp slide). No looping, parallax, or celebratory
  animation anywhere near money figures.
- Respect `MediaQuery.disableAnimations` for anything beyond opacity/color.

## 8. Accessibility

- Contrast: text ≥ 4.5:1, large amounts ≥ 3:1 against their surface (token
  pairs above are chosen to pass; re-verify when adding tokens).
- Color never carries meaning alone: direction always has the `+`/`-` sign,
  status always has chip text, category always has icon + label.
- Every icon-only tap target gets a `Semantics`/`tooltip` label. TalkBack pass
  is a Phase 5 exit criterion (PLAN §9).
- Text scales to 1.3× without truncating amounts; amounts may wrap or the
  layout reflows, but figures are never ellipsized.

## 9. Component recipes

- **Summary card**: `Card` (themed) + 16 padding; label in secondary style,
  amount in card-amount style with direction color; optional leading 40dp
  icon tile.
- **Transaction tile**: leading category tile (§6), title = merchant display
  name (single line, ellipsis), subtitle = category · time in secondary style,
  trailing = signed amount (tabular). Tap opens detail; long-press reserved
  for multi-select (Phase 2).
- **Notice (degraded/warning)**: warning-tinted container
  (`warning` at 12% alpha background, `AppRadius.md`), leading
  `Icons.info_outline`, body text — not bare colored text, and not the error
  color unless something failed.
- **Ask flow (Phase 2)**: notification with exactly 3 guess actions + free
  text; in-app equivalent is a bottom sheet, radius 16, one-tap answers ≥48dp.

## 10. Theme wiring & enforcement

- `MaterialApp` uses `AppTheme.light()` / `AppTheme.dark()` with
  `themeMode: ThemeMode.dark` (dark-first) until the Phase 2 settings screen
  exposes a choice (then default becomes `system`).
- Widget tests that pump bare `MaterialApp`s keep working:
  `PaisaColors.of` falls back to brightness-appropriate defaults.
- Review checklist for any UI PR: no `Colors.*` literals, no raw hex outside
  `app_tokens.dart`/`category_visuals.dart`, no magic padding/radius numbers,
  money text uses tabular figures, both themes screenshot-checked.

# 11. Interaction and Information Architecture Patterns

These patterns govern how PaisaTrack features are organised and presented. They extend the Dashboard, Transactions, Review, Recurring, Insights and Settings capabilities already defined in the master product plan.

## 11.1 Primary-destination navigation

### Pattern

Use a small number of stable, task-oriented primary destinations:

1. **Home**
2. **Transactions**
3. **Review**
4. **Insights**

Settings, categories, accounts, rules, recurring-series management and developer tools are secondary destinations.

Material 3 uses navigation bars for switching between a small set of top-level destinations. For larger devices, the equivalent pattern is a navigation rail, which supports several destinations and an optional floating action button. ([Material Design][1])

### PaisaTrack implementation

```text
Bottom navigation
├── Home
├── Transactions
├── Review
└── Insights

App bar
├── Search
├── Privacy-mode toggle
└── Settings/Profile

Floating action
└── Add transaction
```

### Rules

- Navigation destinations must represent user goals, not implementation modules.
- Recurring payments belong inside Insights, with upcoming items surfaced on Home.
- Categories, accounts and rules belong inside Settings or contextual flows.
- The Review destination displays a badge only when unresolved items exist.
- Bottom-navigation structure must not change based on feature flags.
- Preserve navigation state and scroll position when switching destinations.
- Use `NavigationRail` or equivalent responsive shell on tablets and desktop-sized layouts.

---

## 11.2 Overview-to-detail hierarchy

### Pattern

Start with a concise overview and let users drill into details. Home answers “What needs my attention?” while Transactions and Insights answer “Why?” and “Show me more.”

Copilot’s dashboard combines new transactions, categories needing attention, recurring payments and net-income information rather than acting as a collection of feature buttons. Monzo’s Trends experience separates Balance, Spending and Targets, while YNAB allows users to move from broad spending trends into categories and individual transactions. ([help.copilot.money][2])

### PaisaTrack implementation

```text
Home summary
    ↓
Category card
    ↓
Category detail
    ↓
Filtered transaction list
    ↓
Transaction detail
```

Every dashboard number must support drill-down:

| Home element     | Tap destination                           |
| ---------------- | ----------------------------------------- |
| Total spent      | Debit transactions for selected period    |
| Total received   | Credit transactions for selected period   |
| Category bar     | Category detail                           |
| Top merchant     | Merchant detail                           |
| Review count     | Review queue                              |
| Upcoming payment | Recurring-series detail                   |
| Anomaly          | Explanation and contributing transactions |
| Forecast         | Forecast breakdown                        |

### Rules

- No dashboard card may be decorative-only.
- Every aggregate must disclose its period and inclusion rules.
- Transfers and withdrawals excluded from spending must be explainable.
- Home shows the most important summary; detailed controls belong deeper.
- Avoid making Home a vertically endless analytics report.

---

## 11.3 Progressive disclosure

### Pattern

Show the common decision first and reveal advanced options only when needed.

Progressive disclosure is used to manage feature complexity by keeping advanced or less frequent options on secondary surfaces. It is particularly suitable for financial applications where basic views should remain approachable while detailed data remains available. ([Nielsen Norman Group][3])

### PaisaTrack examples

#### Transaction detail

Initially show:

- Merchant
- Amount
- Category
- Date and time
- Account
- Note

Under **More details** show:

- Transaction reference
- Channel
- Balance after transaction
- Parse source
- Confidence explanation
- Original SMS
- Rule that categorised it
- Duplicate-detection information

#### Category selection

Initially show:

- Three suggested categories
- Recent categories
- Search field

After expanding:

- All categories
- Parent/subcategory hierarchy
- Create category
- Rule scope
- Retroactive application options

#### Insights

Initially show:

- What changed
- Difference in rupees and percentage
- One-sentence explanation

After expansion:

- Baseline used
- Historical comparison
- Contributing merchants
- Contributing transactions
- Calculation method

### Rules

- Do not hide information required for the current decision.
- Advanced information must remain discoverable.
- Avoid expanding multiple nested levels on the same screen.
- Technical confidence data belongs behind an explanation action, not beside every transaction.

---

## 11.4 Review Inbox pattern

### Pattern

Treat uncertain financial data as a unified inbox rather than scattering confirmation prompts across several screens.

Copilot uses a visible “to review” state and supports reviewing or editing transactions from transaction lists. Its web application also supports quick category editing and bulk review. ([help.copilot.money][4])

### PaisaTrack Review Centre

The queue includes:

- Uncertain category
- Unknown merchant
- New P2P counterparty
- Potential duplicate
- Suspected recurring transaction
- Unparsed or incomplete transaction
- Unidentified account
- Anomaly requiring acknowledgement

### Review-card hierarchy

```text
₹2,450.00
RAHUL@OKHDFCBANK
Yesterday · UPI · HDFC ••4521

Suggested: Transfer
Reason: New counterparty

[Confirm] [Choose category] [Skip]
```

### Queue priority

1. High-value unresolved transactions
2. Items blocking an important insight
3. Frequently recurring merchants
4. Potential duplicates
5. Lowest-confidence predictions
6. Oldest unresolved items

### Rules

- Changing category and confirming must be separate actions.
- Confirming accepts the existing suggestion.
- Correcting opens the shared category or merchant picker.
- Queue order must remain stable while an item is being edited.
- Completed items leave with a subtle standard-duration animation.
- Provide list, single-card and bulk-review modes.
- Review badges indicate count, not urgency colour.

---

## 11.5 Shared-picker pattern

### Pattern

Category, merchant and account selection must use reusable components backed by the same domain logic.

Material bottom sheets are intended for secondary content anchored to the current screen. They work well when users need to retain the context behind the selection. They should not be nested or used for lengthy, multi-stage workflows. ([Material Design][5])

### Shared components

```dart
CategoryPickerSheet
MerchantPickerSheet
AccountPickerSheet
CorrectionScopeSheet
TransactionFilterSheet
RuleCreationSheet
```

### `CategoryPickerSheet` structure

```text
Search categories

Suggested
[Food & Dining] [Transfer] [Shopping]

Recent
[Groceries] [Transport] [Bills]

All categories
Food & Dining
Groceries
Transport
Shopping
...

+ Create category
```

### Invocation contexts

The same picker must be used from:

- Transaction detail
- Manual transaction creation
- Review queue
- Merchant-detail default category
- Bulk edit
- Notification deep link
- Rule creation
- Historical recategorisation

### Rules

- Do not implement separate category-selection UIs per screen.
- Suggestions may differ by context, but selection behaviour must remain identical.
- Search remains pinned when the full list scrolls.
- Current category is visibly selected.
- Selection should not save until the parent flow confirms its intended scope.
- Large category-management operations open a full screen, not another bottom sheet.

---

## 11.6 Correct-once learning pattern

### Pattern

When users correct data, the interface should make the scope explicit without forcing them through a miniature tax-return form.

Copilot supports transaction categorisation based on reviewed historical behaviour and provides rules for automatically categorising future transactions. ([help.copilot.money][6])

### Correction flow

After selecting a category:

```text
Apply “Rent” to:

● Only this transaction
○ Future transactions from Rahul
○ Existing and future matching transactions
```

Recommended defaults:

| Context                | Default scope                |
| ---------------------- | ---------------------------- |
| New unknown merchant   | Future matching transactions |
| One-off manual edit    | This transaction only        |
| Bulk review            | Selected transactions        |
| Existing merchant rule | Update future rule           |
| Historical cleanup     | Existing and future matching |

### Rules

- The selected scope must be visible before commit.
- Remember the user’s most recent scope by correction context.
- Never silently retroactively modify historical transactions.
- The write must atomically update transaction, feedback, alias and rule data.
- Show an undo snackbar after completion.
- Display “PaisaTrack will remember this” only when a reusable rule was actually created.

---

## 11.7 Quick edit plus full-detail pattern

### Pattern

Support common edits inline, but reserve complex changes for transaction detail.

Copilot exposes unreviewed indicators and quick category editing within transaction-list contexts, while retaining a full transaction view for richer changes. ([help.copilot.money][4])

### PaisaTrack quick actions

From a transaction tile:

- Confirm
- Change category
- Add note
- Mark as transfer
- Delete

From transaction detail:

- Change merchant
- Change account
- Split transaction
- Add recurring-series membership
- Create or modify rule
- Inspect SMS
- Inspect confidence trail
- Resolve duplicate
- Exclude from analytics

### Rules

- Tapping the tile opens detail.
- Long press enters multi-select.
- Swipe actions are optional shortcuts, never the only access path.
- Do not overload a transaction row with five visible buttons.
- Quick edits must use the same domain commands as detail-screen edits.

---

## 11.8 Search, filter and saved-view pattern

### Pattern

Use visible search for discovery and chips for currently active filters.

Material search supports suggestions while the user types. Material chips are intended for selection, filtering, suggestions and contextual actions. ([Material Design][7])

### PaisaTrack transaction search

Support:

- Merchant name
- Category
- Amount
- Account
- Reference ID
- Note
- Channel
- Date expression
- Review status

Example queries:

```text
zomato
food last month
more than ₹5000
uncategorised
upi credits
transfers to rahul
bank fees this year
```

### Filter UI

Keep only active or high-frequency filters visible as chips:

```text
[This month] [Debit] [Food] [+2 filters]
```

The complete filter form opens in `TransactionFilterSheet`.

### Rules

- Search and filters combine rather than replace one another.
- Active filters remain visible after closing the sheet.
- Provide “Clear all” when more than one filter is active.
- Preserve filter state when opening and returning from transaction detail.
- Empty results must explain the applied filter conditions.
- Add saved views only after real repeated usage is established.

---

## 11.9 Glance-then-drill analytics

### Pattern

Present analytics in two levels:

1. Quick-glance interpretation
2. Detailed investigation

Revolut describes its analytics as supporting both quick-glance understanding and deeper exploration. YNAB’s spending breakdown exposes category percentage, while Monzo supports category and merchant breakdowns across monthly and yearly views. ([Revolut][8])

### Dashboard chart rules

- Summary values come before charts.
- Charts answer one question each.
- Labels and values must remain readable without interpreting colour.
- Top categories should normally use horizontal bars.
- Donuts are allowed only for simple part-to-whole comparison with limited categories.
- “Other” aggregates lower-ranked categories.
- Tapping a chart segment opens the filtered detail.
- Always include the exact amount outside or alongside the chart.
- Avoid legends requiring users to repeatedly match colours with names.

### Recommended visualisation mapping

| Question                         | Visualisation                       |
| -------------------------------- | ----------------------------------- |
| How much have I spent?           | Hero amount                         |
| How is spending changing?        | Line or compact bar trend           |
| Where did it go?                 | Ranked horizontal category bars     |
| Which merchants dominate?        | Ranked merchant list                |
| Am I ahead or behind last month? | Comparison stat with delta          |
| What will month-end look like?   | Progress line plus projected marker |
| What caused the anomaly?         | Contributing transaction list       |

---

## 11.10 Recurring timeline pattern

### Pattern

Recurring payments should be presented as an upcoming timeline, not merely another category chart.

Copilot’s dashboard surfaces upcoming recurring transactions, while Monzo incorporates upcoming payments into balance and left-to-spend calculations. ([help.copilot.money][2])

### PaisaTrack implementation

```text
Today
Netflix                   ₹649

18 July
Home loan EMI          ₹24,500

22 July
Jio Fiber                 ₹999
Price increased by ₹100
```

### Rules

- Upcoming date is visually stronger than recurrence metadata.
- Separate subscriptions, EMIs, bills and recurring income through labels, not separate screens.
- Price creep uses warning styling.
- Missed payments must explain the expected date and evidence.
- Users can pause, end or correct a recurring series.
- Home shows the next few items; Insights contains the full recurring hub.

---

## 11.11 Reversible-action pattern

### Pattern

Use undo for quick reversible actions instead of confirmation dialogs.

Material snackbars provide lightweight operation feedback and may contain one action, commonly Undo. ([Material Design][9])

### Use snackbar plus Undo for

- Transaction deletion
- Category correction
- Review confirmation
- Rule creation
- Exclusion from spending
- Marking an item recurring or not recurring
- Bulk recategorisation

### Continue using confirmation dialogs for

- Delete everything
- Database replacement during import
- Merchant merge affecting many records
- Category merge
- Removing encryption or app lock
- Irreversible model/data deletion

### Rules

- Snackbars describe the result, not the requested action.
- Only one snackbar action is allowed.
- Undo restores all affected records atomically.
- Do not show a success dialog after routine operations.
- Destructive bulk actions must show the affected transaction count.

---

## 11.12 Adaptive-layout pattern

### Pattern

Preserve the same information architecture across compact and expanded layouts while changing composition.

Material recommends navigation rails for medium-sized layouts, allowing primary destinations and an optional floating action. ([Material Design][10])

### Compact phone

- Bottom navigation
- Single-column dashboard
- Bottom-sheet filters and pickers
- Full-screen details

### Foldable/tablet

- Navigation rail
- Two-column dashboard where useful
- Transaction list plus detail pane
- Persistent category/filter side panel where space permits
- Review queue and selected item side by side

### Rules

- Do not merely stretch phone cards across a tablet.
- Preserve destination names and ordering.
- Use master-detail for Transactions and Review.
- Avoid fixed pixel widths.
- Never require landscape orientation.

---

## 11.13 Accessibility-first interaction pattern

Android recommends touch targets of at least `48dp × 48dp`, text contrast of at least `4.5:1` for normal-size text and meaningful descriptions for interactive elements. ([Android Developers][11])

### Mandatory PaisaTrack rules

- Every interactive element has a minimum 48dp target.
- Category icons do not become the only category label.
- Debit and credit use signs as well as colour.
- Charts expose accessible textual summaries.
- TalkBack reads transaction rows in this order:

```text
Zomato, Food and Dining,
minus 449 rupees,
yesterday at 8:42 PM,
needs review.
```

- Decorative illustrations are excluded from accessibility semantics.
- Amounts are never truncated.
- At larger text sizes, trailing amounts move below merchant information.
- Every swipe action has an equivalent visible or overflow-menu action.
- Review flows work without gestures.

---

# 12. Screen-level reference map

| PaisaTrack area    | Primary pattern reference | What to borrow                                              |
| ------------------ | ------------------------- | ----------------------------------------------------------- |
| Home               | Copilot Dashboard         | Summary, review queue, recurring and trends in one overview |
| Transactions       | Copilot transaction views | Review indicator, quick category edit, full detail          |
| Review             | Copilot “To Review”       | Clear pending state and bulk resolution                     |
| Insights           | Monzo Trends              | Balance, spending and target-style separation               |
| Category analytics | YNAB Spending Breakdown   | Category share with drill-down                              |
| Forecast           | Monzo Balance/Targets     | Current pace, upcoming payments, projected available amount |
| Category learning  | Copilot Intelligence      | Categorisation improves after reviewed examples             |
| Category picker    | Material bottom sheet     | Contextual, searchable secondary selection                  |
| Filters            | Material chips and search | Visible active filters and suggestion-backed search         |
| Undo               | Material snackbar         | Lightweight feedback for reversible actions                 |
| Tablet layout      | Material navigation rail  | Stable destinations with expanded composition               |

---

# 13. Patterns PaisaTrack must avoid

## Feature-launcher dashboard

Do not create a grid containing buttons for Transactions, Categories, Recurring, Insights, Assistant, Rules, Accounts and Settings. Navigation already exists. Home is for information and attention, not a menu wearing card components.

## More bottom-navigation destinations

Do not add separate tabs for Accounts, Recurring, Categories or Assistant. They are subordinate capabilities, not independent daily goals.

## Nested bottom sheets

A category picker may open as a bottom sheet. Category creation should then use either an inline expansion or a full-screen route, not a second sheet floating on top of the first like badly stacked dinner plates.

## Duplicate category-selection flows

Review, transaction detail and manual entry must not own separate category UI or category-ranking logic.

## Confidence-score wallpaper

Do not display `83% confidence` on ordinary transaction rows. Show normal, suggested or needs-review states. Exact scores remain in the explanation or developer screen.

## Chart-heavy Home

Do not show category donut, merchant pie, weekly bars, monthly line, income bars and forecast curve simultaneously. The dashboard should prioritise the numbers and one or two meaningful comparisons.

## Confirmation-dialog addiction

Routine edits use undo. Dialogs are reserved for destructive or difficult-to-reverse operations.

## Hidden gesture dependency

Swipes and long presses may accelerate workflows, but every action needs a visible alternative.

## Colour-only meaning

Red, green, gold and warning colours cannot be the sole indication of direction or state.

---

# 14. Enforcement checklist

Every UI PR must answer:

- Does this capability belong in an existing primary destination?
- Does it reuse the shared picker, transaction tile and correction workflow?
- Is the common action visible before advanced options?
- Can every aggregate drill into its underlying transactions?
- Is the action reversible through Undo where practical?
- Does the screen remain useful with no ML model installed?
- Does it work in both light and dark themes?
- Does it support 1.3× text scaling without truncated amounts?
- Are all touch targets at least 48dp?
- Has compact and expanded layout behaviour been defined?
- Has a screenshot test been added for empty, normal and error states?
- Is the implementation borrowing a proven interaction pattern rather than cloning another app’s branding?
