repo: KrShivay/PaisaTrack
branch: main
path: lib

## Last sync
date: 2026-07-26T00:12:00Z

### Updated in this project
- Read theme tokens, category colors, INR/date formatting and the nav shell to ground the redesign
- Built four dashboard directions; the Bloom direction (violet ring + mascot) was chosen and blended with Pulse's budget card, category bars and gold insight card
- Redesigned all ten screens in `PaisaTrack Redesign.dc.html`, light and dark
- Wrote a Claude Code handoff package under `design_handoff_paisatrack_redesign/`

## Screen map
| Project screen | Repo files |
| --- | --- |
| PaisaTrack Redesign · 01 Onboarding | lib/features/onboarding/onboarding_screen.dart |
| PaisaTrack Redesign · 02 Home, 10 Home dark | lib/features/dashboard/dashboard_screen.dart, lib/features/dashboard/dashboard_widgets.dart, lib/features/dashboard/dashboard_providers.dart |
| PaisaTrack Redesign · 03 Activity | lib/features/transactions/transactions_screen.dart, lib/core/widgets/transaction_components.dart, lib/core/widgets/transaction_filter_sheet.dart |
| PaisaTrack Redesign · 04 Sort | lib/features/review/weekly_review_screen.dart |
| PaisaTrack Redesign · 05 Trends | lib/features/insights/insights_screen.dart, lib/intelligence/insights_engine.dart |
| PaisaTrack Redesign · 06 Recurring | lib/features/recurring/recurring_screen.dart, lib/intelligence/recurring_detector.dart |
| PaisaTrack Redesign · 07 Ask | lib/features/assistant/assistant_screen.dart, lib/intelligence/assistant/* |
| PaisaTrack Redesign · 08 Transaction detail | lib/features/transactions/transaction_detail_screen.dart, lib/core/widgets/category_picker_sheet.dart, lib/core/widgets/correction_scope_sheet.dart |
| PaisaTrack Redesign · 09 Settings | lib/features/settings/settings_screen.dart |
| Nav model (all screens) | lib/features/home/home_shell.dart |
| Design tokens (all screens) | lib/core/theme/app_tokens.dart, lib/core/theme/paisa_colors.dart, lib/core/theme/category_visuals.dart, lib/core/format.dart |
