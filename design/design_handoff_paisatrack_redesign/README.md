# Handoff: PaisaTrack redesign (Bloom + Pulse)

## Overview
A full visual and UX redesign of PaisaTrack, the on-device SMS-based expense tracker (Flutter, repo `KrShivay/PaisaTrack`, branch `main`). Ten screens are redesigned around a single hero question — *can I spend today?* — replacing a dense number-first dashboard with one clear answer, a category ring, and a plain-English sentence next to every figure.

Design goals set by the product owner:
- "Too boring, only numbers visible" -> every figure is paired with one human sentence; charts explain rather than decorate.
- "Less text" -> copy is short, warm, second-person; no paragraph blocks in the app UI.
- "Too many clicks" -> categorising is a swipe, filters are chips, bulk actions apply to a whole merchant at once.
- "Navigation and exit not planned" -> four fixed tabs, swipe sideways between tabs, swipe down to dismiss every sheet, no screen without an exit, destructive actions undo from a toast instead of a confirm dialog.

## About the Design Files
The files in this bundle are **design references created in HTML** — streaming prototypes that show intended look, layout, and behavior. They are **not production code to copy**. The task is to **recreate these designs in PaisaTrack's existing Flutter environment**, using its established patterns: `AppColorTokens` / `PaisaColors` theme extensions, `AppSpacing` / `AppRadius` / `AppDurations` tokens, `CategoryVisuals` for per-category hue + Material icon, `formatInr` / `formatTxnTime` / `formatDateGroup` for formatting, Riverpod providers under `lib/features/*`, and Material 3 widgets.

Where the mock shows a glyph like ◍ / ✦ / ◎ / ✳, that is a **placeholder for a Material icon** (use `CategoryVisuals.icon()` for categories; `Icons.auto_awesome` for insight sparkles; `Icons.bolt`/`Icons.chat_bubble` for the Ask action). No SVG illustration in the mocks is final art — the app's existing `assets/icons/*.png` illustrations should be used for onboarding/empty-state heroes per `AppIllustrations`.

## Fidelity
**High-fidelity.** Colors, type sizes, weights, radii, spacing, and copy are final and should be matched closely. Motion specs are given below. Layout is specified at iPhone 402 x 874 logical px; scale by the 4pt spacing scale for other sizes.

## Design Tokens

### New brand palette (replaces emerald-primary; emerald is retained as the *money/positive* accent)
| Token | Hex | Use |
| --- | --- | --- |
| violet/primary | `#6D5AE6` | primary actions, mascot, links, selected chips |
| violet/primaryDark | `#4F3FC4` | pressed primary, text on tinted violet |
| violet/light | `#A78BFA` | gradient partner, subscriptions category |
| ink | `#1B1830` | primary text, nav pill, dark buttons, dark sheets |
| ink/secondary | `#5B5580` | body text on light |
| ink/tertiary | `#7A7596` | captions, metadata |
| ink/quaternary | `#8E88AD` | disabled/nav inactive |
| surface/base (light) | `#FBFAFF` | screen background |
| surface/sunken (light) | `#F3F1FC` | settings / sort background |
| surface/card (light) | `#F6F4FE` | list rows, inset cards |
| surface/chip (light) | `#F1EFFB` | unselected chips, icon buttons |
| hairline (light) | `#EFECFA` | 1px dividers |
| surface/base (dark) | `#0E0C1A` | screen background |
| surface/card (dark) | `#191630` | rows, bubbles, nav pill |
| outline (dark) | `#2E2A4E` | 1px borders on dark |
| track (dark) | `#241F3E` | unfilled progress track |
| emerald | `#34D399` | positive money, Ask orb, budget fill |
| emerald/deep | `#0E9F6E` / `#0E7A56` | orb gradient end, credit text on light |
| gold | `#E8B54D` | insight highlights, committed-money slice, streak |
| credit (light/dark) | `#12A46C` / `#34D399` | money in |
| debit (light/dark) | `#B4322F` / `#F48A8A` | money out |
| warning | `#8A5A00` on `#FFF7E4`, border `#F3D9A0` | needs-review / price creep |

Category hues are **unchanged** from `lib/core/theme/category_visuals.dart` (food `#F97316`, groceries `#84CC16`, transport `#38BDF8`, shopping `#E879F9`, bills `#FACC15`, subscriptions `#A78BFA`, rent `#2DD4BF`, EMI `#FB7185`, health `#4ADE80`, education `#60A5FA`, entertainment `#F472B6`, travel `#22D3EE`, transfers `#94A3B8`, income `#34D399`, fees `#F59E0B`, cash `#A8A29E`, investments `#E8B54D`, other `#9CA3AF`). On light surfaces, category tints use a 12–18% alpha wash (e.g. food tint `#FFE7D3`, icon color `#C2410C`); on dark, `color.withValues(alpha: 0.18)` tint with the full-strength hue as icon color.

### Typography
- Display / UI: **Space Grotesk** (fallback: system sans). Weights 400/500/600/700.
- Numerals: **IBM Plex Mono** 500/600, `letter-spacing: -0.03em` to `-0.05em` — every rupee amount, date number, percentage, and counter is mono.
- Scale used: 46/27/24/22/19/16/15/14/13/12/11/10 px. Headings use `letter-spacing: -0.02em` to `-0.035em`. Hero amount 42px/600 mono; card amounts 30–40px mono; row amounts 15px mono; captions 11–12px.
- Body copy uses `text-wrap: pretty` equivalent (avoid orphan words); line-height ~1.5 for sentences.

### Spacing / radius / motion
- Spacing: existing 4pt scale (4, 8, 12, 16, 24, 32). Screen padding 20px horizontal. Card padding 16–22px. Row gap 8–9px, section gap 18–22px.
- Radius: chips 15–17px (pill), rows/cards 20–24px, hero cards 24–26px, ring 50%, bottom nav pill 32px, sheets 30px top corners, icon tiles 12–13px, small buttons 16–19px.
- Shadow: nav pill `0 12px 28px rgba(27,24,48,0.28)`; sort card `0 18px 40px rgba(27,24,48,0.12)`; Ask orb glow `0 10px 24px rgba(52,211,153,0.35)`.
- Motion: mascot bob `translateY 0 -> -4px`, 3s ease-in-out infinite. Ask-orb pulse ring: `scale(1) opacity .55 -> scale(1.4) opacity 0`, 2.6s ease-out infinite. Tab change 250ms (`AppDurations.standard`), chip/state change 150ms (`AppDurations.fast`). Swipe-card fly-out 220ms ease-out with 8deg rotation. Respect reduce-motion: drop bob, pulse, and fly-out rotation.

## Navigation model (implement first — it changes `home_shell.dart`)
- Four fixed destinations, renamed for plain speech: **Home**, **Activity** (was Transactions), **Sort** (was Review), **Trends** (was Insights).
- Nav is a **floating pill**, 64px tall, inset 20px from screen edges, 30px above the bottom safe area: `#1B1830` on light, `#191630` + 1px `#2E2A4E` on dark. Four icon+label items (17px icon, 9px label, 2px gap) left-aligned in a row with 22px gaps; a 48px **Ask orb** (radius 24, emerald gradient `#34D399 -> #0E9F6E`, ink glyph, pulsing ring) sits at the right end.
- The orb opens **Ask PaisaTrack** as a full-height sheet — it is not a fifth tab.
- Tab switching also happens via horizontal swipe on the body (`PageView` with `IndexedStack`-like state retention). Tab state persists per tab; back gesture inside a tab pops that tab's own stack, never the shell.
- Every secondary screen (Recurring, Transaction detail, Category picker, Settings sub-pages) is a **draggable sheet** with a 44x5 grab handle, dismissible by swipe-down; each also has a visible `←` at top-left. No screen may be reachable without an exit affordance.
- Destructive actions (erase data, delete transaction, cancel subscription tracking) execute immediately and show a 10-second **undo toast** instead of a confirm dialog.

## Screens / Views

### 01 Onboarding — `lib/features/onboarding/onboarding_screen.dart`
- **Purpose**: get SMS permission by explaining the trade honestly, in one screen.
- **Layout**: full-bleed violet gradient block on the top 44% (`linear-gradient(172deg, #6D5AE6 0%, #8B6FF0 44%)`), `#FBFAFF` below. 24px horizontal padding. Column: mascot -> headline -> three benefit rows -> progress row -> CTA stack.
- **Mascot**: 92x92, radius 34, `rgba(255,255,255,0.18)`, two 9px white dots as eyes (gap 9px), bob animation + one pulsing ring border `rgba(255,255,255,0.45)`. In Flutter, use the existing `AppIllustrations.smsRefresh`/`appIcon` art if preferred, but keep the bob.
- **Headline**: 27px/700, `-0.03em`, white, two lines: "I can read your bank / texts so you don't". Sub: 14px `#E2DCFF`, max 272px: "Everything stays on this phone. No account, no upload, no ads."
- **Benefit rows**: 16px padding, radius 22, 34px icon tile (radius 12). Row 1 `#F6F4FE` / tile `#E4DEFF` / icon `#4F3FC4` — "Reads only money texts" + "OTPs and personal messages are skipped entirely." Row 2 `#F1FBF6` / `#D3F2E4` / `#0E7A56` — "Works offline, forever" + "Parsing and answers run on-device." Row 3 `#FFF7E4` / `#F7E5BE` / `#8A5A00` — "Ready in about 20 seconds" + "We'll read the last 6 months so today has context." Titles 14px/600, subs 12px `#7A7596`.
- **Progress**: 6px track `#E4DEFF` inside a `#F6F4FE` 18px-radius row, fill 34% violet gradient, mono label "1 of 3".
- **CTA**: 54px full-width pill `#1B1830`, white 15px/600 — "Allow SMS access". Below, plain text button `#7A7596` 13px — "I'll add things myself".
- **States**: permission denied -> the same screen with the gold row replaced by a warning row (`#FFF7E4`, `#8A5A00`) reading "Android is blocking us — open Settings > Apps > PaisaTrack > SMS", CTA becomes "Open settings". Import progress replaces the progress row with a live count ("412 of 1,240 texts read").

### 02 Home — `lib/features/dashboard/dashboard_screen.dart` + `dashboard_widgets.dart`
- **Purpose**: answer "can I spend today?" in under a second, then explain.
- **Layout**: header row (36px mascot + greeting + streak chip) -> scrollable body (20px padding, 20px section gaps) -> floating nav pill.
- **Header**: mascot 36px circle, violet gradient, two 4px white dots, bob. Greeting 15px/600 "Hey Shivay"; sub 11px `#7A7596` — a *live* line ("Lighter week than usual", "Two texts came in while you were out"). Streak chip: 32px pill `#FFF0D6` / text `#8A5A00` 12px/600 "6 day streak" (dark: `rgba(232,181,77,0.16)` / `#E8B54D`).
- **Hero ring**: 230px circle. Ring is a conic gradient of category shares in descending order, remainder `#E7E4F5` (light) / `#241F3E` (dark) — in Flutter draw with a `CustomPainter` sweeping arcs (stroke width 25, no gaps, butt caps) using `CategoryVisuals.color`. Inner 180px circle in the surface color holds: 11px/600 uppercase `#7A7596` label "SAFE TODAY" (`0.1em` tracking), 42px/600 mono amount "₹1,240" (`-0.04em`), 12px/600 credit-colored delta "₹310 more than yesterday".
- **Metric switcher**: four 30px pills below the ring — Safe today (selected: `#1B1830` light / `#6D5AE6` dark, white text) / Net flow / Burn / Runway (unselected `#F1EFFB` / `#191630`). Selecting one **cross-fades the ring center** (150ms) to that metric; the ring itself stays as the category mix. This is the answer to the four hero metrics requested: safe-to-spend, net cash flow, burn rate, runway.
- **Budget card (from Pulse)**: radius 24, `linear-gradient(165deg, #123227 0%, #0C1F19 60%, #0A1815 100%)`, plus a radial emerald glow `radial-gradient(circle, rgba(52,211,153,0.30), transparent 70%)` 190px at top-right offset (-70px, -50px), clipped. Contents: 11px/600 `#7FD9B6` uppercase "JULY BUDGET" with `0.14em` tracking; right-aligned mono 10px pill `rgba(255,255,255,0.07)` "8 days left"; 30px mono spent "₹28,410" + 13px `#9DB2AB` "of ₹48,000"; 10px stacked bar (radius 6, track `rgba(255,255,255,0.08)`) = 58% emerald gradient `#34D399 -> #7FE8C4` + 9% gold `#E8B54D`; caption 12px `#A9C4BB` "₹4,180 of that is already committed to rent and EMIs — the gold slice."
- **"Where it went"**: section title 16px/600 + "All →" 12px violet. Each row: 36px icon tile (category tint, radius 13) + name 13px + mono amount `#5B5580` + 6px progress bar (track `#F1EFFB` light / `#241F3E` dark, fill = category hue, width = share of top category). Top 3 categories only; "All →" opens Activity filtered.
- **Insight card**: radius 22, `linear-gradient(150deg,#FFF3D8,#FFFBF0)`, 1px `#F3D9A0`; 36px ink tile with gold sparkle; title 13px/700 `#3D2E06` "Blinkit is up 62% this month"; body 12px `#7E6A45` "Nine orders already. Cap it at ₹2,000 a week?"; inline 32px ink pill "Sure" that creates the cap in one tap. Dark variant: `rgba(232,181,77,0.16) -> 0.05` gradient, border `rgba(232,181,77,0.3)`, title `#F3DFB4`.
- **Today list**: title 16px/600 + mono day total. Rows: 12px padding, radius 20, `#F6F4FE`; 36px category tile; name 14px/500; meta 11px `#7A7596` (time · account); mono amount 15px. Unsorted row differs: `#FFF7E4` + 1.5px `#F3D9A0`, "?" tile, meta `#8A5A00` "Swipe to sort · 3 left today".
- **States**: no data -> ring shows a dashed `#E7E4F5` outline, center reads "Nothing yet" with a 32px "Import texts" pill. Import running -> streak chip replaced by a mono progress chip.

### 03 Activity — `lib/features/transactions/transactions_screen.dart`
- **Purpose**: find and fix anything, without opening a filter sheet.
- **Layout**: title row (24px/700 "Activity" + 34px circular `#F1EFFB` search and export buttons) -> horizontal chip row -> summary strip -> grouped list -> selection bar.
- **Chips** (32px, radius 16, 7px gap, horizontally scrollable): active period `#1B1830`/white "This month"; applied filter `#EEE9FF`/`#4F3FC4` with an ✕ to clear ("Spends ✕"); attention chip `#FFF0D6`/`#8A5A00` "Unsorted 3"; inactive `#F1EFFB`/`#5B5580` ("Category", "Account"). Tapping an inactive chip opens a compact popover of options, not a full sheet. This replaces `transaction_filter_sheet.dart` as the primary path (keep the sheet as an "advanced" entry from the ↧ button).
- **Summary strip**: 11px padding, radius 16, `#F6F4FE`; left 12px `#7A7596` "148 spends · 12 credits"; right mono 14px/600 "−₹28,410". Updates live with chips.
- **Groups**: header 12px/700 `#7A7596` `0.04em` uppercase date group (use `formatDateGroup`) with a mono group total on the right; 8px gaps between rows.
- **Swipe row**: swiping a row left reveals a 72px violet (`#6D5AE6`) action panel with a 16px icon + 10px label "Recategorise"; swiping right reveals emerald "Accept guess" for unsorted rows. Row content otherwise identical to Home rows. Long-press enters multi-select.
- **Selection bar** (replaces nav pill when items are selected): 56px, radius 28, `#1B1830`; "2 selected" 13px; `rgba(255,255,255,0.14)` pill "Categorise"; emerald pill `#34D399`/`#04231A` 12px/600 "Apply to all" (applies to every transaction from the same merchant).
- **States**: empty search -> centered 14px `#7A7596` "Nothing matches those chips" + "Clear filters" violet text button. Credits use credit color and a ↓ tile.

### 04 Sort — `lib/features/review/weekly_review_screen.dart`
- **Purpose**: clear the uncategorised queue in about a minute, one gesture per item.
- **Layout**: `#F3F1FC` background. Header: 22px/700 "Sort the strays", 12px `#7A7596` "9 left · about a minute", right 32px white pill "List view" (switches to the grouped list mode). Segment progress: N equal 5px bars, radius 3, done `#6D5AE6`, pending `#DED8F5`, 4px gaps. Body centers a card deck; footer teaching note.
- **Card deck**: two offset stubs behind (`#EDE9FA` at +8px, `#E4DEF7` at +16px, radius 26) and the live card on top: white, radius 26, 22px padding, `rotate(-1.2deg)`, shadow `0 18px 40px rgba(27,24,48,0.12)`.
- **Card contents**: 26px gold pill "Unsorted" + mono 11px timestamp; 40px/600 mono "−₹1,100" (`-0.045em`); 16px/600 merchant "PAYTM-4429JK"; 12px `#7A7596` "HDFC ••4821 · UPI · from SMS"; guess panel (radius 18, `#F6F4FE`, 14px padding) with 11px `#7A7596` "MY BEST GUESS", 34px category tile, 14px/600 category name, 11px reason "You filed 4 similar ones here", mono 12px violet confidence "78%"; then 30px alternative chips (`#F1EFFB`), last chip "Something else" opens the category picker sheet.
- **Actions**: 56px circular white/`#E4DEF7` "Skip" (↺) on the left, 76px ink circle with emerald ✓ "Accept guess" in the center (shadow `0 14px 30px rgba(27,24,48,0.3)`), 56px "Choose" (◍) on the right. Swipe right = accept, left = skip, up = choose. Card flies out 220ms with rotation; the next card straightens.
- **Teaching note**: 20px radius `#E7F8F0`, 28px emerald tile, 12px `#0E5B41` "Filing this also teaches the next 6 Paytm texts. No repeat work."
- **Completion state**: deck replaced by a centered mascot at 92px, 22px/700 "Inbox zero", 13px `#7A7596` "Nine sorted in 54 seconds", ink pill "Back home", plus a one-time streak increment animation (gold count-up, 400ms).

### 05 Trends — `lib/features/insights/insights_screen.dart`
- **Purpose**: understand the month in three sentences and six bars.
- **Layout**: title 24px/700 + 32px `#F1EFFB` month picker chip "July 2026 ▾" -> gradient summary card -> insight cards -> top merchants.
- **Summary card**: radius 26, `linear-gradient(160deg,#6D5AE6,#8B6FF0 55%,#5B49D6)`, white radial glow top-right; 11px/600 `#DDD6FF` uppercase "YOU KEPT"; 38px mono "₹19,590" + 13px `#CFC6FF` "of ₹48,000 in"; 13px `#E4DEFF` sentence "Best month since March. Food is down ₹2,100 and no late fees at all."; a 70px-tall 6-month cubic-Bezier sparkline (2.5px white stroke, white 0.35 -> 0 gradient fill, 4.5px gold dot on the last point) with mono 10px month labels. Keep the existing Bezier sparkline painter, restyled.
- **Insight cards** (radius 22, 16px padding, 34px icon tile, title 13px/700, body 12px): gold `#FFF7E4`/border `#F3D9A0`/tile ink+gold — "Quick commerce is your growth story" / "Blinkit + Zepto = ₹6,240 this month, up from ₹3,850. Mostly after 9 PM."; green `#F1FBF6`/`#C9EEDD`/`#0E7A56` — "Rent-day dip is gone" / "You stayed above ₹10,000 through the 1st for the first time in five months."; red `#FDF2F3`/`#F4D2D4`/`#B4322F` — "Two price creeps" / "Spotify ₹119 → ₹149 and Jio ₹299 → ₹349. Together ₹60 a month more." Map these to the existing `insights_engine` / `narrative_insight_generator` outputs; the rule is one sentence of fact plus one of consequence.
- **Top merchants**: mono rank (18px column), 14px name, 11px `#7A7596` frequency, mono amount right-aligned 60px column, 1px `#EFECFA` dividers.

### 06 Recurring — `lib/features/recurring/recurring_screen.dart` (sheet)
- **Purpose**: show what is already spoken for, and what just got more expensive.
- **Layout**: back chevron + 22px/700 "Recurring" -> commitment card -> "NEXT 14 DAYS" timeline -> subscriptions list -> footer note.
- **Commitment card**: radius 24, `#1B1830`, white text; 11px/600 `#A9A2CC` "COMMITTED EACH MONTH"; 34px mono "₹24,860"; 12px `#B8B2D6` "52% of your usual income. Next out the door: rent on the 1st."; 8px segmented bar (radius 4, 2px gaps) rent `#2DD4BF` 62% / EMI `#FB7185` 14% / subs `#A78BFA` 12% / bills `#FACC15` 12% with 10px legend labels.
- **Timeline rows**: radius 20, `#F6F4FE`, 13px padding; left 44px date column (mono 16px/600 day over 10px `#7A7596` month), 1px `#E4DEF7` vertical rule, name 14px/500 + 11px cadence sub, right mono amount with an optional 10px debit-colored delta ("↑ ₹50").
- **Subscription rows**: white + 1px `#EFECFA`; usage sub ("Used 11 times in July"). A flagged row uses the gold treatment with sub "Price up ₹30 · no plays since May" and a 11px/600 violet "Cancel?" affordance under the amount.
- **Footer**: 12px `#7A7596` "Committed money is held out of \"safe to spend\" automatically." + 38px `#F1EFFB`/`#4F3FC4` "Adjust" pill.

### 07 Ask PaisaTrack — `lib/features/assistant/assistant_screen.dart` (sheet, dark)
- **Purpose**: answer a money question in one sentence, then offer the next action.
- **Layout**: dark `#0E0C1A`. Header: 34px mascot, 15px/600 "Ask PaisaTrack", 11px `#34D399` "On-device · no internet used", ✕ right; 1px `#1E1B33` divider. Message list 16/20px padding, 14px gaps. Composer pinned bottom.
- **User bubble**: right-aligned, max 78%, `#6D5AE6`, radius `20 20 6 20`, 14px white.
- **Assistant bubble**: left, max 88%, `#191630` + 1px `#262244`, radius `20 20 20 6`. Answer sentence first (14px, 1.5 line-height). Optional inline chart: 52px bars, 4px gaps, inactive `#3A3462`, highlighted bar in the category hue, mono 10px axis labels, then a 1px `#262244` rule and a 12px `#A9A2CC` explanatory line.
- **Follow-up chips** under the bubble: 32px, `#191630` + 1px `#2E2A4E`, `#C6C0E8`; an action chip uses `#122B22` + `#1F5142` + `#7FE8C4` ("Set a food cap").
- **Verdict answers** lead with a 14px/600 emerald line ("Yes — with ₹3,100 to spare") then the reasoning in 13px `#B8B2D6`.
- **Composer**: suggestion chips row (30px, `#191630`, `#A9A2CC`, horizontally scrollable — 3 visible at a time, rotating from the existing prompt catalogue instead of a 42-item tray) above a 52px input pill `#191630` + 1px `#2E2A4E`, placeholder 14px `#6F6A92` "Ask anything about your money…", 40px emerald gradient send button with ink ↑.
- **States**: thinking -> three 6px `#6D5AE6` dots pulsing inside an assistant bubble (600ms stagger). Model missing -> gold bubble offering "Download the 1.4 GB brain" with size and a progress bar. No answer -> "I can't answer that offline yet" + two chips that reframe the question.

### 08 Transaction detail — `lib/features/transactions/transaction_detail_screen.dart` (sheet)
- **Purpose**: correct one thing quickly and see where the data came from.
- **Layout**: scrim `#1B1830` at ~65% over the dimmed list; sheet radius 30 top, `#FBFAFF`, 12/20/30px padding, max height ~700px, 44x5 `#DED8F5` grab handle centered.
- **Head row**: 52px category tile (radius 18) + 19px/600 merchant + 12px `#7A7596` "23 Jul 2026 · 7:12 PM · HDFC ••4821" + right mono 26px/600 amount and 11px method.
- **Category chips**: 12px/700 `#7A7596` "CATEGORY" label; selected chip is the **full category hue** with white text (34px, radius 17); alternatives `#F1EFFB`/`#5B5580`; final chip "More…" opens `category_picker_sheet`.
- **Correction scope** (replaces `correction_scope_sheet.dart` as inline radio): 20px radio dots, violet when chosen — "Just this one" / "All 14 Swiggy spends · past & future".
- **Provenance**: 12px/700 label "WHERE THIS CAME FROM"; radius 18 `#F1FBF6` + 1px `#C9EEDD` block containing the raw SMS in mono 11px `#4E7A69` (1.6 line-height), then a 24px `#0E7A56` "Parsed locally" badge and 11px "Template match · 99%".
- **Footer buttons**: 48px pills side by side — `#F1EFFB`/`#5B5580` "Add a note" and `#1B1830`/white "Save".
- **States**: needs-review -> head row gains a gold "Unsorted" pill and Save reads "File it". Manual entry uses the same sheet with editable amount/merchant fields (mono 26px input).

### 09 Settings — `lib/features/settings/settings_screen.dart`
- **Purpose**: change the few things that matter, in plain words.
- **Layout**: `#F3F1FC` background, back chevron + 22px/700 "Settings", white grouped cards (radius 24, 16px padding, 14px internal gaps, 1px `#F3F1FC` dividers), 16px between groups. Group labels 12px/700 `#7A7596` `0.04em` uppercase.
- **LOOK**: segmented control — 4px padding `#F3F1FC` track, 36px segments radius 12, active `#1B1830`/white 12px/600 — Auto / Light / Dark. Toggle row "Show paise" + 46x28 switch (off track `#DED8F5`, 22px white knob; on track `#6D5AE6`), sub "Off keeps the big numbers cleaner".
- **YOUR MONEY**: "Monthly budget" with mono `#4F3FC4` value "₹48,000" (opens a stepper sheet), sub "Drives \"safe to spend\""; "Categories" -> 18 in use · 3 you made; "Accounts & cards" -> "HDFC ••4821, ICICI ••9930". Chevrons `#B8B2D6`.
- **THE BRAIN**: emerald-gradient dark card (same gradient family as the budget card), 12px/700 `#7FD9B6` label, "On-device" badge `rgba(52,211,153,0.18)`/`#7FE8C4`, 14px model name "Gemma 2B · quantised", 11px `#9DB2AB` "1.4 GB · answers in ~0.8s", 32px `rgba(255,255,255,0.1)` "Change" pill, and a 12px `#A9C4BB` reassurance line.
- **SAFETY NET**: "Encrypted backup" + last-saved sub + 32px violet-tinted "Back up" pill; "Erase everything" in debit color with sub "Undoable for 10 seconds after".

### 10 Home · dark — same widget tree as 02
- Surfaces: `#0E0C1A` base, `#191630` cards/nav, `#2E2A4E` outlines, `#241F3E` tracks. Ring remainder `#241F3E`; inner circle matches the base. Text `#ECEAF6` / `#B8B2D6` / `#8E88AD`. Selected metric chip becomes `#6D5AE6` (ink reads as background at night). Category tiles switch to `hue @ 18% alpha` with full-hue icons. Budget card and insight card keep their gradients; the insight card flips to the gold-on-dark variant. Nav pill gains a 1px `#2E2A4E` border.

## Interactions & Behavior
- **Hero metric switch**: tap a pill -> 150ms cross-fade of the ring's center text only.
- **Swipe to sort** (Activity + Sort): >40% drag or >600px/s fling commits; haptic light impact on commit; 10s undo toast "Filed under Food · Undo".
- **Bulk apply**: "Apply to all" writes a payee rule via the existing `rule_repository` and shows "6 more filed" in the toast.
- **Sheets**: drag-down to dismiss with velocity threshold; the scrim fades 0 -> 0.65 over the drag.
- **Tabs**: horizontal swipe or tap; 250ms ease; each tab keeps scroll position.
- **Insight "Sure" button**: creates the suggested cap immediately, card collapses to a 32px confirmation strip "Cap set · ₹2,000/week · Undo".
- **Streak**: increments once per day when the unsorted queue reaches zero; gold count-up 400ms plus a single confetti-free scale pop (1.0 -> 1.12 -> 1.0). No repeated celebration.
- **Loading**: skeletons use the surface/card color with a 1.2s shimmer; never a spinner over the whole screen. The ring shows a 25px-stroke indeterminate arc while the first import runs.
- **Errors**: inline gold/red rows with one sentence and one action. Never a modal alert.
- **Reduce motion**: disable bob, pulse ring, shimmer, and card rotation; keep opacity/color transitions.

## State Management (Riverpod, existing patterns)
- `heroMetricProvider` — enum { safeToday, netFlow, burnRate, runway }; selected pill; safe-to-spend = (budget − spent − committed) ÷ days remaining, from `dashboard_repository` + `recurring_detector` + `burn_rate_forecaster`.
- `dashboardRingProvider` — ordered list of (categoryId, share) for the conic ring; remainder = unspent budget.
- `unsortedQueueProvider` — uncategorised transactions with classifier guess + confidence, from `local_classifier` / `decision_policy`; feeds Sort and the Home "Swipe to sort · N left" row.
- `activityFilterProvider` — period, direction, categories, accounts, needsReview flag; chips read/write it; drives the summary strip.
- `selectionProvider` — selected transaction ids for the bulk bar.
- `streakProvider` — consecutive days at inbox zero; persisted in settings.
- `insightsProvider`, `recurringProvider`, `assistantControllerProvider` — unchanged sources, restyled presentation.
- `undoProvider` — last destructive/categorisation action with a 10s timer for the toast.

## Assets
- No new raster or vector assets are required. Category icons come from `CategoryVisuals.icon`; other glyphs map to Material icons. Existing 3D illustrations in `assets/icons/*.png` remain the right choice for onboarding and empty-state heroes (48–120dp only).
- Fonts to add: **Space Grotesk** (400/500/600/700) and **IBM Plex Mono** (400/500/600) — both SIL Open Font License, bundle as `assets/fonts/` and declare in `pubspec.yaml`.
- The mascot is two dots on a violet gradient circle — implementable in code, no asset needed.

## Files
Design references in this bundle (open in a browser):
- `PaisaTrack Redesign.dc.html` — the ten redesigned screens, annotated, with the design-principles panel. **This is the primary reference.**
- `dashboard-a-pulse.dc.html` — direction A (dark, glow, motion-led). Its budget card, category bars, gold insight card, and pulsing Ask orb were carried into the final design.
- `dashboard-d-bloom.dc.html` — direction D (violet, ring, mascot, streaks). The chosen base.
- `dashboard-b-ledger.dc.html`, `dashboard-c-grid.dc.html` — the two rejected directions, kept for context.
- `ios-frame.jsx` — device bezel used by the prototypes only. Not part of the design.

Repo files each screen replaces are named in the screen sections above; the mapping is also recorded in `github.md` at the project root.
