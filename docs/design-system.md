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

| Role | Dark | Light | Usage |
|---|---|---|---|
| Background | `#0B1210` | `#F6FAF8` | Scaffold |
| Surface | `#141D1A` | `#FFFFFF` | Cards, nav bar |
| Surface raised | `#1B2724` | `#EEF5F2` | Chips, elevated tiles |
| Primary (emerald) | `#34D399` | `#0E9F6E` | CTAs, active nav, selection |
| Accent (gold) | `#E8B54D` | `#E8B54D` | Insight highlights, achievements — sparingly |
| Info (royal blue) | `#3B82F6` | `#3B82F6` | Informational accents (matches illustration tiles) |
| Credit | `#3DDC97` | `#0E9F6E` | Received amounts only |
| Debit | `#F48A8A` | `#D64545` | Spent amounts only |
| Warning | `#FBBF24` | `#B45309` | needs_review, degraded permission, price creep |
| Error | `#F87171` | `#DC2626` | Failures only |

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

| Role | Size/weight | Usage |
|---|---|---|
| Hero amount | 32 / w700, tabular | Dashboard month net |
| Card amount | 20 / w600, tabular | Summary cards, list trailing amounts |
| Screen title | 22 / w700, -0.3 tracking | AppBar |
| Body | 16 / w400 | Explanations, notices |
| Secondary | 14 / w400, `onSurfaceVariant` | Subtitles, timestamps |
| Label/chip | 12 / w500 | Chips, nav labels, section headers (UPPERCASE +0.5 tracking optional) |

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
