# Categorisation v2 — "Other" and income gap, payee review, taxonomy

Status: Proposed, planning only — 2026-10-10.
Tasks: [T-205](../tasks/T-205.md), [T-211](../tasks/T-211.md),
[T-162b/d](../tasks/T-162.md). ADR: [0036](../decisions/0036-explicit-payee-decisions-and-cue-rules.md)
(Proposed). Builds on [smart assistance](smart-transaction-assistance.md),
[T-177](../tasks/T-177.md) (c: scoped correction + undo, d: grouped review),
[ADR 0011](../decisions/0011-evidence-backed-assistance.md),
[0025](../decisions/0025-category-memory-suggestions.md),
[0031](../decisions/0031-recurring-and-correction-integrity.md).

## Goal

On the owner's device the share of spend in `other` falls well below half
without guessing, "money in" reflects real salary/interest/refunds, and the
user can resolve the remaining unknown payees in a few taps. Totals stay
source-faithful: no amount, direction or source-evidence change, ever.

## Current state — root causes (evidence)

1. **Ladder is thin and direction-blind.** Order is user rule
   (`categorizer.dart:116`) → merchant memory (`:132`) → classifier (`:149`) →
   seed (`:165`) → person/self fallback (`:180`) → LLM (`:190`) → `other` at
   confidence 0.3 (`:207`). Nothing reads `record.direction`, `channel` or
   `accountHint`; a credit and a debit with the same text get the same label.
2. **Memory and LLM steps are not wired.** `categorizerProvider`
   (`categorizer.dart:223-233`) passes only rules, seed, classifier and
   threshold; `merchantMemory`/`llmSuggester` are null in production
   (ADR 0025 keeps suggestions out of the ladder). The classifier returns
   null without a trained `model_meta` row (`local_classifier.dart:27-34`),
   which a new install lacks. So effectively rules + 29 seeds.
3. **Seed map is tiny and unsafe.** `assets/seed/category_seed.json` has 29
   keywords, substring-matched on `merchantRaw`/VPA only
   (`seed_category_map.dart:30-36`). No UPI-mandate, card-bill, rent, SIP,
   fuel-brand, hospital, school or NEFT cues. Short keys (`ola`, `lic`, `jio`)
   also false-match inside longer words (precision risk when expanded).
4. **P2P always falls to `other`.** `CounterpartyKeyParser.parse` returns
   `merchant` whenever `merchantRaw` is non-empty (`counterparty_key.dart:74`),
   and `person` only for phone-like VPAs with no merchant text (`:121-131`);
   `self` is never produced. Both outcomes end at `other`
   (`categorizer.dart:180-187`), correctly per ADR 0011, but nothing then
   asks the user. `other` has `is_spending = 1`, so unresolved P2P debits
   (rent, lending, family, own-account hops) count as spending
   (`financial_eligibility.dart:12`, `dashboard_repository.dart:150`).
5. **Own-account transfers link only when both legs exist.**
   `PaymentSourceRepository.reconcileOwnedTransfers` pairs debit+credit
   rows from *owned, active* sources with a unique neighbour
   (`payment_source_repository.dart:134-180`). A transfer to an own account
   whose SMS sender is not captured, or whose source is not marked owned,
   stays a spending debit. Credit-card bill payments are the same pattern
   (bank debit to card; card credit rarely captured).
6. **Income is "any credit", so ₹10k means few credits arrive.**
   `creditTotal` sums every settled credit regardless of category
   (`dashboard_repository.dart:152`, `dashboard_providers.dart:313`).
   Therefore the gap is *capture*, not categorisation: the Android allowlist
   knows ~29 header tokens (`SmsFilter.kt:18-23`), so any other bank/employer
   header is dropped before parsing (`:80`); personal-number senders are
   dropped (`:74`); only 9 template files exist (`assets/templates/`); NEFT/
   IMPS/RTGS credit wording relies on the generic parser. Salary gets
   `income_salary` only if the text yields merchant "Salary" or a seed hit
   (`generic_transaction_parser.dart:177`, seed `salary`). This is T-162.
7. **No "unresolved payee" surface.** `ActivityFilterChoice.unsorted`
   (`transactions_screen.dart:98`) means "no category or not confirmed", not
   "in `other`"; the Sort/review queue is per row. Grouped payee review is
   planned (T-177d) but nothing leads with *volume in `other`*.
8. **Category granularity.** 87 categories, 18 top-level, with no alcohol,
   tobacco, personal care, pets, vehicle, stays, rental subs, so even
   resolved rows land in broad buckets or `other` (T-211).

Measure before fixing: T-205a ships device-local reason-bucket counts so the
causes above are ranked on the owner's data, not assumed.

## Design

### 1. Deterministic cue rules (safe under ADR 0011)

New step in the ladder after user rules/memory and before classifier/seed:
`CueRuleEngine` over structured fields + coded body cues. Bundled asset
`assets/seed/category_cue_rules.json`, versioned, each rule:
`{id, direction, channels[], account_kinds[], require_cues[], any_tokens[],
 category_id, confidence, reason_bucket}`. Result `source = 'cue_rule'`,
confidence 0.85, `ruleId = cue:<id>`. User rules still win.

`PaymentCues` (new, pure) turns the raw body into a small set of coded cue ids
at ingest time only (body is already in hand at `sms_ingestion.dart:471`);
the raw text and cue strings are not persisted beyond the cue id list in
`confidence_json`. `NormalizedTransactionRecord` is not changed.

| Rule | Evidence required (all) | Category |
|---|---|---|
| Salary/payroll | credit + (`salary_word` or `payroll_word` cue) + channel netbanking/unknown (NEFT/IMPS/ACH) + account hint present | `income_salary` |
| Interest | credit + `interest_credited` cue + savings/FD cue | `income_interest` |
| Dividend | credit + `dividend` cue (ADR 0032 supporting SMS) | `income_dividend` |
| Refund/reversal | credit + `refund`/`reversal` cue; link stays separate (T-209 open) | `refund_purchase` / `refund_reversal` |
| Card bill payment | debit + token `credit card`/`cc payment`/biller `CRED`/`CREDCLUB`/`billdesk cc` + card last-4 | `transfers_card_payment` (non-spending; card purchases remain the spend) |
| Own-account | debit/credit both on owned sources, or user-confirmed own VPA/account tail | `transfers_own_account` + existing owned-transfer link |
| SIP/MF mandate | debit + `nach`/`si`/`mandate` cue + AMC/platform token (`groww`,`zerodha coin`,`kuvera`,`mutual fund`, AMC names) | `investments_mutual_fund_sip` |
| Rent | debit + token `rent` in narration/merchant only (word boundary) | `rent_house` (suggested, not auto) |
| Insurance premium | debit + insurer token + `premium`/`policy` cue | `insurance_*` |
| EMI | debit + `emi`/`loan` cue + NACH | `emi_*` |
| Fuel / hospital / school / utility | merchant token lists with word-boundary match | existing + new subs |

Hard constraints: a personal VPA alone never triggers a rule; rent from a
person VPA is only a *suggestion* in the review flow, never automatic;
direction is mandatory for every income rule; rules abstain on conflict
(two rules with different categories) and the row stays `other`/unresolved.
Seed expansion (T-205c/T-211e) switches matching to word-boundary tokens and
adds fuel brands, hospitals, schools, utilities and the new taxonomy.

### 2. "Spending or transfer?" payee review

Builds on the shipped correction path (`CorrectionScope.existingAndFuture`,
ADR 0031 receipt and guarded Undo), so this P0 does not wait for T-177c/d,
which are gated on the T-177a owner holdout. "Ask later" is a session-only
skip until T-177d adds persistent deferral. When T-177c/d land they replace
call sites; T-205 keeps the question model and entry points (orchestrator
decision 2026-10-10).

- Group key: stable payee identity (`PayeeKey`/`CounterpartyKeyParser`
  identityKey; VPA key when VPA present, else name key). Phone digits are
  hashed (`counterparty_key.dart:123-125`); UI shows the stored display name or
  masked form only.
- Order: unresolved volume in `other` descending (sum of debit amount in the
  current financial month, then all-time), tie by row count then id.
  Skipped/deferred groups sink; never repeat an answered payee.
- Card: payee label, N payments, total, date range, up to 3 sample rows with
  amounts (no SMS text). Choices:
  Spending (opens category picker, with search), Transfer to a person
  (`transfers_person`), Own account (`transfers_own_account`; also offers to
  mark the VPA/tail as owned), Rent (`rent_house`), Lent/borrowed
  (`transfers_lent` / `transfers_borrowed_repaid`, by direction), Ask later
  (persistent deferral, T-177d).
- Decision memory: one `rules` row per identity (match type `counterparty`
  or `merchant`), `feedback` context `payee_review`. Credits and debits for
  the same identity share the rule; a Transfer rule yields credit rows
  `transfers_person` too, so friends' repayments are not counted as income.
- Apply: always a preview first ("Updates 14 past payments, ₹23,400,
  and future ones"), exact ids/versions bound; stale preview refuses; one
  atomic write; Undo receipt restores category, feedback and the rule.
  Past rows already confirmed by the user are listed as exceptions and are
  not changed unless ticked.
- No amounts change. Spending totals move only because the *category*
  eligibility changes, shown in the preview as "removes ₹X from spending".

### 3. Uncategorised count and entries

`UncategorisedSummary` query: settled rows with `category_id IS NULL OR
category_id = 'other'` (and not in the `other_*` explicit user children),
count and amount per window, plus `payeeGroupCount`. Dashboard shows an
"Uncategorised: 31 payees · ₹58,200" chip leading to the payee review; the
Activity filter set adds `Uncategorised` (new enum value, distinct from
`unsorted`, which means "not yet confirmed"). The category donut's slice for
`other` links to the same filter. Hidden at zero; never says "all done"
while deferred groups remain (smart-assistance rule).

### 4. Privacy-safe local diagnostics

`CategorisationDiagnostics` returns counts only: per `source`
(`rule|cue_rule|seed|classifier|memory|fallback`), per `reason_bucket`
(`p2p_person_vpa`, `p2p_phone_vpa`, `merchant_unmatched`, `credit_unmatched`,
`card_bill`, `own_account_unpaired`, `sip_mandate`, `rent_candidate`,
`no_counterparty`, `other_user_chosen`), per direction and channel, plus
spend-share and count-share of `other` per month. Rounded amounts only in
buckets (₹ decade bands), never per-payee values. Shown in
Settings → Diagnostics (copyable JSON, local only, no network; ADR 0002).
Owner verification: record before/after on the device; target `other` share
by amount < 40% after rules, < 20% after a first review session
(*targets, not guarantees*).

## Constraints and invariants

- Deterministic extraction owns facts; cue rules and models only choose
  categories (ADR 0011). No LLM involvement in this plan.
- `Categorizer.categorize` is CRITICAL impact: keep signature and
  `CategorizationResult`; add an optional cues parameter only.
- Backfill/live/shadow paths share the same engine (no divergent copy).
- Re-categorisation of history happens only through preview + Undo, never as a
  silent migration. Existing user rules, confirmed rows and feedback win.
- Financial eligibility remains `FinancialEligibility`; category flag
  `is_spending` is the only switch (no new spending predicates).
- Accessibility: 48dp targets, semantics on choice chips; no flicker when the
  queue shrinks (keep list, animate removal; T-203 helper).

## Data model and ADR needs

ADR 0036 (Proposed) covers cue rules, explicit payee decisions and the
non-schema stance. Schema: none planned. If deferral needs more than a
`model_meta` JSON entry, T-177d decides before schema v21. Seed categories are
insert-or-ignore (`database.dart:71-88`), so new ids appear on upgrade; the
reparent migration is explicit (T-211b). Backup already exports rules,
feedback, categories; migration tests must cover restore of an older archive.

## T-211 taxonomy plan

- **Seed format.** Keep `assets/seed/categories.json` row shape (id, name,
  parent_id, icon, is_spending, sort_order, is_user_created). Add optional
  keys read only by new code: `aliases` (search synonyms, e.g. "chai"),
  `legacy` (true for superseded general buckets). Sort order: 10 per
  top-level, children +1.
- **Stable ids.** `<parent>_<slug>`, lowercase snake. Existing ids are never
  deleted or renamed (rows, rules, recurring series, budgets reference
  them). Where an existing id's parent changes, only `parent_id` changes via
  a one-time idempotent migration keyed in `model_meta`
  (`category_taxonomy_version`). Reparent set: `transport_bike_petrol`,
  `transport_vehicle_service`, `transport_parking_toll` → `vehicle`;
  `health_grooming` → `personal_care`; `health_pet_json` → `pets`;
  `health_insurance` → `insurance`; `fees_tax` → `taxes_govt`;
  `other_donations`, `other_religious` → `donations_religion`. Their names
  are updated only when `is_user_created = 0` and the user has not edited it
  (compare to previous seed name).
- **User-created categories** keep ids and parents; collisions on new seed
  ids are impossible because user ids are generated differently (verify in
  T-211b; otherwise migrate user id with suffix and repoint rows atomically).
- **Icons.** Add new icon names to `_icons` in
  `lib/core/theme/category_visuals.dart` (appendix lists them); prefix
  fallback map covers each new top-level; colours for each of ~35 top-levels
  from the existing hue wheel, subs inherit parent hue (already how prefix
  fallback works).
- **Picker scaling.** `CategoryPickerSheet` filters by name/parent name only
  (`category_picker_sheet.dart:42-48`). With ~370 rows: search over name +
  parent + `aliases` (diacritic/case-insensitive, prefix-ranked), collapsed
  groups when query empty, Suggested/Recent rows first, sticky parent
  headers, lazy `ListView.builder`. Test with 400 rows for jank.
- **Merchant seed expansion.** Grow `category_seed.json` to ~400 keys with
  word-boundary matching, grouped by taxonomy; synthetic test per key family
  (no real data). Alcohol/tobacco/cannabis keywords stay generic
  ("wine shop", "paan", "bhang") with neutral labels; no brand-level
  inference for sensitive categories unless the user picks them.
- **Sensitive categories** (alcohol, tobacco, cannabis): ordinary categories,
  no special export or telemetry; hidden from the assistant's example prompts.
- **Count.** Appendix proposes 35 top-level and 332 subcategories; the owner
  asked 200–300. T-211a review trims low-value rows (target ≤300), marking
  keeps/cuts in the appendix.

## Risks

- Mislabeling transfers as spending (or reverse) shifts totals: mitigated by
  evidence-required rules, preview, Undo, and abstain-on-conflict.
- Over-trusting a personal VPA: explicit ADR 0011 test (a person-VPA rent debit
  is never auto non-spending).
- Taxonomy migration touching referenced ids: migration test with rows,
  rules, budgets, recurring series and backup restore.
- Income gap may be capture, not categorisation: T-205a diagnostics plus T-162
  determine it first; do not promise the income number from rules alone.
- Context: T-177 is in review for C/D; avoid forking the correction engine.

## Rollout / flags

Flags (default off, `feature_flags`): `cue_rules_enabled`,
`payee_review_enabled`, `uncategorised_entry_enabled`,
`taxonomy_v2_enabled` (picker/visibility only; ids always seeded).
Order: diagnostics → taxonomy seed (additive) → cue rules shadow (compute,
log counts, do not apply) → apply to new rows → payee review → history apply.

## Open owner questions

None blocking. Non-blocking: (a) should `investments` stay `is_spending`?
(today yes, `categories.json`); (b) should `transfers_person` credits count as
income (default no).

## Subtasks and parallel groups

| Id | Title | Size/model | Depends | Group |
|---|---|---|---|---|
| T-205a | Categorisation diagnostics (counts only) | M Sonnet | — | A |
| T-205b | Cue-rule engine + PaymentCues (pure) | M Sonnet | — | A |
| T-205c | Cue rule asset + ladder wiring (flagged) | M Sonnet | T-205b | B |
| T-205d | Uncategorised summary query + Dashboard chip + Activity filter | M Sonnet | T-205a | B |
| T-205e | Payee group query + decision model | M Sonnet | ADR 0036 | C |
| T-205f | Payee review screen + apply/undo | M Sonnet | T-205e | D |
| T-205g | Own-account/card-bill source hints in review | S Haiku | T-205e | D |
| T-205h | Device verification report | S Haiku | T-205a,c,f | E |
| T-211a | Taxonomy review + trim (docs only) | S Haiku | — | A |
| T-211b | ADR check + reparent migration + seed (additive) | M Sonnet | T-211a | B |
| T-211c | Category visuals for new ids | S Haiku | T-211a | B |
| T-211d | Picker search/scale | M Sonnet | T-211b | C |
| T-211e | Merchant seed expansion + word-boundary matcher | M Sonnet | T-211a | B |
| T-162b1 | Sender-onboarding evidence format doc + validator | S Haiku | — | A |
| T-162b2 | Review gate test for allowlist changes | S Haiku | T-162b1 | B |
| T-162d1 | Payroll alias recogniser (pure) | M Sonnet | T-162a, T-162b1 | B |
| T-162d2 | Payroll alias wiring + fixtures | S Haiku | T-162d1, T-205c | C |

Group A tasks touch disjoint files and may run in parallel; B waits for its
dependencies, and so on. Details: the three task briefs.

## Appendix A — Proposed taxonomy (draft, 35 top-level, 332 subcategories)

Notes: "existing id" keeps the id of today's category (name may be refined;
its parent may change as listed above). All other ids are new. "(general)"
legacy buckets stay selectable for old rows. Icon names are Material
identifiers; those missing from `_icons` are added in T-211c.

#### Food & Dining (`food_dining`, spending, icon `restaurant`)

| id | name | icon | note |
|---|---|---|---|
| `food_tea_cigarette` | Tea stall & chai | `emoji_food_beverage` | existing id |
| `food_dining_out` | Restaurants | `restaurant` | existing id |
| `food_delivery` | Food delivery | `delivery_dining` | existing id |
| `food_office_lunch` | Office lunch & canteen | `lunch_dining` | existing id |
| `food_cafe_snacks` | Cafes & snacks | `local_cafe` | existing id |
| `food_street` | Street food & chaat | `fastfood` | new |
| `food_bakery_sweets` | Bakery & sweets | `bakery_dining` | new |
| `food_juice_shake` | Juice, shakes & ice cream | `icecream` | new |
| `food_fast_food` | Fast food chains | `lunch_dining` | new |
| `food_tiffin` | Tiffin & mess | `rice_bowl` | new |
| `food_catering` | Catering & party orders | `celebration` | new |
| `food_dhaba` | Dhaba & highway food | `restaurant` | new |

#### Groceries (`groceries`, spending, icon `local_grocery_store`)

| id | name | icon | note |
|---|---|---|---|
| `groceries_quick_commerce` | Quick commerce | `shopping_cart` | existing id |
| `groceries_supermarket` | Supermarket | `local_grocery_store` | existing id |
| `groceries_fruits_vegetables` | Fruits & vegetables | `shopping_basket` | existing id |
| `groceries_kirana` | Kirana & general store | `store` | new |
| `groceries_dairy` | Milk & dairy | `water_drop` | new |
| `groceries_meat_fish` | Meat, fish & eggs | `set_meal` | new |
| `groceries_staples` | Staples, atta & oil | `grain` | new |
| `groceries_snacks_beverages` | Packaged snacks & beverages | `cookie` | new |
| `groceries_organic` | Organic & specialty | `eco` | new |

#### Alcohol & Tobacco (`alcohol_tobacco`, spending, icon `local_bar`)

| id | name | icon | note |
|---|---|---|---|
| `alcohol_liquor_store` | Liquor store | `liquor` | new |
| `alcohol_bars_pubs` | Bars & pubs | `sports_bar` | new |
| `alcohol_beer_wine` | Beer & wine | `wine_bar` | new |
| `tobacco_cigarettes` | Cigarettes & paan shop | `smoking_rooms` | new |
| `tobacco_vape` | Vapes & hookah | `vaping_rooms` | new |
| `cannabis_bhang` | Cannabis & bhang | `grass` | new |
| `alcohol_other` | Other intoxicants | `local_bar` | new |

#### Local Transport (`transport`, spending, icon `directions_car`)

| id | name | icon | note |
|---|---|---|---|
| `transport_metro` | Metro | `subway` | existing id |
| `transport_cab_auto` | Cabs & autos | `electric_rickshaw` | existing id |
| `transport_bus_train` | Bus & local train | `train` | existing id |
| `transport_bike_taxi` | Bike taxi | `two_wheeler` | new |
| `transport_ride_pass` | Passes & smart cards | `badge` | new |
| `transport_ferry` | Ferry & boat | `directions_boat` | new |
| `transport_porter` | Porter & local delivery | `local_shipping` | new |
| `transport_airport_transfer` | Airport transfer | `airport_shuttle` | new |

#### Own Vehicle (`vehicle`, spending, icon `two_wheeler`)

| id | name | icon | note |
|---|---|---|---|
| `transport_bike_petrol` | Fuel (petrol/diesel/CNG) | `local_gas_station` | existing id |
| `transport_vehicle_service` | Service & repair | `build` | existing id |
| `transport_parking_toll` | Parking & toll (general) | `toll` | existing id |
| `vehicle_parking` | Parking | `local_parking` | new |
| `vehicle_tolls` | Tolls & FASTag | `toll` | new |
| `vehicle_insurance` | Vehicle insurance | `shield` | new |
| `vehicle_ev_charging` | EV charging | `ev_station` | new |
| `vehicle_tyres_battery` | Tyres & battery | `tire_repair` | new |
| `vehicle_wash` | Washing & detailing | `local_car_wash` | new |
| `vehicle_accessories` | Accessories & spares | `settings` | new |
| `vehicle_puc_rto` | PUC, RTO & registration | `description` | new |
| `vehicle_challan` | Traffic challan | `gavel` | new |
| `vehicle_driver` | Driver & chauffeur | `person` | new |

#### Vehicle Rental (`vehicle_rental`, spending, icon `car_rental`)

| id | name | icon | note |
|---|---|---|---|
| `rental_bike_scooter` | Bike & scooter rental | `two_wheeler` | new |
| `rental_self_drive_car` | Self-drive car | `car_rental` | new |
| `rental_chauffeur_car` | Chauffeur-driven car | `directions_car` | new |
| `rental_cycle` | Cycle rental | `pedal_bike` | new |
| `rental_camper_rv` | Campervan & RV | `rv_hookup` | new |
| `rental_deposit` | Rental deposit | `savings` | new |

#### Travel (`travel`, spending, icon `flight`)

| id | name | icon | note |
|---|---|---|---|
| `travel_flights` | Flights | `flight` | existing id |
| `travel_trains` | Trains | `train` | existing id |
| `travel_hotels` | Hotel bookings (general) | `hotel` | existing id |
| `travel_buses` | Intercity buses | `directions_bus` | new |
| `travel_cabs_outstation` | Outstation cabs | `local_taxi` | new |
| `travel_visa_passport` | Visa & passport | `badge` | new |
| `travel_forex` | Forex & travel cards | `currency_exchange` | new |
| `travel_insurance` | Travel insurance | `shield` | new |
| `travel_baggage_seats` | Baggage, seats & meals add-ons | `luggage` | new |
| `travel_tours_packages` | Tours & packages | `tour` | new |
| `travel_activities` | Sightseeing & activities | `attractions` | new |
| `travel_lounge` | Lounge & airport services | `weekend` | new |
| `travel_agent_fees` | Agent & convenience fees | `request_quote` | new |
| `travel_cruise` | Cruise | `directions_boat` | new |

#### Stays (`stays`, spending, icon `hotel`)

| id | name | icon | note |
|---|---|---|---|
| `stays_hotels` | Hotels | `hotel` | new |
| `stays_hostels` | Hostels & dorms | `bed` | new |
| `stays_homestays` | Homestays & guesthouses | `cottage` | new |
| `stays_resorts` | Resorts | `pool` | new |
| `stays_rentals_airbnb` | Vacation rentals | `holiday_village` | new |
| `stays_dharamshala` | Dharamshala & ashram | `temple_hindu` | new |
| `stays_camping` | Camping & glamping | `camping` | new |
| `stays_service_apartment` | Service apartments | `apartment` | new |
| `stays_extras` | Stay extras & taxes | `receipt` | new |

#### Shopping (`shopping`, spending, icon `shopping_bag`)

| id | name | icon | note |
|---|---|---|---|
| `shopping_clothing` | Clothing | `shopping_bag` | existing id |
| `shopping_electronics` | Electronics | `laptop_mac` | existing id |
| `shopping_home` | Home goods (general) | `home` | existing id |
| `shopping_gifts` | Gifts (general) | `redeem` | existing id |
| `shopping_footwear` | Footwear | `hiking` | new |
| `shopping_accessories` | Bags, watches & accessories | `watch` | new |
| `shopping_jewellery` | Jewellery | `diamond` | new |
| `shopping_marketplace` | Marketplace (mixed) | `storefront` | new |
| `shopping_mobile_accessories` | Mobile & accessories | `phone_android` | new |
| `shopping_books_stationery` | Books & stationery | `menu_book` | new |
| `shopping_toys_games` | Toys & games | `toys` | new |
| `shopping_sports_goods` | Sports goods | `sports` | new |
| `shopping_flowers` | Flowers & plants | `local_florist` | new |
| `shopping_luggage` | Luggage | `luggage` | new |

#### Personal Care (`personal_care`, spending, icon `face_retouching_natural`)

| id | name | icon | note |
|---|---|---|---|
| `health_grooming` | Salon & barber | `content_cut` | existing id |
| `care_spa_massage` | Spa & massage | `spa` | new |
| `care_skincare_cosmetics` | Skincare & cosmetics | `face` | new |
| `care_hair` | Hair care & products | `brush` | new |
| `care_hygiene` | Hygiene & toiletries | `clean_hands` | new |
| `care_nails_beauty` | Beauty parlour & nails | `self_improvement` | new |
| `care_fragrance` | Fragrances | `air` | new |
| `care_laundry_drycleaning` | Laundry & dry cleaning | `local_laundry_service` | new |
| `care_tailoring` | Tailoring & alterations | `checkroom` | new |

#### Health (`health`, spending, icon `local_hospital`)

| id | name | icon | note |
|---|---|---|---|
| `health_doctor` | Doctor consultation | `medical_services` | existing id |
| `health_pharmacy` | Pharmacy | `medication` | existing id |
| `health_fitness_wellness` | Fitness & wellness (general) | `fitness_center` | existing id |
| `health_diagnostics` | Lab tests & diagnostics | `biotech` | new |
| `health_hospital` | Hospital & surgery | `local_hospital` | new |
| `health_dental` | Dental | `dentistry` | new |
| `health_eye` | Eye care & glasses | `visibility` | new |
| `health_mental` | Therapy & counselling | `psychology` | new |
| `health_ayush` | Ayurveda & homeopathy | `spa` | new |
| `health_physio` | Physiotherapy | `accessibility` | new |
| `health_medical_devices` | Medical devices | `monitor_heart` | new |
| `health_vaccination` | Vaccination & checkups | `vaccines` | new |
| `health_supplements` | Supplements & nutrition | `nutrition` | new |
| `health_ambulance` | Ambulance & emergency | `emergency` | new |

#### Insurance (`insurance`, spending, icon `shield`)

| id | name | icon | note |
|---|---|---|---|
| `health_insurance` | Health insurance | `shield` | existing id |
| `insurance_life` | Life & term insurance | `favorite` | new |
| `insurance_vehicle` | Vehicle insurance (policy) | `directions_car` | new |
| `insurance_home` | Home & contents | `home` | new |
| `insurance_travel` | Travel insurance (policy) | `flight` | new |
| `insurance_personal_accident` | Personal accident | `healing` | new |
| `insurance_gadget` | Gadget protection | `phone_android` | new |
| `insurance_other` | Other premiums | `shield` | new |

#### Pets (`pets`, spending, icon `pets`)

| id | name | icon | note |
|---|---|---|---|
| `health_pet_json` | Pet care (general) | `pets` | existing id |
| `pets_food` | Pet food | `pets` | new |
| `pets_vet` | Vet & medicine | `vaccines` | new |
| `pets_grooming` | Pet grooming | `content_cut` | new |
| `pets_boarding` | Boarding & sitting | `home` | new |
| `pets_supplies` | Toys & supplies | `toys` | new |
| `pets_training` | Training | `school` | new |
| `pets_adoption` | Adoption & breeding fees | `favorite` | new |

#### Bills & Utilities (`bills_utilities`, spending, icon `receipt_long`)

| id | name | icon | note |
|---|---|---|---|
| `bills_electricity` | Electricity | `electric_bolt` | existing id |
| `bills_water` | Water | `water_drop` | existing id |
| `bills_cooking_gas` | Cooking gas (LPG/PNG) | `propane` | existing id |
| `bills_mobile_recharge` | Mobile recharge & postpaid | `phone_android` | existing id |
| `bills_broadband_wifi` | Broadband & Wi-Fi | `wifi` | existing id |
| `bills_dth_tv` | DTH & cable TV | `tv` | existing id |
| `bills_society_maintenance` | Society maintenance | `apartment` | existing id |
| `bills_property_tax` | Property & municipal tax | `account_balance` | new |
| `bills_sewage_waste` | Waste & sewage | `delete` | new |
| `bills_landline` | Landline | `call` | new |
| `bills_prepaid_wallet` | Prepaid meters & wallets | `account_balance_wallet` | new |
| `bills_credit_card` | Credit card bill payment | `credit_card` | new |

#### Subscriptions (`subscriptions`, spending, icon `subscriptions`)

| id | name | icon | note |
|---|---|---|---|
| `subscriptions_ott` | Video streaming | `movie` | existing id |
| `subscriptions_music` | Music & audio | `music_note` | existing id |
| `subscriptions_cloud` | Cloud storage | `cloud` | existing id |
| `subscriptions_claude` | Claude | `psychology_alt` | existing id |
| `subscriptions_codex` | Codex | `terminal` | existing id |
| `subscriptions_gym` | Gym membership | `fitness_center` | existing id |
| `subscriptions_ai_tools` | Other AI tools | `smart_toy` | new |
| `subscriptions_news_magazines` | News & magazines | `newspaper` | new |
| `subscriptions_software` | Software & apps | `apps` | new |
| `subscriptions_gaming` | Gaming passes | `sports_esports` | new |
| `subscriptions_memberships` | Clubs & memberships | `card_membership` | new |
| `subscriptions_vpn_security` | VPN & security | `vpn_key` | new |
| `subscriptions_domains_hosting` | Domains & hosting | `dns` | new |
| `subscriptions_learning` | Learning platforms | `school` | new |

#### Home & Rent (`rent_housing`, spending, icon `home`)

| id | name | icon | note |
|---|---|---|---|
| `rent_house` | House rent | `house` | existing id |
| `rent_house_help` | Domestic help | `cleaning_services` | existing id |
| `rent_repairs` | Repairs & maintenance | `handyman` | existing id |
| `rent_laundry` | Laundry (general) | `local_laundry_service` | existing id |
| `rent_deposit` | Security deposit | `savings` | new |
| `rent_brokerage` | Brokerage | `real_estate_agent` | new |
| `rent_pg_hostel` | PG & hostel rent | `bed` | new |
| `rent_office_coworking` | Office & coworking rent | `business` | new |
| `rent_parking_space` | Parking space rent | `local_parking` | new |
| `rent_cook_maid_driver` | Cook, maid & nanny | `person` | new |
| `rent_moving` | Packers & movers | `local_shipping` | new |
| `rent_storage` | Storage unit | `warehouse` | new |

#### Household (`home_household`, spending, icon `chair`)

| id | name | icon | note |
|---|---|---|---|
| `household_furniture` | Furniture | `chair` | new |
| `household_appliances` | Appliances | `kitchen` | new |
| `household_kitchenware` | Kitchenware | `soup_kitchen` | new |
| `household_decor` | Decor & furnishings | `bedroom_parent` | new |
| `household_cleaning` | Cleaning supplies | `cleaning_services` | new |
| `household_plumber_electrician` | Plumber & electrician | `plumbing` | new |
| `household_pest_control` | Pest control | `bug_report` | new |
| `household_garden` | Garden & plants | `yard` | new |
| `household_security` | Security & CCTV | `security` | new |
| `household_renovation` | Renovation & paint | `format_paint` | new |
| `household_hardware` | Hardware & tools | `construction` | new |

#### EMI & Loans (`emi_loans`, spending, icon `account_balance`)

| id | name | icon | note |
|---|---|---|---|
| `emi_credit_card` | Credit card EMI | `credit_card` | existing id |
| `emi_home_loan` | Home loan EMI | `account_balance` | existing id |
| `emi_vehicle_loan` | Vehicle loan EMI | `directions_car` | existing id |
| `emi_personal_loan` | Personal loan EMI | `request_quote` | existing id |
| `emi_education_loan` | Education loan EMI | `school` | new |
| `emi_gold_loan` | Gold loan | `savings` | new |
| `emi_bnpl` | Buy-now-pay-later | `payments` | new |
| `emi_consumer_durable` | Consumer durable EMI | `tv` | new |
| `emi_loan_interest` | Loan interest & foreclosure | `percent` | new |
| `emi_business_loan` | Business loan EMI | `business` | new |

#### Education (`education`, spending, icon `school`)

| id | name | icon | note |
|---|---|---|---|
| `education_school_fees` | School fees | `school` | existing id |
| `education_child_care` | Child care (general) | `child_care` | existing id |
| `education_online_courses` | Online courses | `laptop_mac` | existing id |
| `education_books` | Books (general) | `menu_book` | existing id |
| `education_college_fees` | College & university fees | `account_balance` | new |
| `education_tuition` | Tuition & coaching | `co_present` | new |
| `education_exam_fees` | Exam & application fees | `assignment` | new |
| `education_uniform_supplies` | Uniform & stationery | `checkroom` | new |
| `education_school_transport` | School transport | `directions_bus` | new |
| `education_hostel_mess` | Hostel & mess | `bed` | new |
| `education_certifications` | Certifications | `workspace_premium` | new |

#### Kids & Family (`kids_family`, spending, icon `child_care`)

| id | name | icon | note |
|---|---|---|---|
| `kids_daycare` | Daycare & creche | `child_care` | new |
| `kids_toys` | Toys & games (kids) | `toys` | new |
| `kids_clothes` | Kids clothing | `checkroom` | new |
| `kids_baby_care` | Baby care & diapers | `baby_changing_station` | new |
| `kids_activities` | Classes & hobbies | `palette` | new |
| `kids_pocket_money` | Pocket money | `savings` | new |
| `kids_parents_support` | Parents' support | `elderly` | new |
| `kids_events_birthdays` | Birthdays & events | `cake` | new |

#### Entertainment (`entertainment`, spending, icon `theaters`)

| id | name | icon | note |
|---|---|---|---|
| `entertainment_movies_events` | Movies & events | `movie` | existing id |
| `entertainment_sports` | Sports (general) | `sports_cricket` | existing id |
| `entertainment_nightlife` | Nightlife (general) | `local_bar` | existing id |
| `entertainment_concerts` | Concerts & shows | `music_note` | new |
| `entertainment_gaming` | Gaming & in-app purchases | `sports_esports` | new |
| `entertainment_amusement` | Amusement parks | `attractions` | new |
| `entertainment_clubs` | Clubs & lounges | `nightlife` | new |
| `entertainment_streaming_rent` | Rent/buy movies | `movie` | new |
| `entertainment_fantasy` | Fantasy & contests | `emoji_events` | new |
| `entertainment_books_comics` | Books, comics & audio | `menu_book` | new |

#### Sports & Hobbies (`sports_hobbies`, spending, icon `sports`)

| id | name | icon | note |
|---|---|---|---|
| `hobby_gym_classes` | Fitness classes | `fitness_center` | new |
| `hobby_sports_clubs` | Sports clubs & turf | `sports_soccer` | new |
| `hobby_equipment` | Sports equipment | `sports` | new |
| `hobby_music_art` | Music & art supplies | `palette` | new |
| `hobby_photography` | Photography | `photo_camera` | new |
| `hobby_trekking` | Trekking & adventure | `hiking` | new |
| `hobby_crafts` | Crafts & DIY | `handyman` | new |
| `hobby_collectibles` | Collectibles | `collections` | new |

#### Gifts & Social (`gifts_social`, spending, icon `redeem`)

| id | name | icon | note |
|---|---|---|---|
| `gifts_birthday` | Birthday & anniversary gifts | `cake` | new |
| `gifts_wedding` | Weddings & shagun | `favorite` | new |
| `gifts_festival` | Festival gifts & sweets | `celebration` | new |
| `gifts_party` | Party & get-together | `local_bar` | new |
| `gifts_flowers` | Flowers & cards | `local_florist` | new |
| `gifts_online` | Gift cards & vouchers | `card_giftcard` | new |
| `gifts_condolence` | Condolence & funeral | `volunteer_activism` | new |

#### Donations & Faith (`donations_religion`, spending, icon `volunteer_activism`)

| id | name | icon | note |
|---|---|---|---|
| `other_donations` | Charity & donations | `volunteer_activism` | existing id |
| `other_religious` | Temple & religious | `temple_hindu` | existing id |
| `donations_crowdfunding` | Crowdfunding | `groups` | new |
| `donations_pooja_items` | Pooja items | `local_florist` | new |
| `donations_festivals` | Festival contributions | `celebration` | new |
| `donations_ngo_csr` | NGO & foundation | `handshake` | new |

#### Tech & Digital (`tech_software`, spending, icon `devices`)

| id | name | icon | note |
|---|---|---|---|
| `tech_gadgets` | Gadgets & peripherals | `headphones` | new |
| `tech_repairs` | Device repair | `build` | new |
| `tech_app_purchases` | App & game purchases | `apps` | new |
| `tech_cloud_dev` | Dev tools & APIs | `terminal` | new |
| `tech_internet_cafe` | Print, scan & cyber cafe | `print` | new |
| `tech_domain` | Domains & certificates | `dns` | new |

#### Work & Business (`business_work`, spending, icon `work`)

| id | name | icon | note |
|---|---|---|---|
| `work_coworking` | Coworking & office | `business` | new |
| `work_equipment` | Work equipment | `laptop_mac` | new |
| `work_travel` | Work travel | `flight` | new |
| `work_meals` | Work meals | `lunch_dining` | new |
| `work_software` | Work software | `apps` | new |
| `work_stationery` | Stationery & printing | `print` | new |
| `work_client_gifts` | Client gifts | `redeem` | new |
| `work_reimbursable` | Reimbursable expense | `receipt_long` | new |
| `work_advertising` | Advertising & marketing | `campaign` | new |
| `work_supplies_stock` | Stock & supplies | `inventory` | new |

#### Services (`services_professional`, spending, icon `handyman`)

| id | name | icon | note |
|---|---|---|---|
| `services_legal` | Legal | `gavel` | new |
| `services_ca_tax_filing` | CA & tax filing | `calculate` | new |
| `services_courier` | Courier & postage | `local_shipping` | new |
| `services_repairs` | Repairs & technicians | `build` | new |
| `services_printing_docs` | Printing & documents | `print` | new |
| `services_notary_stamp` | Notary & stamp duty | `description` | new |
| `services_photographer` | Photography services | `photo_camera` | new |
| `services_astro` | Astrology & counselling | `auto_awesome` | new |
| `services_domestic_agency` | Agency & placement | `badge` | new |

#### Investments (`investments`, spending, icon `trending_up`)

| id | name | icon | note |
|---|---|---|---|
| `investments_mutual_fund_sip` | Mutual funds & SIP | `show_chart` | existing id |
| `investments_stocks` | Stocks & trading | `candlestick_chart` | existing id |
| `investments_nps_ppf` | NPS, PPF & EPF | `savings` | existing id |
| `investments_fd_rd` | FD & RD | `account_balance` | existing id |
| `investments_gold` | Gold & silver | `trending_up` | existing id |
| `investments_bonds` | Bonds & debentures | `receipt_long` | new |
| `investments_crypto` | Crypto | `currency_bitcoin` | new |
| `investments_real_estate` | Real estate | `apartment` | new |
| `investments_ulip_insurance` | ULIP & endowment | `shield` | new |
| `investments_brokerage_fees` | Brokerage & demat charges | `request_quote` | new |
| `investments_sgb_etf` | SGB & ETF | `trending_up` | new |
| `investments_ipo` | IPO applications | `rocket_launch` | new |
| `investments_p2p_lending` | P2P lending | `handshake` | new |

#### Taxes & Government (`taxes_govt`, spending, icon `account_balance`)

| id | name | icon | note |
|---|---|---|---|
| `fees_tax` | Income tax (general) | `currency_rupee` | existing id |
| `taxes_advance_tax` | Advance & self-assessment tax | `currency_rupee` | new |
| `taxes_gst` | GST | `receipt_long` | new |
| `taxes_property` | Property tax | `home` | new |
| `taxes_professional` | Professional tax | `work` | new |
| `govt_fines` | Fines & penalties | `gavel` | new |
| `govt_passport_licence` | Passport, licence & ID | `badge` | new |
| `govt_court_stamp` | Court & stamp fees | `description` | new |

#### Fees & Charges (`fees_charges`, spending, icon `request_quote`)

| id | name | icon | note |
|---|---|---|---|
| `fees_bank` | Bank charges (general) | `request_quote` | existing id |
| `fees_card_annual` | Card annual fee | `credit_card` | new |
| `fees_late_payment` | Late fees & penalties | `schedule` | new |
| `fees_atm` | ATM & transaction charges | `atm` | new |
| `fees_gst_on_fees` | GST on charges | `receipt_long` | new |
| `fees_forex_markup` | Forex markup | `currency_exchange` | new |
| `fees_sms_alerts` | SMS & maintenance charges | `sms` | new |
| `fees_convenience` | Convenience fees | `request_quote` | new |
| `fees_interest_charged` | Interest charged | `percent` | new |
| `fees_processing` | Processing fees | `request_quote` | new |

#### Cash Withdrawal (`cash_withdrawal`, non-spending, icon `atm`)

| id | name | icon | note |
|---|---|---|---|
| `cash_atm` | ATM withdrawal | `atm` | new |
| `cash_pos` | Cash at POS | `point_of_sale` | new |
| `cash_cardless` | Cardless withdrawal | `atm` | new |

#### Transfers (non-spending) (`transfers`, non-spending, icon `swap_horiz`)

| id | name | icon | note |
|---|---|---|---|
| `transfers_family` | Family (general) | `swap_horiz` | existing id |
| `transfers_wife` | Spouse | `favorite` | existing id |
| `transfers_own_account` | Own account transfer | `sync_alt` | new |
| `transfers_card_payment` | Card bill payment (settlement) | `credit_card` | new |
| `transfers_person` | Transfer to a person | `person` | new |
| `transfers_lent` | Lent to someone | `call_made` | new |
| `transfers_borrowed_repaid` | Borrowed money repaid | `call_received` | new |
| `transfers_wallet_topup` | Wallet top-up | `account_balance_wallet` | new |
| `transfers_friends_split` | Friends split / shared bill | `groups` | new |
| `transfers_parents` | Parents | `elderly` | new |
| `transfers_siblings_relatives` | Siblings & relatives | `people` | new |
| `transfers_pending_ask_later` | Undecided (ask later) | `help_outline` | new |

#### Income (`income`, non-spending, icon `payments`)

| id | name | icon | note |
|---|---|---|---|
| `income_salary` | Salary | `payments` | existing id |
| `income_freelance` | Freelance & business | `account_balance_wallet` | existing id |
| `income_dividend` | Dividends | `account_balance_wallet` | existing id |
| `income_interest` | Interest earned | `percent` | new |
| `income_rent_received` | Rent received | `house` | new |
| `income_bonus` | Bonus & incentives | `emoji_events` | new |
| `income_reimbursement` | Reimbursements from employer | `receipt_long` | new |
| `income_pension` | Pension | `elderly` | new |
| `income_capital_gains` | Sale proceeds & maturity | `trending_up` | new |
| `income_gift_received` | Gifts received | `redeem` | new |
| `income_tax_refund` | Tax refund | `currency_rupee` | new |
| `income_other` | Other income | `payments` | new |
| `income_from_person` | Received from a person (unclassified) | `person` | new |

#### Refunds & Cashback (`refunds_cashback`, non-spending, icon `undo`)

| id | name | icon | note |
|---|---|---|---|
| `refund_purchase` | Purchase refund | `undo` | new |
| `refund_cashback` | Cashback & rewards | `redeem` | new |
| `refund_reversal` | Failed-payment reversal | `restore` | new |
| `refund_insurance_claim` | Insurance claim settlement | `shield` | new |
| `refund_deposit_return` | Deposit returned | `savings` | new |
| `refund_travel` | Travel refund | `flight` | new |

#### Other (`other`, spending, icon `category`)

| id | name | icon | note |
|---|---|---|---|
| `other_misc` | Miscellaneous | `category` | new |
| `other_unknown_payee` | Unknown payee (needs review) | `help_outline` | new |
