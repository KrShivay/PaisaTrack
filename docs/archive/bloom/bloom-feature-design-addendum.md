# Archived — Bloom Feature Design Addendum

Status: superseded design input; current gaps are in `docs/product-status.md`
and `TASKS.md`

Companion audit: `docs/archive/bloom/bloom-feature-migration-audit.md`

## Scope and precedence

The original Bloom handoff defines the visual language and ten primary views.
This addendum defines the missing feature surfaces required to preserve the
pre-redesign product.

Use the Bloom palette, typography, spacing, radii, motion, and components from
the handoff. When this addendum conflicts with a visual mock, preserve the
domain, privacy, and data-integrity contract first.

The redesign rules are:

- visual replacement is allowed; capability removal requires an explicit
  product decision;
- one repository/domain action must have one UI-independent implementation;
- a sheet can replace a page, but it must return the same result and expose the
  same states;
- no sample finance copy appears in production;
- raw SMS, prompts, identifiers, and exception text never appear outside their
  approved disclosure boundary.

## Global navigation and presentation

Keep the four fixed Home, Activity, Sort, and Trends tabs and the Ask orb.

Secondary destinations use one of two forms:

- **Task sheet** — short create/edit/select flows: manual entry, category picker,
  correction scope, budget editor, filters, passphrase, SMS lookup.
- **Secondary page within the active tab navigator** — searchable or potentially
  long management flows: Categories, Payee labels, Payment sources, Recurring,
  model details, diagnostics.

Every task sheet has:

- 44×5 drag handle;
- title, optional one-line explanation, and visible close/back control;
- scroll-safe body;
- pinned action area when input can be lost;
- loading/disabled action state;
- swipe-down dismissal only when it cannot discard a running irreversible
  operation or unsaved input without warning.

Every secondary page has a visible back action. Re-entering a selected primary
tab returns to that tab's root.

## SMS lookup and inbox scan

### User-facing name

Use **Find transactions from SMS** for the primary action. “SMS lookup” may be
used in engineering documentation, but “lookup” alone is ambiguous to users.

This feature scans the permitted Android SMS inbox for financial messages. It
does not expose or search the user's personal-message inbox.

### Entry points

1. Home, no transaction history: primary pill **Find transactions from SMS**;
   secondary text action **Add one manually**.
2. Activity, true empty state: same two actions.
3. Settings → Data & backup: row **Find transactions from SMS**, subtitle based
   on last scan state.
4. Onboarding: permission success automatically starts the first scan and opens
   the same progress/result model inline.

Do not show the scan action when the current view is merely filter-empty; show
**Clear filters** instead.

### `SmsLookupSheet`

Header:

- SMS icon tile in violet tint;
- title **Find transactions from SMS**;
- reassurance **Scanned on this phone. Personal messages stay private.**

States:

#### Permission needed

- Notice: **SMS access is off**
- Body: **PaisaTrack reads transaction alerts and skips OTPs, promotions, and
  personal messages.**
- Primary: **Allow SMS access**
- Secondary: **Not now**

For permanently denied permission:

- Primary: **Open Android settings**
- Instruction: **Settings → Apps → PaisaTrack → Permissions → SMS**
- Keep **Add manually** available.

#### Ready

- Show last successful scan time when known.
- Explain that re-scanning preserves edits, confirmations, deletions, and manual
  entries.
- Primary: **Scan now** or **Scan again**
- Secondary: **Cancel**

#### Scanning

- Determinate progress when Android supplies total rows; otherwise use a Bloom
  indeterminate arc.
- Live mono counter:
  - **412 of 1,240 messages checked**, or
  - **412 messages checked**
- Supporting count, when available: **38 transactions found**
- Keep the operation observable after sheet dismissal through a Home/Settings
  progress chip.
- Do not present a destructive Cancel unless the runner can cancel safely.

#### Complete

Use a green result card:

- **38 transactions found**
- **1,240 checked · 27 already known · 0 failed**
- Primary: **View Activity**
- Secondary: **Done**

If nothing new is found:

- **You're up to date**
- **No new financial transactions were found.**

#### Partial failure

Use a gold result card, never a raw exception:

- **Scan finished with some gaps**
- **1,238 checked · 36 found · 2 could not be read**
- Primary: **Retry failed messages**
- Secondary: **View Activity**

Persist a non-sensitive failure count so the warning survives the snackbar.

#### Error

- One sentence mapped from a typed failure: permission, platform unavailable,
  database unavailable, or retryable scan failure.
- Primary: **Try again**
- Secondary where relevant: **Open Android settings**
- Log only typed codes/counts. Never log sender or body.

### Result and ingestion contract

- Reuse `SmsHistoryImportRunner.run(force: true)`.
- Live and historical messages continue through `SmsIngestor`; UI code must not
  construct transactions directly.
- Deduplication, source linking, parser trust, merchant resolution,
  categorization, and user-rule precedence remain unchanged.
- Re-scan must not overwrite user edits, confirmations, manual transactions, or
  deletions.
- A release result may show aggregate counts and sanitized source labels. Raw
  SMS sender/body and confidence JSON remain developer-only.

## Home additions

### Header

- Greeting name is optional and local. If none exists, use **Good morning**,
  **Good afternoon**, or **Good evening**.
- The subline is provider-derived, for example **2 transactions arrived today**
  or **Nothing new since yesterday**.
- The streak chip shows the persisted value, including zero. It must have the
  semantic label **Open Settings; N-day sorting streak** if it remains the
  Settings entry.

### Period chip

Add a 32px chip below or beside the greeting:

- current label: **This month**, **Last 30 days**, or formatted custom range;
- tap opens `BloomPeriodSheet`;
- choices: This month, Previous month, Today, Last 7 days, Last 30 days, Choose
  month, Custom range;
- all Home metrics, categories, merchants, and transactions update from the same
  selected `DashboardPeriod`.

### Empty states

Distinguish:

- **No history** — dashed ring, **Nothing yet**, SMS lookup + manual add.
- **No activity in selected period** — **Nothing in this period**, Change period.
- **Import running** — ring arc plus live progress chip.
- **Load error** — inline error plus Retry.

### Drill-downs

- **All →** switches to Activity.
- Category row opens Activity with a visible category chip.
- Unsorted row switches to Sort.
- Budget card/commitment caption opens Recurring.
- Recent transaction opens the detail sheet.

### Budget editor

The no-budget card opens `MonthlyBudgetSheet`; it never writes a sample value.

Fields:

- amount with INR formatting;
- effective month (current month by default);
- optional clear/unset action;
- explanation: **Used for safe today and month-end projection.**

Validate positive finite amount and show the current saved amount. Save through
`BudgetRepository`.

### Insights

The gold insight card renders only a real insight/suggestion object. Its title,
body, merchant, amount, period, and action are data. If no eligible suggestion
exists, omit the card.

## Activity additions

### Header

- Title **Activity**
- 48×48 search/clear semantics even when a search field is inline
- export action only if a product-safe export format is approved
- add action for manual entry

### Filter chips

Primary chips:

- Period
- Expenses/Income/Transfers
- Category
- Account
- Unsorted

Applied values use violet tint and include a clear affordance. An **Advanced**
chip opens `BloomTransactionFilterSheet` for:

- exact date range;
- merchant;
- channel;
- min/max amount;
- reviewed/needs review;
- recurring/not recurring;
- SMS/manual;
- anomaly status.

The sheet adapts the existing `TransactionFilters` model. Do not introduce a
parallel Bloom filter type.

### Search

Search remains active after opening and closing detail. It covers:

- display and raw merchant;
- account/source hint;
- channel;
- note/description;
- reference;
- status;
- formatted/unformatted amount.

### List scale and states

- Pull down refreshes.
- Reaching the final loaded group exposes **Load older transactions** or starts
  bounded infinite loading.
- Loading, error, true empty, filter empty, and end-of-history are distinct.
- Date-group totals and summary strip update after every search/filter.

### Selection and bulk actions

Long-press or visible **Select** enters selection mode. The floating nav pill is
replaced by the Bloom selection bar:

- **N selected**
- **Categorise**
- **Apply to merchant**
- overflow **Clear selection**

`Apply to merchant` previews the matching merchant/counterparty and affected
count before creating a rule. Both actions record feedback correctly and show a
ten-second undo only when the domain operation is reversible.

### Swipe alternatives

Keep swipe-to-confirm/recategorize, but expose the same actions in a row overflow
menu and transaction detail. TalkBack announces the alternatives.

## Sort additions

### Header and modes

- title **Sort the strays**
- remaining count and time estimate
- **List view** / **Card view** toggle
- progress bars based on actual queue length

Mode and search state remain alive while switching tabs.

### Card

Show:

- amount, merchant, time, source/account;
- current proposed category;
- classifier confidence;
- one human reason from confidence/source data;
- up to three safe alternative category chips;
- **Something else** category picker.

Actions:

- **Skip** — advance locally without mutation;
- **Accept guess** — confirm and record feedback;
- **Choose** — open picker and explicit correction scope where applicable.

Gestures mirror these actions, but buttons remain visible.

### List mode

- search field;
- grouped merchant rows;
- select all filtered;
- bounded pagination/load more;
- individual confirm/category;
- bulk confirm;
- merchant-group confirm with affected count;
- clear search restores the full queue.

Provider loading or error must never render as Inbox Zero.

## Transaction detail and correction

Use a draggable, scrollable Bloom sheet. Preserve every correction and evidence
contract from the pre-redesign screen.

### Summary

- category tile;
- merchant/display label;
- date/time;
- masked payment source;
- signed amount;
- method/channel;
- needs-review or low-trust badge when applicable.

### Edit

- category chips plus **More…**;
- note/description field;
- Save action with dirty/busy state;
- errors retain the draft.

### Category scope

After changing category, show inline radio choices:

- **Just this transaction**
- **This merchant · N past and future matches**

If merchant scope is unsafe or unavailable, show only the first option with a
short explanation. Preview the affected count before save.

### Low-trust parse

When parse trust requires confirmation:

- title **Check this transaction**
- explanation **Confirm the amount, direction, and merchant.**
- **Confirm**
- **Fix**

`Fix` opens `ParseCorrectionSheet` with amount, direction, and merchant. Save
through the existing atomic repository action.

### Progressive evidence

User-facing **Transaction details**:

- direction;
- channel;
- masked account;
- balance after;
- reference;
- counterparty VPA.

User-facing **Why this category**:

- rule/feedback/seed/classifier explanation;
- category confidence where meaningful.

Developer-only **Technical evidence**:

- parse source and confidence;
- retained SMS sender/body;
- merchant/category confidence trail;
- rule id;
- pretty confidence JSON.

The release build must not reveal raw SMS body/sender or raw confidence JSON.

## Trends

### Month selection

Add the month chip from the handoff. All trend, comparison, category, merchant,
insight, and recurring summaries use the same selected period.

### Insight cards

Map `InsightsEngine` / narrative outputs to:

- fact sentence;
- consequence sentence;
- optional safe action;
- persistent dismiss action.

No UI literal may assert a merchant trend or amount. Deterministic analytics
remain available when the narrative model is disabled or unavailable.

Category and merchant rows open Activity with visible filters. Empty and error
states remain actionable.

## Recurring

Split content into:

1. monthly commitment summary;
2. next 14 days timeline;
3. recurring series/subscriptions.

Render actual states with text/icon plus color:

- expected;
- settled;
- missed;
- inactive/cancelled;
- price changed.

Never map every database row to “Active”. Price-change cards show old/new amount
when available. Row tap opens filtered Activity. **Adjust** opens series
management; stop/cancel tracking uses confirmation or undo according to actual
recoverability.

## Ask PaisaTrack

- One header only: mascot, title, **On-device · no internet used**, close.
- Keep four rotating prompt chips in the primary sheet.
- Add **Browse questions** for the existing categorized catalogue and filtering.
- Render typed states for model missing, unsupported device, download progress,
  download failure, cancellation, and retry.
- Plain deterministic paths remain usable without the optional model.
- Follow-up chips and compact charts render only structured controller output;
  they do not parse numbers back out of model prose.
- Generic errors do not include raw exception text.

## Settings and management surfaces

### Appearance

- Auto / Light / Dark segmented control
- Show paise toggle wired to `setShowPaise`
- reduce-motion follows system accessibility; no duplicate app toggle unless a
  product requirement is added

### Your money

- Monthly budget → `MonthlyBudgetSheet`
- Categories → Bloom management page
- Accounts & cards → Bloom payment-source page
- Payee labels → Bloom label-management page

Preserve search, hierarchy, icons, merge previews, conflicts, nicknames, owned
state, and analytics inclusion.

### Local AI

The model card reads live `LlmModelStatus`:

- checking;
- unsupported with reason;
- not downloaded with model size;
- downloading with progress and Cancel;
- installed with runtime/backend;
- failed with Retry;
- Delete model.

Do not display “Engine active” unless runtime state confirms it.

### Data and backup

- Back up
- Restore
- Find transactions from SMS

`BackupPassphraseSheet` uses a `Form`:

- passphrase;
- confirmation on export;
- minimum 12 characters;
- mismatch validation;
- clear controllers on disposal;
- no plaintext temp file;
- encrypted filename and `application/octet-stream`;
- generic error copy.

### Delete data

Deleting the encrypted database, key, settings, and import state is not undoable
with the current architecture. Keep explicit confirmation and consequence copy.

If product still requires a ten-second undo, first implement a delayed commit
that leaves the old encrypted database and key recoverable until the timer
expires. Do not show an Undo action without that mechanism.

### Legacy screens

Migrate these without reducing behavior:

- `manual_entry_screen.dart`
- `category_manager_screen.dart`
- `payee_labels_screen.dart`
- `payment_sources_screen.dart`
- `key_loss_screen.dart`
- `model_metrics_screen.dart`
- `unparsed_sms_screen.dart`
- `category_picker_sheet.dart`
- `transaction_filter_sheet.dart`
- `correction_scope_sheet.dart`
- parse correction and passphrase dialogs

Developer screens remain debug-only and keep plaintext/export warnings.

## Standard state contract

Every migrated surface defines:

- initial loading;
- refresh/loading-more;
- empty;
- filtered empty;
- normal;
- partial data;
- error with retry;
- destructive/busy;
- narrow width;
- large text;
- dark/light;
- reduced motion.

Do not infer empty from `AsyncValue.valueOrNull ?? []`; that makes loading and
failure look like successful emptiness.

## Accessibility

- Minimum interactive target 48×48 logical pixels, including custom
  `GestureDetector` controls.
- Custom chips/orbs/rows use `Semantics(button: true, label: ...)`.
- Every swipe and long-press action has a visible alternative.
- Status uses text/icon in addition to color.
- Focus order follows reading order.
- Modal sheets announce title and result changes.
- Import/model progress updates use polite live-region announcements.
- Large text must not hide amounts, merchant names, actions, or exit controls.

## Verification

For each migrated surface:

1. restore behavioral widget tests from the pre-redesign suite or replace them
   with equivalent Bloom tests;
2. add dark/light, narrow, large-text, and reduced-motion coverage where layout
   or gestures change;
3. run the full Flutter analyzer/test suite;
4. run Android unit tests;
5. validate SMS permission/import, model management, document picker, and
   key-loss/reset on a physical Android device;
6. run GitNexus impact before symbol edits and `detect_changes` before commit.
