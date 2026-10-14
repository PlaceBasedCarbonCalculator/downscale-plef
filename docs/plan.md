# Downscaling PLEF to LSOAs: initial plan

*Draft v0.2, 14 October 2026 (decisions added). A starting point to iterate on, not a settled design.*

## 1. Aim

Take the CREDS *Positive Low Energy Futures* (PLEF) national scenarios as given and distribute them across Great Britain's ~42,000 LSOAs / Data Zones, for **housing** and **transport** only, so that:

- every year, the population/household-weighted sum of LSOA values reproduces the PLEF national pathway;
- each LSOA follows a plausible trajectory (bounded rates of change, technical ceilings, no impossible jumps);
- different distributive principles (capability, equity, uniform) can be compared;
- the results identify early adopters, late adopters, the best option(s) per area, and areas with no good options, with policy implications.

Food, goods and services are out of scope for downscaling. If a total footprint is needed for context, they follow the PLEF national trend uniformly (as the "Data Needs" document already proposes).

## 2. What already exists

### 2.1 In this repo (`docs/`, `data/`)

| Item | What it gives us |
|---|---|
| `original PLEF/CREDS-Role-of-energy-demand-report-2021.pdf` | The full PLEF report. Appendix tables A1/A2 give energy service demand indices by scenario for 2020–2050 (e.g. passenger car km in Transform falls to 0.50 of 2010; two-wheelers ×7.25; bus ×2.52; rail ×1.78). The Shelter appendix gives the heat pump S-curve constraint (e.g. Transform: 15% of max technical potential by 2025, 60% by 2030, 100% by 2035), retrofit roll-out (250k/yr Shift, 1m/yr Transform), DH cap of 34% of residential heat, and HP-compatible stock shares by dwelling type (houses ~80%, flats 10–13%). |
| `original PLEF/s41560-022-01057-y.pdf` | Barrett et al. (2022) *Nature Energy* paper: the peer-reviewed reference for the scenarios. |
| `original PLEF/Data – Positive low energy futures.htm` | Archived data page: sector energy and emissions tables (Figs 7–9). |
| `data/LED_TRN_analysis_v2.xlsx` (42 MB) | **TEAM-UK transport model outputs**: annual 2012–2050 (to 2100 in places) for scenarios LED0 "BAU", LED1 "High Ambition", LED2 "Transformative". Includes trips, trip length and mode shares by journey purpose (commute, business, leisure long/local, school, shop, personal business), effects of telework/4-day week/proximity, pass-km and veh-km by mode, vehicle stock by fuel/size, energy and emissions, and socio-demographics (population, households, cars per 1,000). This is the richest national input we have. |
| `data/elec_ghg_intensity.xls` | UKTM electricity generation and grid intensity (gCO2e/kWh) 2010–2050 for LED-RF, LED-HA, LED-TC. |
| `data/total_car_stock.xls`, `total_vehicle_stock.xls` | UKTM car and vehicle stock by fuel 2010–2050, same three scenarios. |
| `docs/PLEF Downscaling Data Needs.docx` | Defines the five downscaling targets (insulation/heat demand, heat pumps & DH, car km via sharing/active/PT/telework, EV switch, aviation), a −1…+1 adoption score per LSOA, and candidate local factors per measure. |
| `docs/AI Summary of Factors.docx` | Literature-style summary of adoption factors, direction and rough magnitude, for each of the eight measures. Useful as a long list; the citations need checking before use in a paper. |
| `docs/PBCC Downscaling Jan 2026.pptx` | Latest framing: map PLEF sectors to PBCC (Transport, Housing, Consumption); three ways change is distributed (reduced carbon factors, uniform, skewed S-curve adoption with a "tuning" and a "prioritisation" variable); decile spread of current emissions (e.g. car 2.9×, gas 2.4×, flights 2.3× top vs bottom decile). |
| `original PLEF/Downscaling Examples.docx/.xlsx` | Worked toy examples: uniform %, flat share, "more equitable", propensity-based; and the Individual/Technology/Area-led × Uniform/Equity/Propensity framing. |
| `original PLEF/PLEF Downscaling.xlsx` | Every PLEF policy scored for carbon effect, local variability and ease of downscaling. |
| `original PLEF/Downscaling_Review_Paper_Scoping_v1…docx` | Scoping for a (systematic) review paper on downscaling methods. |

**Gap:** there is no residential equivalent of the transport workbook. The residential pathways came from the National Household Model (NHM), and we only have what is printed in the report appendix.

### 2.2 In Carbon & Place (`../build`)

The build pipeline is a large `targets` project (~300 targets) producing annual LSOA21/DZ22 data for GB. Its local store (`../build/_targets`) already holds the objects we need, so this project can read them directly. Relevant targets:

| Theme | Targets | Use here |
|---|---|---|
| Geography | `bounds_lsoa_GB_*`, `lookup_*`, `lsoa_admin`, `area_classifications`, `oac*`, `inputdata/rural_urban` | Spatial units, LA aggregation, area types |
| Population | `population` (LSOA × year, households, adults), `household_clusters` | Weights and demographics |
| Emissions baseline | `lsoa_emissions_all` (per-capita and total by domain, 2010–2022) | Starting point for every measure; equity ranking |
| Housing | `epc_dom_summary` (EPC band, dwelling type, tenure, age, wall/roof/floor/heating ratings, main fuel, floor area), `retrofit_lsoa_data`, `central_heating_2021` (census heating type incl. heat pumps and DH), `domestic_gas`, `domestic_electricity`, `other_heating_emissions`, `house_prices*`, `income_lsoa_msoa`, `bills_*` | Heat demand, insulation status, HP/DH suitability, capacity to pay |
| Transport | `vehicle_summary` (cars per household, BEV/ULEV share, 2011–2024), `car_km_pc` and `car_emissions` (MOT-based km and CO2), `pt_frequency`, `access_proximity` (15–60 min access to services), `travel2work`, `dl_pct` (Propensity to Cycle Tool), `nts`, `flights_lsoa_emissions` | Baseline car use and ownership, EV uptake history, alternatives available |
| Existing PLEF work | `oldCode/plef.R` (commented-out `PLEF`, `PLEF_emissions` targets) and `inputdata/PLEF/` (`PLEF Tables.xlsx`, `CREDS-leds-data.xlsx`) | A first "grandfathered" and "equal per-capita by 2050" sector-level split. Good baseline comparison, superseded by this project. |

Sibling repos that matter: `inputdata` / `inputdatasecure` (raw inputs), `PublicTransportAnalysis` (bus/rail frequency), `outputdata` (published bulk outputs).

## 3. Conceptual model

### 3.1 Three kinds of change

Every PLEF assumption we downscale is classed as one of:

1. **Carbon factor change** (same activity, cleaner energy): grid intensity, vehicle efficiency. Applied uniformly; no local variation.
2. **Technology adoption** (a share from 0 to a ceiling, S-shaped): heat pumps, district heating, fabric retrofit measures, BEV share of the car fleet, (possibly) solar thermal.
3. **Activity change** (a continuous quantity that rises or falls): car km per person, cars per household, mode shares by purpose, trips avoided by telework/4-day week, heat demand per dwelling, (aviation km).

Type 1 is easy. Types 2 and 3 are the core of the research.

### 3.2 Adoption curves for type 2

For measure *m*, LSOA *i*, year *t*:

`a_im(t) = c_im / (1 + exp(-k_im (t - τ_m(t) - δ · p_im)))`

- `c_im` **ceiling**: technical maximum share in that area (e.g. HP-compatible dwellings from EPC dwelling type using PLEF's own compatibility shares; DH ceiling ≈ 0 below a heat-density threshold).
- `p_im` **prioritisation score** (−1…+1): early or late adopter, built from weighted local factors (section 4).
- `δ` **spread** (the "tuning variable"): years between the earliest and latest adopters.
- `k_im` steepness, bounded so no LSOA exceeds a maximum annual change (e.g. ≤10 percentage points/yr for HPs).
- `τ_m(t)` national midpoint, **solved each year** (1-D root finding) so that `Σ w_i a_im(t) = N_m(t)`, the PLEF national value. Monotonic in τ, so `uniroot` always works and the national constraint holds exactly.

Starting value: each LSOA's observed 2021–2024 level (e.g. census 2021 heat pumps, Q1 2024 BEV share). The curve is fitted to pass through it, so current leaders stay ahead unless the approach says otherwise.

### 3.3 Allocation for type 3

Activity changes are allocated as a reduction (or increase) share per LSOA, generalising the toy examples:

`x_i(t) = x_i(t0) · (1 - r_i(t))`, with `Σ w_i x_i(t) = N(t)`

where `r_i(t)` combines the national reduction with a propensity tilt, again solved per year for the national total, and bounded (no negative km, no LSOA cutting more than a set % per year, floors such as minimum car use in remote rural areas).

### 3.4 Distributive approaches

Each run combines a measure with one approach:

| Approach | Who goes first / furthest | Score built from |
|---|---|---|
| **Uniform** (reference) | Nobody; every LSOA moves by the national % | – |
| **Capability-based** | Areas most able to change | Feasibility and capacity factors (income, tenure, dwelling type, density, PT/active travel access, trip lengths) |
| **Equity-based** | Highest emitters first; convergence in per-capita emissions | Current per-capita emissions for the relevant domain (from `lsoa_emissions_all`) |
| **Hybrid** | Weighted mix, e.g. need × capability | Both, with a mixing weight α |
| **Trend-continuation** (validation aid) | Whoever is adopting fastest now | Observed recent change (e.g. EV registrations 2018–2024) |

The old `plef.R` "grandfathered" and "equal per capita by 2050" outputs map onto Uniform and an extreme Equity case, so they serve as sanity checks.

### 3.5 Interactions

- **Fabric first:** HP propensity uses the LSOA's insulation level *in that year* (from the retrofit run), so retrofit is downscaled before heat pumps.
- **DH vs HP:** DH is allocated first to dense, high heat-demand areas within its ceiling; HPs fill the remaining heat-decarbonisation target. Both are calibrated together to the PLEF share of low-carbon heat.
- **Car ownership, km and EVs:** mode shift and telework reduce car km; ownership falls with km; BEV share applies to the remaining fleet and km. Emissions = km × (BEV share × grid intensity × kWh/km + ICE share × gCO2/km).
- **Housing emissions:** heat demand (after retrofit and behaviour) × fuel mix (gas/oil/HP/DH) × carbon factors.

## 4. Measures, national targets and local factors

| # | Measure (type) | PLEF national pathway | Unit / weight | Candidate local factors (C&P source; gap) |
|---|---|---|---|---|
| H1 | Fabric retrofit / heat demand per dwelling (2/3) | NHM: 250k (Shift) or 1m (Transform) measures/yr; residential heat demand index (Table A1) | dwellings | EPC band and wall/roof/floor ratings, wall type, dwelling age, tenure, income, house price (`epc_dom_summary`, `retrofit_lsoa_data`, income); **gap:** conservation areas, listed buildings |
| H2 | Heat pumps (2) | HP S-curve on max technical potential (report appendix); UKTM heat outputs if available | dwellings | Dwelling type (houses vs flats), off-gas grid, insulation (H1), income, tenure, floor area (`epc_dom_summary`, `central_heating_2021`, `domestic_gas`); **gap:** MCS/BUS install data, DNO headroom |
| H3 | District heating (2) | Up to 34% of residential heat (cap); actual share by year needed | dwellings | Heat density (gas kWh/ha), flats share, social housing share, non-domestic demand nearby (`nondomestic_gas`), existing communal heating (census); **gap:** heat network zoning pilot areas, existing networks |
| T1 | Telework / 4-day week / trips avoided (3) | TEAM `PassTravel`: `chTrips_*_TeleWork`, `chTrips4dayweek`, teleshop | trips/person | Occupation mix and census 2021 WFH, broadband; **gap:** Ofcom broadband, census occupation |
| T2 | Mode shift to walk/cycle (3) | TEAM mode shares by purpose; two-wheeler ×4–7 | pkm/person | Rural–urban, trip distances (`travel2work`, NTS by area type), PCT Go Dutch (`dl_pct`), `access_proximity`; **gap:** cycle infrastructure (OSM) |
| T3 | Mode shift to bus/rail (3) | TEAM bus ×2.5, rail ×1.8 (Transform) | pkm/person | `pt_frequency`, distance to stations, density, current car ownership vs PT trend line (the Figure 3 idea in Downscaling Examples) |
| T4 | Car ownership (3) | TEAM cars/1000, `BuyFirstCar`/`BuySecondCar` | cars/household | Multi-car households, PT/active access, income, age (`vehicle_summary`, census) |
| T5 | Car km (3, result of T1–T4 + occupancy) | TEAM car veh-km, occupancy | km/person | MOT km (`car_km_pc`), trip lengths |
| T6 | BEV share of car fleet (2) | TEAM/UKTM car stock by fuel | cars | Income, off-street parking proxy (dwelling type), existing ULEV share and trend (`vehicle_summary`), multi-car, km/day; **gap:** chargepoints (NCR) |
| (A) | Aviation (3) | TEAM air pkm (×0.62 by 2050 in Transform) | flights/person | `flights_lsoa_emissions` (income-based); frequent-flyer concentration. Deferred to a later phase |
| C | Grid intensity, vehicle efficiency (1) | `elec_ghg_intensity.xls`, TEAM efficiencies | – | none (uniform) |

Factor weights are a research question in their own right. Plan:

1. Start with literature-informed signs and rough magnitudes (from the AI factor summary, verified against the cited papers).
2. **Calibrate on observed early adoption** where we have history at LSOA level: BEV/ULEV registrations 2011–2024, heat pumps and DH in census 2011 vs 2021 and in EPCs by lodgement date, cycling and WFH in census 2011 vs 2021, EPC improvements over time. Regressing observed uptake on the factors gives empirically grounded weights for the capability approach.
3. Run sensitivity analysis (Monte Carlo over weights, `δ`, max-change limits) and report the robustness of each LSOA's early/late classification.

## 5. Pipeline design (R + targets)

### 5.1 Repo layout

```
downscale-plef/
  _targets.R            # pipeline definition
  parameters.json       # paths: build store, inputdata, secure data; base year; scenarios
  R/                    # functions only, one theme per file
    plef_inputs.R       # read/tidy TEAM, UKTM, report tables
    cp_inputs.R         # read Carbon & Place targets
    factors.R           # build and normalise local factors
    downscale_core.R    # generic S-curve + calibration + allocation engine
    measures_housing.R  # H1-H3 specifics
    measures_transport.R# T1-T6 specifics
    emissions.R         # recombine into LSOA emissions pathways
    analysis.R          # typologies, policy indicators
    outputs.R           # maps, bulk CSV, C&P-compatible JSON
  data/                 # raw PLEF inputs (as now) + transcribed tables as CSV
  reports/              # Quarto notebooks rendered by tarchetypes
  tests/testthat/       # unit tests for the engine
  docs/                 # plans, notes, literature
  renv.lock
```

### 5.2 Target groups

1. **`plef_*`**: one tidy long table `plef_pathways` (scenario, year, measure, value, unit, source), annual, interpolating 5-yearly points where needed. Scenario mapping is one small lookup table.
2. **`cp_*`**: read C&P objects with `targets::tar_read(name, store = file.path(path_build, "_targets"))`, wrapped in `format = "file"` hash tracking so a rebuild of C&P triggers ours. Assemble `lsoa_baseline` (one row per LSOA, base year).
3. **`factors_*`**: per-measure factor tables, normalised to ranks or z-scores, then combined into `p_im` for each approach.
4. **`downscale_*`**: `tarchetypes::tar_map()` over measure × scenario × approach (about 9 × 3 × 4 ≈ 100 branches), each returning LSOA × year results plus a calibration check (national sum error = 0).
5. **`emissions_*`**: housing and transport kgCO2e per capita by LSOA, year, scenario and approach.
6. **`analysis_*`**: adopter typologies, per-LSOA required annual rate vs recent observed rate ("acceleration needed"), residual 2050 emissions, LA and OAC summaries.
7. **`outputs_*`**: maps, bulk CSV/parquet, Quarto report, and later JSON/PMTiles using C&P's export functions.

### 5.3 Engineering conventions

- `renv` for package versions; R ≥ 4.3.3 to match `build`.
- `testthat` tests for the engine, starting by reproducing `Downscaling Examples.xlsx`, plus property tests (national sums match, bounds hold, monotonic where required).
- Every downscaled output carries a calibration diagnostic; the pipeline errors if any national sum is off by more than a tolerance.
- Use `arrow`/parquet for large intermediates: ~42k LSOAs × 30 years × ~100 runs ≈ 125M rows.

## 6. Work plan

| Phase | Content | Output |
|---|---|---|
| 0. Set-up | Repo skeleton, `renv`, `parameters.json`, read-only link to the C&P store, `inputs.md` data audit | Running empty pipeline |
| 1. National pathways | Extract TEAM transport pathways; transcribe report appendix tables; obtain NHM residential pathways; fix scenario mapping; rebase to observed 2023/24 national values | `plef_pathways` with a validation figure against the report |
| 2. Baseline | Assemble `lsoa_baseline` from C&P; reconcile GB vs UK totals | Baseline atlas notebook |
| 3. Engine | Generic S-curve/allocation engine with tests; toy examples reproduced | `downscale_core.R` + tests |
| 4. Pilot measures | **BEVs (T6)** first (best history for validation), then **heat pumps (H2)** | First maps, validation against 2011–2024 history |
| 5. Remaining measures | H1, H3, T1–T5 (and aviation if in scope) | Full set of measure outputs |
| 6. Emissions & comparison | Recombine; compare approaches and scenarios; sensitivity | Results notebook |
| 7. Policy analysis | Early/late adopter typology; "best option per area"; "no good options" areas; required vs recent rates; LA summaries | Paper draft(s), policy brief |
| 8. C&P integration | Downscaled layer/popup on carbon.place | Tiles + JSON |
| Parallel | Systematic review on downscaling methods (scoping doc) | Review paper |

## 7. Decisions (14 October 2026)

1. **Scenario mapping:** working assumption is LED0 ≈ Ignore/Steer, LED1/LED-HA ≈ Shift, LED2/LED-TC ≈ Transform (LED-RF ≈ reference). Malcolm is confirming with the PLEF authors. The mapping lives in a single lookup table, so it's cheap to change.
2. **Residential pathways:** start with what we have (report appendix tables, UKTM S-curve constraints). Malcolm will try to obtain NHM outputs; the `plef_pathways` table should accept them as a drop-in replacement.
3. **Rebasing:** the downscaled pathways are *PLEF-inspired, not perfectly aligned*. Start from observed national levels around 2025 (from C&P and national statistics) and blend onto the PLEF trajectory and end-points, rather than following PLEF's 2020–2025 values literally. The rebasing method gets documented per measure.
4. **Aviation:** ultimately in scope as part of transport, but deferred to a later phase.
5. **C&P link:** read directly from `../build/_targets` with change tracking, so updates to the build repo flow through. Freeze a versioned extract for publication.

## 8. Remaining open questions

1. **Geography.** GB LSOA21 + DZ22 as in C&P. PLEF is UK-wide, so national targets are scaled to GB by population or households. LSOA population held at the latest estimate, or projected?
2. **Rate limits.** What maximum annual change is plausible per measure (e.g. HPs ≤10 pp/yr of dwellings)? Literature or expert judgement?

## 9. Progress (14 October 2026)

**Done:** Phase 0 (skeleton, `parameters.json`, C&P link), Phase 1 for the pilot measures, Phase 3 (engine with 27 tests), and a first pass of Phase 4 (BEVs, heat pumps, car km). The full pipeline runs in a few minutes: 3 measures × 4 scenarios × 4 approaches = 48 runs over 43,064 GB zones.

**Findings from the pilot:**
- Observed national starting values: BEVs 2.0% of private cars (2025), heat pumps 1.8% of homes (EPC), car km 4,193 per person (2022).
- BEVs in Steer, Shift and Transform cannot hit the rebased national target in some 2030s years under the 10 pp/yr local limit (up to ~6.5 pp short). PLEF implies more than 10 pp/yr nationally after rebasing, so either the limit or the pathway needs revisiting.
- Heat pumps in Shift and Transform fall up to ~2.6 pp short in 2048–50, as many areas reach the compatibility ceiling.
- Heat pump starting values come from EPCs for all of GB, because census central heating has no renewable category in Scotland.
- LA patterns are plausible: Scottish islands and Highland lead on heat pumps; Westminster, Camden and South Cambridgeshire lead on BEVs under the capability approach.

**Next:**
1. Calibrate factor weights against observed early adoption (BEV history 2011–2025; MCS heat pump installs).
2. Remaining measures: district heating (with a density threshold), retrofit/heat demand, telework, mode shift, car ownership.
3. Recombine into emissions and compare approaches.
4. `renv` lockfile; Scotland heating data; NHM pathways when available.
