# UX v2: scan, icon system, design-language refresh, screen redesigns (T-204)

Status: Proposed, planning only — 2026-10-10.
Owner: T-204 (owner items #3, #6). Subtask briefs:
[T-204](../tasks/T-204.md). Related: T-207 (Dashboard customisation; plan in
`docs/plans/intelligence-v2.md`, drafted by another agent).

## 1. Goal

One coherent, calm, fast UI: a single icon family and size ladder, one
palette/elevation/motion language, shared primitives instead of ~15 hand-rolled
button/card variants, honest states (loading / empty / error / filter-empty),
48dp targets with semantics everywhere, no flicker, and per-screen redesigns
the owner has explicitly allowed ("creativity is key"). The Dashboard streak
chip must stop reading as Settings.

Non-goals: new financial claims, schema changes, new network use, a chart
dependency, Dashboard card reorder/hide persistence (T-207).

## 2. Current state (scan evidence)

Scope scanned: 83 Dart files / ~28.5k lines under `lib/features/**`,
`lib/core/widgets/**` (incl. `bloom/`), `lib/core/theme/**`. Counts are from
`grep` over those paths on 2026-10-10.

### 2.1 Icons

- 375 `Icons.*` references: 86 `_rounded`, 49 `_outlined`, 240 plain (filled
  default). `lib/core/theme/category_visuals.dart` alone holds 178 (all plain
  or `_outlined`: `:22` `Icons.category_outlined`, `:44-62` default map,
  `:65` prefix map, `:86-207` picker options, `:286-366` name map).
- Non-rounded outside the theme folder: settings 40 (`settings_screen.dart` 22,
  `payee_labels_screen.dart` 6), transactions 17, core/widgets 11, sms 9,
  dev 8, review 6, home 5, recovery/onboarding/assistant 3 each.
  Mixed families inside one widget: `transactions_screen.dart:328`
  `sms_outlined` + `:332` `add` next to `:1186` `sms_rounded` + `:1205`
  `add_rounded`; `manual_entry_screen.dart:113/118/173` plain
  `arrow_upward/arrow_downward/event`; `category_picker_sheet.dart:78/83/270`
  `search/close/check_circle`; `bloom_sheet_scaffold.dart:79/102`
  `arrow_back/close`; `bloom_undo_toast.dart:274` `close`.
- Nav uses outlined (inactive) + rounded (selected) pairs, which is fine, but
  they are raw `Icons.*` at `home_shell.dart:76-95`, and the Ask orb uses plain
  `Icons.auto_awesome` (`:713`).
- No custom icon painter, `CupertinoIcons`, or `IconData(` in the scan
  scope; the only brand art is `AppIllustrations` PNGs
  (`app_tokens.dart:262-278`).
- Explicit `size:` values in use: 18 (29x), 20 (12x), 16 (11x), 14 (6x),
  15 (5x), 19 (3x), 24 (3x), 17, 22, 28, 32, 34 and tile sizes 36/40/44/48/54/56.
  Target ladder is 16 / 20 / 24 only. Examples to normalise:
  `dashboard_screen.dart:126/144` (16/14 for the same flame icon),
  `insights_screen.dart:268/284` (14 vs 24 default), `assistant_screen.dart:231`
  (20), `recurring_screen.dart:657/689` (18), `transactions_screen.dart:403`
  (18), `transaction_source_sms_section.dart:211` (16).
- `lib/intelligence/assistant/prompt_catalogue.dart` is the only `Icons.*` use
  outside scope; it must move to `AppIcons` as well.
- Category icons are stored as string names (`assets/seed/categories.json`,
  e.g. `"restaurant"`, `"emoji_food_beverage"`); the string-to-IconData lookup
  in `category_visuals.dart` is the only mapping point. Names persisted by
  users must keep working (no data change).

### 2.2 Period chips (Dashboard vs Trends)

Both open `BloomDatePeriodSheet` and watch `dashboardPeriodProvider`
(`dashboard_screen.dart:182-189`, `insights_screen.dart:243-250`) but are two
separate hand-rolled widgets that differ:

| Aspect | Dashboard (`dashboard_screen.dart:196-261`) | Trends (`insights_screen.dart:243-295`) |
| --- | --- | --- |
| Height | `minHeight: 48` (`:205`) | none: padding 6 + 14dp icon ≈ 28dp (`:249-254`) |
| Icon | `calendar_today_rounded` 16 | `calendar_month_rounded` 14 |
| Text | 12 / w600, up to 2 lines, primary ink | 11 / w600, secondary ink, 1 line |
| Surface | `bloomDarkTrack`/`bloomChip` + 1dp border, radius 14 | `bloomDarkCard`/`bloomChip`, no border, radius 16 |
| Chevron | yes (`keyboard_arrow_down_rounded`) | none (does not read as a dropdown) |
| Semantics | `button`, "Select period: …" (`:183-185`) | none; compact mode only a Tooltip (`:262-270`) |
| Placement | own row below header | squeezed into the title row beside "Recurring" |

Trends' second chip, Recurring (`:296-349`), has the same <48dp defect and no
semantics label. `compactHeader` (`:193`) swaps both to bare 48x48 icons with
only a Tooltip, which TalkBack does not announce as a button.

### 2.3 Tap targets < 48dp and missing semantics

- Trends period + Recurring chips (above): about 28dp tall, no `Semantics`.
- Ask send button `assistant_screen.dart:219-243`: 40x40 `GestureDetector`,
  no `Semantics`/tooltip (only a `ValueKey`), no focus/keyboard action.
- Ask "Try asking" rotate `IconButton` inside a 32dp-high `SizedBox`
  (`assistant_screen.dart:273-300`, also `:343-351`): 18dp icon, parent clips
  the 48dp button.
- Dashboard metric switcher pills: visual height 30
  (`dashboard_widgets.dart:410`) inside a 48dp hit box (OK), but their
  `Semantics(container, button)` + `ExcludeSemantics` + `GestureDetector`
  recipe is hand-copied 15 times (see 2.7).
- Onboarding icon tiles are decorative 34dp (`onboarding_screen.dart:217/277`),
  fine; `sms_lookup_sheet.dart:132` 44x44 tile, verify if tappable.
- Home Ask orb: 48dp hit area (`home_shell.dart:667-707`) but the orb is 44dp
  and the pulse ring runs forever (see 2.9).
- `review_list_row.dart:170-171` sets `tapTargetSize: shrinkWrap` with
  `minimumSize 48` (OK) but must be re-verified with 2x text.
- Hand-rolled buttons with `ExcludeSemantics` wrappers (screen-reader
  nodes depend on a separate outer `Semantics`): `transactions_screen.dart:813`
  and `:1043`, `weekly_review_screen.dart:145/924/986/1057`,
  `appearance_section.dart:228`, `settings_screen.dart:1024`,
  `recurring_screen.dart:642/722`, `dashboard_widgets.dart:401/840/1028/1439`.
  Two of them (`transaction_detail_screen.dart:1098/1164`, category chips) use a
  plain `GestureDetector` with `minHeight` only and no `selected` state.
- Total `Semantics(` sites in scope: ~50 for ~28 `GestureDetector`/many
  `InkWell`; zero `Semantics(header: true)` on section titles (spot check:
  `_SettingsSection`, dashboard sections).

### 2.4 Hard-coded colour, spacing, radius

- 123 raw `Color(0x…)` literals in `lib/features` + `lib/core/widgets`; worst:
  `recurring_screen.dart` 22 (`:499-600`), `transaction_detail_screen.dart` 13
  (`:712-763`, `:1108-1159`), `sms_lookup_sheet.dart` 13 (`:198-390`),
  `onboarding_screen.dart` 13 (`:100-369`), `dashboard_widgets.dart` 11
  (`:623-782`, `:1197-1376`), `weekly_review_screen.dart` 7,
  `assistant_screen.dart` `:212/454/501/697` (`0xFF6F6A92`, `0xFF1E1B33`).
- `Colors.white/black/…` another ~45 (e.g. `upi_qr_action.dart` 12).
- 637 `isDark` ternaries (`insights_screen.dart` 77, `weekly_review_screen.dart`
  73, `dashboard_widgets.dart` 60, `transactions_screen.dart` 55,
  `settings_screen.dart` 54, `recurring_screen.dart` 51). `PaisaColors`
  (the `ThemeExtension`) is read in only 4 files, so features bypass the theme.
- Two palettes coexist: legacy emerald/near-black-green `AppColorTokens.dark*`
  + `PaisaColors` (`app_tokens.dart:12-83`, themes at `app_theme.dart:76-125`)
  vs Bloom violet + ink (`app_tokens.dart:86-160`, themes `:128-175`). Features
  use Bloom; the Dashboard hero mixes both (green gradient and `0xFF9DB2AB`
  greys at `dashboard_widgets.dart:623-782` on a violet-black base). Unused
  legacy tokens: `darkHeroGradient`, `emeraldGradient`, `goldGradient` (0
  references); `darkSurface`/`darkBackground`/`lightBackground` used 3/4/1x.
  `app_tokens.dart:1-9` and `:36` still call emerald the brand/"§5".
- Radius: 15 x `circular(16)`, 11 x 14, 11 x 12, plus 20/22/26/18/10/3/4/2/8
  literal radii next to `AppRadius.bloom*`; `AppRadius.bloomChip=16` exists
  but the Dashboard chip uses 14 and the Detail chips use 17
  (`transaction_detail_screen.dart:1109/1166`; `AppRadius.bloomPill=17`
  exists but is bypassed).
- Spacing: `AppSpacing` (4-pt) is used only in the legacy core widgets;
  Bloom screens hard-code `EdgeInsets` 20/16/24/12/14/6/10 and
  `SizedBox(height: 24/16/12/…)` (e.g. `dashboard_screen.dart:36-41`).
- Hard-coded version string "Version 2.4.0" `settings_screen.dart:748`;
  `pubspec.yaml:4` is `0.1.10+2019`. A fabricated product claim.

### 2.5 Typography

- `AppTheme.bloomDisplay(size, weight)` (`app_theme.dart:23`) is called with
  literal sizes: 11 (10x), 12 (8x), 13 (5x), 15, 14; the streak chip uses 10
  and 12 (`dashboard_screen.dart:134/160`). Sizes below 12sp hurt legibility
  at default scale and clip at 2x. `bloomDisplay` fixes letter-spacing as a
  fraction of size and ignores `TextTheme`, so there is no named scale.
- Raw `TextStyle(fontSize: …)` still appears in `assistant_screen.dart:
  273-280` etc. (fontSize 12/16/18).
- Amounts: `BloomAmount` (`bloom_amount.dart`) exists; verify all rupee text
  goes through it (tabular figures per design-system.md "Foundations").
- Overflow risks: Dashboard chip clamps with `maxLines: 1, softWrap: false`
  at 10px (`dashboard_screen.dart:128-139`) but period label allows 2 lines
  next to a fixed width formula `width - 66` (`:197`); Trends header
  `Row` has three siblings and only the title column is `Expanded`
  (`insights_screen.dart:211-350`), so the two chips push the title at 2x text;
  `_TileRow`/Settings subtitles (`settings_screen.dart:810-860`) need
  `maxLines`/wrapping verification.

### 2.6 Cards and sections: duplicated styles

Every feature re-implements "card": `_TrendsInboxCard` (`insights_screen.dart:
592`), `_NarrativeInsightCard` (`:747`), `_SixMonthBarChartCard` (`:845`),
`_MoMComparisonCard` (`:1002`), Dashboard `_card()` helpers
(`dashboard_widgets.dart:565/976`), `_CommitmentsSummaryCard`
(`recurring_screen.dart:481`), `_AppBannerCard` (`settings_screen.dart:704`),
`_SortCard` (`weekly_review_screen.dart:1010`, radius 26), `_SettingsSection`
(`:766`). Fills differ (`bloomDarkCard` vs `bloomDarkTrack` vs `bloomChip`
vs `bloomCard`), radii differ (16/20/22/24/26), shadows come from three tokens
(`app_tokens.dart:184-202`). There is no `BloomCard`, `BloomSectionHeader`, or
`BloomChip` primitive.

### 2.7 Hand-rolled interaction recipe (15 copies)

`Semantics(button, label, selected, onTap) → ExcludeSemantics → GestureDetector
(opaque) → ConstrainedBox(48) → Container`. No ripple/pressed feedback, no
focus ring, no keyboard activation, and zero haptics anywhere
(`grep HapticFeedback lib` returns 0). One shared `BloomPressable` removes all
copies.

### 2.8 States: loading / empty / error

- `EmptyStateView` (`app_state_views.dart:8`) and `ListLoadingSkeleton`
  (`:116`) are used by no feature (0 references under `lib/features`);
  `ErrorStateView` by three (`transactions_screen`, `payment_sources_screen`,
  `card_source_audit_screen`). Features instead use bare strings:
  `payee_labels_screen.dart:154`, `payment_sources_screen.dart:39`,
  `not_transactions_screen.dart:40`, `assistant_screen.dart:587`,
  `card_source_audit_screen.dart:62/165`, `unparsed_sms_screen.dart:46`.
- 20+ bare `CircularProgressIndicator()` loading states (settings sub-screens,
  sms, recovery, `trends_history_screen.dart:142`) vs `BloomSkeleton` on 7
  screens: inconsistent and a layout jump on resolve.
- Raw exceptions shown to the user: `settings_screen.dart:395` `'Error: $err'`,
  `:514/586` `Export failed: $e`, `category_manager_screen.dart:163`,
  `transaction_detail_screen.dart:346`, `weekly_review_screen.dart:578/700/768`
  (`… $e`), `feature_flags_screen.dart:46`. Needs plain-language copy and a
  Retry; details to a "Show details" disclosure.
- Dev-only `loading: () => SizedBox.shrink()` (`unparsed_sms_screen.dart:70`)
  is silent.
- Dashboard cards each handle `.when` privately (`dashboard_widgets.dart:198,
  559, 961`); `valueOrNull ?? const []` at `:85`, `:1179` turns loading/error
  into empty, which violates design-system.md "Do not convert AsyncValue
  loading or error into an empty collection".
- Per-skeleton `AnimationController` (`bloom_skeleton.dart:34-50`,
  `app_state_views.dart:125-127`): N skeletons = N tickers, not phase-locked.

### 2.9 Motion, performance, flicker

- Animation use is nearly absent: 4 files use any implicit animation. No
  shared curves (`grep Curves.` = 8), no `AnimatedSwitcher` between skeleton and
  content, so loaded -> refreshing -> loaded can swap subtree types and flash.
- Leak/bug: `BloomBobController` (`bloom_motion.dart:19-37`) builds a throw-away
  second `AnimationController` inside the `CurvedAnimation` initializer
  (`:21-28`) that is never disposed, then reassigns `animation`. Every mascot
  instance (Dashboard header, Settings banner) leaks a ticker.
- Infinite animations never pause off-screen: mascot bob, Ask orb pulse
  (`home_shell.dart:677-701`, an `AnimatedBuilder` rebuilding a `Transform` +
  `Border` every frame on every tab), skeletons. Only 1 `RepaintBoundary` in
  scope.
- `DashboardScreen` is a plain `ListView(children: [...])` of ~10 sections
  built eagerly (`dashboard_screen.dart:35-300`); `TransactionsScreen` nests a
  `shrinkWrap` `ListView` in a `Column` for the empty/loading layout
  (`transactions_screen.dart:565-575`) and a `SliverList` for data (`:538`);
  the switch changes the tree shape.
- Only `Dismissible` rows (`transactions_screen.dart:1000`) have an `item.id`
  key; others do not.
- Full-width elevated shadows: `bloomSortCardShadow` blur 40 (`:191-197`) on
  large cards, and `bloomNavPillShadow` blur 28.

### 2.10 Dark-mode issues

- Onboarding has zero `isDark` branches and hard-coded light tints
  (`onboarding_screen.dart:100,139-165,280,357,369`): white-ish cards on the
  violet-black base in dark theme.
- Detail category chips `0xFF282346` / `0xFFF1EFFB`
  (`transaction_detail_screen.dart:1108`), sms_lookup status tints
  (`:342-390`) and recurring warning tints (`:499-600`) are per-screen
  light/dark pairs instead of tokens, so contrast is unverified.
- Dashboard hero mixes legacy greens (`dashboard_widgets.dart:623-782`).
- Assistant composer placeholder `0xFF6F6A92` and dividers `0xFF1E1B33` are
  single-mode (`assistant_screen.dart:212,454,501`).
- No automated contrast or golden checks (`grep matchesGoldenFile test` = 0).

### 2.11 Dashboard streak chip vs Settings (owner finding)

Where it sits: top-right of the Dashboard header row, after the mascot and the
greeting (`dashboard_screen.dart:48-165`). Why it reads as Settings (it
literally is):

1. It is the **only** navigation into Settings from the main shell:
   `SettingsScreen()` is pushed at `dashboard_screen.dart:95`, and the only
   other entry is the Ask sheet header (`assistant_screen.dart:810`). No gear,
   no tab.
2. Its semantics and tooltip say "Settings & Streak" / "Settings and N day
   streak" (`:87-90`), i.e. one control with two meanings.
3. Visually it is a gold pill with a flame (`:121-146`): a status badge, not
   a control; users tap it expecting a streak explanation and land on Settings.
4. In compact mode it collapses to "N d" at 10px (`:127-139`), unreadable.
5. Hard-coded colours (`0xFFFFF0D6`, `0xFF8A5A00`) instead of tokens.

Truthfulness defects (design-system.md "production UI must not present sample …
streaks as live"):

- `incrementStreak`/`setStreak` have **no callers** (`grep` shows only
  `app_settings.dart:184,220`), so the persisted streak never advances.
- `streakProvider` (`streak_provider.dart:9-21`) returns `1` whenever the
  review queue is empty even if never reviewed: a fabricated streak.
- `weekly_review_screen.dart:1477` falls back to `?? 6` (a sample number)
  in the inbox-zero view and renders "N day streak maintained!" (`:1543`).
- Test coverage is only the settings JSON round-trip
  (`test/features/shell/bloom_navigation_test.dart:256-265`).

### 2.12 Other findings

- `app_tokens.dart:266` cites "design-system.md §6" (illustration/icon rules)
  and `:36` "§5"; also `category_visuals.dart:14` "§6",
  `transaction_repository.dart:108`, `paisa_colors.dart:35`,
  `app_state_views.dart:7` cite "§5". `docs/design-system.md` has no numbered
  sections and no iconography section (headings: Principles, Foundations,
  Standard states, Feature migration contract, Future feature UX, Accessibility
  acceptance).
- `AppSizes.minTouchTarget` exists (`app_tokens.dart:233-239`) but there are no
  size tokens for icons, chips, tiles.
- Settings is one flat ListView of 8 shouting all-caps groups with a long dev
  section and a destructive full-width button at the end
  (`settings_screen.dart:84-400`, `:974-1050`); the profile (T-149a) will
  not fit.
- Ask is a bottom sheet on a floating orb (`home_shell.dart:660-725`), the nav
  pill has four tabs and no Settings.

## 3. Design

### 3.1 Icon system: `AppIcons` (+ `AppIcon`)

Decision: back the enum with the built-in rounded glyph set
(`Icons.*_rounded`, Material Symbols Rounded-equivalent, weight 400) first;
zero new dependency, tree-shakes, and keeps one switch point. If the owner
later wants the variable FILL axis (animated filled nav icons), swap the
`IconData` source inside `app_icons.dart` to `material_symbols_icons` without
touching call sites (needs a dependency/APK-size note and likely an ADR then).

API (`lib/core/theme/app_icons.dart`):

```dart
enum AppIconSize { inline(16), standard(20), large(24); final double px; }
enum AppIcons { search(Icons.search_rounded), ... ; final IconData data; }
class AppIcon extends StatelessWidget {
  const AppIcon(this.icon, {this.size = AppIconSize.standard, this.color,
      this.semanticLabel});     // null label => ExcludeSemantics (decorative)
}
IconData appIconData(AppIcons i);       // for IconButton/ListTile APIs
IconData categoryIconData(String? seedIconName); // string lookup, one source
```

Rules: features never import `Icons`; only `app_icons.dart` and
`category_visuals.dart` (which delegates) may. A test (T-204b) fails on any new
`Icons.` outside the allowlist. 16 = inline with text/meta/chips; 20 =
buttons, list leading, tile glyph (36dp tile); 24 = nav, app bar, hero actions.
Category tile glyph = 20 in a 36 tile, 24 in a 48 tile. Selected nav icon is
the filled variant (`home_rounded`) vs unselected outlined-rounded
(`home_outlined` has no rounded twin: use `AppIcons.homeOutline` mapped to
`Icons.home_outlined` explicitly and document the two exceptions below).

Mapping table (old -> `AppIcons` member -> glyph). "Symbols" is the Material
Symbols Rounded name, which is the intended phase-2 source.

| Semantic | Old (examples) | AppIcons | Glyph / Symbols name |
| --- | --- | --- | --- |
| close / dismiss | `close` x9 (`transactions_screen.dart:403`, `bloom_sheet_scaffold.dart:102`, `category_picker_sheet.dart:83`) | `close` | `close_rounded` |
| back | `arrow_back` (`bloom_sheet_scaffold.dart:79`) | `back` | `arrow_back_rounded` |
| search | `search` x6 | `search` | `search_rounded` |
| chevron | `chevron_right` x6 | `chevronRight` | `chevron_right_rounded` |
| dropdown | `keyboard_arrow_down_rounded` | `chevronDown` | same |
| check / confirm | `check`, `check_circle`, `check_circle_outline`, `verified_rounded` | `check`, `checkCircle` | `check_rounded`, `check_circle_rounded` |
| add | `add`, `add_rounded` | `add` | `add_rounded` |
| edit | `edit_outlined`, `edit_note_rounded` | `edit` | `edit_rounded` |
| copy | `copy`, `copy_rounded` | `copy` | `content_copy_rounded` |
| refresh / rotate | `refresh`, `refresh_rounded`, `restart_alt` | `refresh`, `reset` | `refresh_rounded`, `restart_alt_rounded` |
| calendar / period | `calendar_today_rounded`, `calendar_month_rounded`, `calendar_today_outlined`, `event` | `period` | `calendar_month_rounded` (one icon for all period chips) |
| recurring | `autorenew_rounded`, `repeat_rounded` | `recurring` | `autorenew_rounded` |
| settings | (none today) | `settings` | `settings_rounded` |
| streak | `local_fire_department_rounded` | `streak` | `local_fire_department_rounded` |
| home tab | `home_outlined`/`home_rounded` | `navHome`/`navHomeSelected` | `home_outlined` / `home_rounded` |
| activity tab | `receipt_long_*` | `navActivity`/`...Selected` | `receipt_long_outlined` / `receipt_long_rounded` |
| sort tab | `fact_check_*` | `navSort`/`...Selected` | `fact_check_outlined` / `fact_check_rounded` |
| trends tab | `insights_*` | `navTrends`/`...Selected` | `insights_outlined` / `insights_rounded` |
| ask | `auto_awesome` (`home_shell.dart:713`, 4 uses) | `ask` | `auto_awesome_rounded` |
| send | `arrow_upward_rounded` | `send` | `arrow_upward_rounded` |
| sms | `sms_outlined`, `sms_rounded`, `sms_failed_outlined` | `sms`, `smsFailed` | `sms_rounded`, `sms_failed_rounded` |
| wallet/source | `account_balance_wallet_outlined`, `credit_card` | `wallet`, `card` | `account_balance_wallet_rounded`, `credit_card_rounded` |
| label / tag | `sell_outlined` | `label` | `sell_rounded` |
| direction | `arrow_upward`, `arrow_downward` (`manual_entry_screen.dart:113/118`) | `debit`, `credit` | `arrow_upward_rounded`, `arrow_downward_rounded` |
| warning / info | `warning_amber_rounded`, `info_outline` | `warning`, `info` | `warning_rounded`, `info_rounded` |
| export | `file_download_outlined` | `download` | `download_rounded` |
| QR | `qr_code_2_rounded` | `qr` | `qr_code_2_rounded` |
| terminal (dev) | `terminal`, `terminal_rounded` | `terminal` | `terminal_rounded` |
| view toggle | `view_list_rounded`, `view_carousel_rounded` | `viewList`, `viewCards` | same |
| more | `more_horiz_rounded` | `more` | `more_horiz_rounded` |
| privacy/AI | `shield`, `smart_toy`, `cleaning_services`, `fact_check_outlined` | `privacy`, `model`, `clean`, `audit` | `shield_rounded`, `smart_toy_rounded`, `cleaning_services_rounded`, `fact_check_rounded` |

Category glyphs (`category_visuals.dart:44-366`): map every existing key to its
`_rounded` twin (`restaurant`->`restaurant_rounded`,
`local_grocery_store`->`local_grocery_store_rounded`,
`directions_car`->`directions_car_rounded`, `shopping_bag`, `receipt_long`,
`subscriptions`, `home`->`home_rounded`, `credit_card`, `local_hospital`,
`school`, `theaters`, `flight`, `swap_horiz`->`swap_horiz_rounded`,
`payments`, `request_quote`, `atm`, `trending_up`, `category`->
`category_rounded`; fallback `category_outlined` -> `category_rounded`).
Exceptions (no rounded twin in the framework): list them in a comment in
`app_icons.dart` and keep the outlined/plain glyph for those only
(`temple_hindu`, `smoking_rooms`, `sports_cricket` need a check at implementation
time; T-204j produces the definitive 1:1 table in its test).

Illustrations remain `AppIllustrations` PNGs for empty states/onboarding only.

### 3.2 Design-language refresh

Principles carried from design-system.md (calm, numbers first, one accent):
refresh adds structure, not decoration.

**Palette.** One palette: Bloom (violet ink surfaces + emerald/credit and gold
accents) as shipped on every feature screen. Delete the unreferenced legacy
gradients, route `ThemeData` through a single `BloomPalette` accessed as
`context.bloom` (extends `PaisaColors`, T-204d) so `isDark` ternaries
disappear. Add missing semantic roles instead of per-screen hex: `surfaceTint`
(warning/success/danger/info tints with on-colors for both brightnesses),
`scrim`, `onAccent`, `focusRing`. Verify AA contrast (4.5:1 text, 3:1 icons)
for every pair in a unit test. Legacy `emerald` themes remain only if the app
still exposes a "legacy" choice; check `AppThemeChoice` and delete otherwise.

**Typography.** Named scale in `bloom_typography.dart` (SpaceGrotesk for
display/numbers, system sans for body is NOT introduced; keep SpaceGrotesk):

| Role | Size/weight | Use |
| --- | --- | --- |
| `numericHero` | 40 / w700, tabular | hero amount |
| `title` | 22 / w700 | screen title |
| `section` | 17 / w600 | card/section header (Semantics header) |
| `body` | 15 / w500 | rows, primary text |
| `label` | 13 / w600 | chips, buttons |
| `caption` | 12 / w400 | meta; 12 is the floor, no 10/11 |

All via `MediaQuery.textScaler`; any row with a trailing amount must lay out
at 2x on 320dp (wrap, then ellipsise secondary text, never the amount).

**Spacing and radius.** Use 4-pt `AppSpacing` everywhere (add `AppSpacing.screenH
= 20`, `sectionGap = 24`, `cardPad = 16`); radii only from `AppRadius`:
chip 16, row 20, card 24, hero 26, sheet 30; delete literal 12/14/17/22.
Prefer `Gap`-style `SizedBox` consts via helpers.

**Elevation.** Three levels, tonal first (better in dark mode, cheaper to paint):
`flat` (surface fill + hairline), `raised` (one step lighter fill, no shadow),
`floating` (nav pill, Ask orb, toasts, sheets: shadow, blur <= 24). Remove the
blur-40 card shadow (`app_tokens.dart:191-197`) from `_SortCard` in favour of
`raised` + a short, cached shadow only on the top swipe card.

**Motion.** `AppMotion` replaces ad-hoc durations (`app_tokens.dart:249-258`):

| Token | Value | Use |
| --- | --- | --- |
| `instant` | 90ms, `easeOut` | press scale, toggles |
| `fast` | 150ms, `easeOutCubic` | chip select, crossfade skeleton->content |
| `standard` | 250ms, `Cubic(.2,0,0,1)` | expand, sheet content, route fades |
| `emphasized` | 400ms, `Cubic(.2,0,0,1)` | streak pop, ring fill (once) |

Rules: nothing > 400ms; list rows never animate on data rebuild; a single
shared `Ticker` drives all shimmers (phase-locked); infinite animations
(mascot bob, Ask pulse) pause via `TickerMode`/visibility when the tab is not
visible and stop under `disableAnimations`; every card is a `RepaintBoundary`.
Page transitions: shared-axis fade-through for tab switches (no slide), default
Android predictive back for pushed routes (T-167j contract).

**No-flicker contract.** (1) Providers keep the previous value while a refresh
is in flight (`AsyncValue.when(skipLoadingOnRefresh: true,
skipLoadingOnReload: true)` or `valueOrNull` + `isLoading` flag), so a loaded
list never returns to skeleton; (2) skeleton and content share exact heights
(`BloomCard` min-height per card spec) and swap with a 150ms `AnimatedSwitcher`
keyed by state kind, not by data; (3) stable `ValueKey(id)` on list rows;
(4) first-frame data comes from the existing providers' cache, no `Future` in
`build`; (5) the Activity list keeps one sliver tree for loading/empty/data.
This extends T-203 (flicker).

**Haptics.** `AppHaptics` (`lib/core/theme/app_haptics.dart`) wraps
`HapticFeedback`, respects an Appearance toggle "Haptic feedback" (default on)
and `disableAnimations`-independent: `selection` (chip, tab, segmented, picker
row), `light` (confirm in Sort, swipe commit), `medium` (long-press, undo),
`heavy` never. Destructive confirm dialogs use `medium` on the confirm only.
Never haptic on scroll, data refresh, or error toasts.

**Shared primitives** (new, `lib/core/widgets/bloom/`): `BloomPressable`
(semantics + 48dp hit + ripple/scale + focus + keyboard + haptic),
`BloomChip` and `BloomPeriodChip` (one spec: 36dp visual, 48dp hit, 16dp icon,
`label` text, radius 16, chevron, `selected` state), `BloomCard` (variants
`flat/raised/tinted(role)/hero`, padding/radius from tokens),
`BloomSectionHeader` (`Semantics(header)`, optional trailing action 48dp),
`BloomStateView` (loading/empty/error/filter-empty, built on
`app_state_views.dart`), `BloomShimmerScope`.

### 3.3 Per-screen redesign briefs

Common acceptance for every screen: renders at 320x568 and 360x800, text scale
1.0 and 2.0, light and dark, with no overflow exception; all controls >= 48dp
with `Semantics` label/role; loading/empty/error/filter-empty via
`BloomStateView`; no raw `Icons.*`, no `Color(0x…)`, no literal radii; no
skeleton flash on refresh. All existing capabilities remain (design-system.md
"Feature migration contract").

**Dashboard** (`lib/features/dashboard/`). Header: mascot + greeting on the
left; right side has a **Settings gear `IconButton` (48dp, `AppIcons.settings`,
tooltip "Settings")** and nothing else; the streak moves into the body as a
`StreakBadge` (3.4). Period: `BloomPeriodChip` on its own row aligned
left, with "Compare" slot reserved. Body becomes an **adaptive card grid**:
`DashboardCardSlot` (shell: `BloomCard`, header with title + optional action,
loading/error/empty slots, fixed min-height per spec) laid out by
`DashboardCardGrid`: 1 column below 600dp, 2 columns 600-840dp with spans,
3 above, landscape-compact uses 2 narrow columns; each card declares
`span` (1 or full), `minHeight`, and a stable id. Cards today: Hero ring +
metric pills, Budget, Source currency activity, Top categories, Insight,
Today list, Exclusions note. T-207 adds ordering/visibility persistence on top
of the same `DashboardCardSpec{id, span, builder}` (`id` is the `card_type` of the T-207 registry in `docs/plans/intelligence-v2.md`; T-207 adds default rank, eligibility predicate and persisted layout per its ADR 0035, and reserves skeleton height per card, which `minHeight` here provides); T-204 must not add
reorder UI. Implementation uses a sliver list of row groups (no eager
`ListView(children)`), `RepaintBoundary` per card, hero ring painted once and
re-animated only on period change. Wrap-up: Exclusions note becomes a
collapsed footer card.

**Activity** (`transactions_screen.dart`). Sticky search + filter row
(`BloomChip`s with counts), sticky date group headers with day net, rows 56dp
min with category tile 36, merchant, amount right-aligned via `BloomAmount`,
subtle status dot for needs-review; swipe actions keep their visible
alternative (row menu). One sliver tree across states; filter-empty state with
"Clear filters". Pull-to-refresh keeps the list. Pagination footer is a
non-jumping 48dp row.

**Sort / Review** (`weekly_review_screen.dart`, `review_list_row.dart`).
Card mode: a single raised swipe card with category suggestions as 48dp
chips, an evidence line, large Confirm/Skip/Not-a-transaction actions (already
48+; unify through `BloomPressable`), progress as a segmented bar with a count
label; list mode: dense rows with bulk select. Undo toast uses `AppMotion`.
Inbox-zero view: honest streak (3.4), "Next review" summary, link to Trends.
Haptic `light` on confirm, `selection` on category pick.

**Transaction detail** (`transaction_detail_screen.dart`, `detail/*`; after
T-156c/T-158b/c). Header with amount (`numericHero`), merchant, direction chip;
sections as `BloomCard` blocks: Category (chips -> `CategoryPickerSheet`),
Details, Evidence (collapsed original SMS, "Technical details" disclosure),
Recurring, Actions. Category chips use `BloomChip` (selected state, tokens,
48dp). Sheet presentation follows the T-156c/T-176 inset contract.

**Trends** (`insights_screen.dart`, `trends_history_screen.dart`). Header: title
+ subtitle on one row, `BloomPeriodChip` (identical to Dashboard) on a second
row with a Recurring `BloomChip` (icon+label, 48dp, wraps below at large
text). Cards: summary narrative, six-month bars (keep the custom bars, add
semantic summary), MoM, categories, merchants, inbox. History filters become
`BloomChip` rows (Status / Month / Type) with tokenised selected colour
(currently `violetPrimary` + `Colors.white`, `trends_history_screen.dart:
312-330`).

**Ask** (`assistant_screen.dart`; with T-151b/d/e). Composer: 48dp send
`BloomPressable` with label "Send question", disabled state when empty, `ime
action send`; placeholder/divider colours from tokens. "Try asking" rotate
control gets its 48dp box (remove the 32dp clip). Bubbles per T-151b,
thinking/no-model states per T-151d, charts/follow-ups per T-151e. Settings
shortcut in the sheet header uses `AppIcons.settings`.

**Settings** (`settings_screen.dart` + sections; with T-149a profile). Hub
layout: profile/status header card (replaces "PaisaTrack Bloom / Version 2.4.0";
version read from build info, not a literal), a search field (filters rows),
then grouped `BloomCard` lists with `BloomSectionHeader` (sentence-case, not all
caps) in this order: Data & backup, Capture (SMS), Categories & learning,
Appearance, AI, Privacy; "Developer" tools stay reachable as a collapsed group (no capability removed);
"Delete all local data" in its own danger card at the bottom with confirm.
Every row: icon tile 36 (20 glyph), title, one-line subtitle (max 2 lines),
chevron; 48dp+.

**Onboarding** (`onboarding_screen.dart`). Dark-mode correct, three paged
steps instead of one scroll (Promise: on-device & private; What we read: SMS
permission explanation; Ready: first scan), page indicator, one primary CTA per
step; illustrations from `AppIllustrations` (<=120dp); all colours from
`context.bloom` tints.

**Category picker** (`category_picker_sheet.dart`). Search at top (sticky),
"Suggested" and "Recent" chips (from deterministic engine; never invented),
then groups with 36dp category tiles, selected row shows `AppIcons.check`;
two-column grid for top-level at width >= 360, list when text scale >= 1.5;
48dp rows; haptic `selection`; filter-empty state with "Create category".

**Recurring** (`recurring_screen.dart`). Summary card (monthly commitments via
`BloomAmount`), "Upcoming" timeline grouped by week, series rows with cadence
chip and status chip from tokens (replace 22 hex values), unmark action as a
48dp trailing `IconButton` in the row, empty state with explanation of how a
series is detected.

### 3.4 Streak chip redesign

1. Header trailing control = Settings gear (separate 48dp `IconButton`).
2. `StreakBadge` is a non-navigating, gold-tinted status pill placed under the
   greeting subline or as the first element of the Today card: flame
   `AppIcons.streak` 16 + "N-day streak" (`label`), `Semantics(label: "N day
   review streak")`; tapping opens a small `BloomSheet` explaining "Days in a
   row with an empty Sort inbox" and showing best streak; no Settings link.
3. Show the badge only for N >= 2; otherwise a
   quiet "Sort inbox to start a streak" hint when there is review work, or
   nothing at inbox zero. Never shown as a placeholder number.
4. Honest data: a pure `StreakCalculator.advance(prev, today, inboxZeroToday)`
   (local dates) persisted in `AppSettings` (`streak`, `streakBest`,
   `lastStreakDay`); advances on app resume and on the review queue reaching 0;
   resets to 0 when a local day passes with pending items; `weekly_review_screen`
   `?? 6` becomes `?? 0`. Tests under `TZ=America/New_York` and
   `Asia/Kolkata`, DST day, backdated clock.
5. Compact layouts: icon + number only ("7") with semantics giving the full
   phrase; min text 12.
6. Owner question (non-blocking): keep streak at all? Default: yes, honest and
   quiet; feature flag `streakBadge` (default on) for instant rollback.

### 3.5 Golden and regression strategy

Existing: zero goldens (`grep matchesGoldenFile test` = 0); T-167h and T-168d
already plan goldens, so this plan supplies the harness and component goldens
and lets those tasks consume it.

1. `test/support/golden_harness.dart`: `pumpGolden(tester, widget, {size,
   textScale, brightness, locale})` wrapping `MaterialApp` with the real
   `AppTheme`, loads SpaceGrotesk via `FontLoader` from the asset bundle (no
   network), disables animations, fixed `DateTime`/`ProviderScope` overrides.
2. Goldens only for deterministic leaf widgets and a small set of screens:
   `BloomChip`/`BloomPeriodChip`, `BloomCard` variants, `StreakBadge`, state
   views, nav pill, `DashboardCardSlot`, then Dashboard, Activity, Sort,
   Settings at 360x800 light/dark and 320x568 @2x text (screens are owned by
   T-168d/T-167h; they use this harness).
3. Goldens live in `test/goldens/<area>/`; tagged `@Tags(['golden'])`; run
   on the Linux CI image only (`flutter test --tags golden`); local
   contributors skip with `--exclude-tags golden`; update via `--update-goldens`
   with the diff reviewed in the PR.
4. Behavioural tests do the heavy lifting: tap-target guideline
   (`meetsGuideline(androidTapTargetGuideline)` and `labeledTapTargetGuideline`)
   on every redesigned screen; `textContrastGuideline` for light and dark;
   a text-scale sweep test (T-204am) pumping every root screen and sheet at 320x568,
   2.0x, both themes asserting `tester.takeException() == null`.
5. Static guards: `icon_usage_guard_test` (no `Icons.` outside allowlist),
   `token_guard_test` (no `Color(0x` / `Colors.white` / literal radius in
   `lib/features` outside allowlist that shrinks to zero), run in the normal
   `flutter test`.
6. Flicker test: widget test that overrides a provider to emit
   `AsyncData -> AsyncLoading.copyWithPrevious(prev) -> AsyncData` and asserts
   `BloomSkeleton` is never in the tree after first data (Dashboard, Activity,
   Trends).

## 4. Required edits to `docs/design-system.md`

(This task does not edit it; T-204ao applies these.)

1. Keep sections named, not numbered (orchestrator decision 2026-10-10;
   `app_tokens.dart` already cites "Foundations" and "Iconography", and an
   Iconography section exists). Add a named "Money colour and amounts"
   section (move the debit/credit and neutral-transfer rules there) and point
   the remaining "§5"/"§6" comments (`paisa_colors.dart:35`,
   `transaction_repository.dart:108`, `app_state_views.dart:7`,
   `category_visuals.dart:14`) at section names.
2. Iconography: one family (Rounded); sizes 16/20/24 only; `AppIcons` is the
   only import point (features must not import `Icons`); outlined/filled pair
   only for nav selected state; decorative icons excluded from semantics,
   meaningful icons carry a label; icon colour from role (not money colours);
   category glyph lookup via `categoryIconData`; illustrations PNG only as
   48-120dp heroes in onboarding/empty states (moves `app_tokens.dart:262`
   rule here). Include the mapping table from this plan.
3. §2 Foundations: add palette decision (Bloom), type scale table, spacing/
   radius scales, elevation levels, motion tokens, haptics policy, minimum text
   12sp, `context.bloom` accessor rule ("no `isDark` ternaries or hex in
   features").
4. §3 Standard states: name `BloomStateView` kinds and the no-flicker contract
   (keep previous value on refresh, equal-height skeletons, 150ms crossfade).
5. New §9 Components: `BloomPressable`, `BloomChip`/`BloomPeriodChip` (identical
   on Dashboard and Trends), `BloomCard`, `BloomSectionHeader`, `DashboardCard
   Slot`, `StreakBadge`; each with spec, states, semantics.
6. §8 Accessibility: add 2x text at 320dp matrix, tap-target and contrast
   guidelines as required tests, ban `ExcludeSemantics`+`GestureDetector`
   hand-rolled buttons.
7. Add: "Streaks and other gamified numbers must be derived from persisted
   events; never default to a sample number; separate status badges from
   navigation controls."
8. Fix wording that points to `PaisaColors` as the only colour source; point to
   `context.bloom`.

## 5. Constraints and invariants

- No schema change; `AppSettings` additions (`streakBest`, `lastStreakDay`)
  are JSON-in-prefs with defaults (check backup export includes/ignores them
  and the delete-everything reset clears them; T-204o test).
- No new network use or dependency (icons use the built-in font).
- ADR 0011: no UI copy introduces financial claims; suggestions in the
  category picker come from existing deterministic ranking only.
- Existing keys used by tests (`dashboard_streak_count`, `dashboard_period_
  label`, `assistant_send_button`, `assistant_prompt_chip_rotate`) are
  preserved or updated in the same task with its tests.
- T-176/T-167f bottom-inset contract (`BloomBottomInset.contentPadding`) is
  consumed unchanged.
- Touching a screen file: run GitNexus `impact` on its widget symbols first;
  report HIGH/CRITICAL to the orchestrator before editing.

## 6. Integration with open tasks

| Open task | How T-204 integrates |
| --- | --- |
| T-128, T-167d | `BloomPressable`/`BloomChip` replace the 15 hand-rolled button recipes; T-167d's scope is satisfied by T-204e/f and screen tasks; do not duplicate |
| T-167c/g/h/i | T-204am is the text-scale/guideline sweep; T-167g viewport variants and T-167h goldens reuse T-204m harness; T-167i sheets use the inset contract in T-204n/ac |
| T-168c/d | T-204k/l route sheets via Bloom helpers; goldens via T-204m |
| T-151b/d/e | T-204ac only restyles composer/header/tokens; bubble geometry/states/charts stay in T-151x (T-204ac depends on T-151b if it lands first) |
| T-149a-c | T-204ad leaves a profile-header slot; T-149a fills it |
| T-156c, T-158b/c | T-204z/aa start only after T-158c; they restyle, not restructure |
| T-176 | consumed, not changed |
| T-207 | T-204q/s provide `DashboardCardSlot`/`DashboardCardGrid`/`DashboardCardSpec`; T-207 adds ordering/visibility persistence |
| T-203 (flicker) | no-flicker contract in 3.2 is the UI half |

## 7. Risks

- Visual churn across 83 files: mitigated by token/primitive tasks landing
  first and per-folder ownership; guards (icon/token tests) with shrinking
  allowlists keep partial migrations safe.
- Rounded glyph gaps (a few icons have no `_rounded` twin): documented
  exceptions in `app_icons.dart`; swap to `material_symbols_icons` is a
  one-file change.
- Golden flakiness across hosts: Linux-CI-only tag, bundled font, no
  animations, tolerance comparator capped at 0.1%.
- Redesign regressions in Sort/Detail (largest files): extract-first tasks
  (T-204r, T-204x) are move-only with characterization via existing tests.
- Streak honesty may expose that most users have streak 0: badge hidden
  below 2; feature-flagged.
- Two `AppSettings` writers (streak advance vs settings controller) race:
  single-writer in `StreakController`, covered by a test.

## 8. Rollout / flags

Primitives and tokens land first with no visible change. Screen redesigns land
one at a time; Dashboard card grid and new Settings hub behind
`uiV2Dashboard` / `uiV2Settings` flags (default on after dogfood; flag removed
once golden suite is green for two releases). `streakBadge` flag as above.

## 9. Open owner questions

None blocking. Non-blocking defaults chosen: built-in rounded icon font (not
the `material_symbols_icons` package); Bloom palette stays; streak kept but
honest and hidden below 2 days; haptics default on.

## 10. Subtask table

See [T-204 briefs](../tasks/T-204.md) for the full text. Parallel groups touch
disjoint files; a group starts when its dependencies finish.

| ID | Title | Size | Model | Depends | Group |
| --- | --- | --- | --- | --- | --- |
| T-204a | `AppIcons` enum + `AppIcon` widget | S | Sonnet | — | A |
| T-204c | Motion/elevation/size tokens in `app_tokens.dart` | S | Sonnet | — | A |
| T-204d | `context.bloom` palette accessor + semantic tints | M | Sonnet | — | A |
| T-204e | `BloomPressable` + `AppHaptics` | M | Sonnet | — | A |
| T-204i | Fix mascot ticker leak, pause offscreen animations | S | Haiku | — | A |
| T-204m | Golden harness | S | Sonnet | — | A |
| T-204o | Honest streak logic + `StreakCalculator` | M | Sonnet | — | A |
| T-204b | Icon/token guard tests | S | Haiku | a | B |
| T-204f | `BloomChip` + `BloomPeriodChip` | M | Sonnet | a,c,d,e | B |
| T-204g | `BloomCard` + `BloomSectionHeader` | M | Sonnet | c,d | B |
| T-204h | `BloomStateView` + shared shimmer | M | Sonnet | a,c,d | B |
| T-204j | `category_visuals` -> `AppIcons` | M | Sonnet | a | B |
| T-204k | Migrate `core/widgets/bloom` sheets/toast/notice | S | Haiku | a,d | B |
| T-204l | Migrate core filter/transaction widgets | S | Haiku | a,d | B |
| T-204p | Header gear + `StreakBadge` | M | Sonnet | a,f,o | C |
| T-204q | Dashboard card shell + adaptive grid | M | Sonnet | g,h | C |
| T-204r | Split `dashboard_widgets.dart` (move-only) | S | Sonnet | — | C |
| T-204x | Split `weekly_review_screen.dart` (move-only) | S | Sonnet | — | C |
| T-204ab | Trends redesign | M | Sonnet | f,g,h | C |
| T-204ac | Ask restyle | M | Sonnet | f,e,a | C |
| T-204ad | Settings hub redesign | M | Sonnet | g,h,a | C |
| T-204ae | Settings subscreens A | S | Haiku | a,h | C |
| T-204af | Settings subscreens B | S | Haiku | a,h | C |
| T-204ag | Onboarding redesign | M | Sonnet | d,g | C |
| T-204ah | Recurring redesign | M | Sonnet | d,f,g,h | C |
| T-204ai | SMS lookup + permission card | M | Sonnet | d,a,g | C |
| T-204aj | Recovery + unreadable SMS migration | S | Haiku | a,d,h | C |
| T-204ak | Manual entry/correction/source actions | S | Haiku | a,d | C |
| T-204al | Home shell nav + Ask orb | M | Sonnet | a,e,i | C |
| T-204n | Category picker redesign | M | Sonnet | j,f,h | C |
| T-204s | Dashboard screen recomposition | M | Sonnet | p,q,r | D |
| T-204t | Hero + metrics cards | M | Sonnet | q,r | D |
| T-204u | Budget + source-currency cards | M | Sonnet | q,r | D |
| T-204v | Categories + insight + today cards | M | Sonnet | q,r | D |
| T-204w | Activity redesign | M | Sonnet | f,g,h,e | C |
| T-204y | Sort redesign | M | Sonnet | x,e,f,o | D |
| T-204z | Detail screen restyle | M | Sonnet | f,g,T-158c | D |
| T-204aa | Detail widgets restyle | S | Haiku | d,a,T-158c | D |
| T-204am | Text-scale/guideline sweep | M | Sonnet | all screens | E |
| T-204ao | Apply `design-system.md` edits | S | Haiku | a,c,d,f,g,h | E |
