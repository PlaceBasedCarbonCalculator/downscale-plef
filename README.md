# downscale-plef

Downscaling the CREDS [Positive Low Energy Futures](https://low-energy.creds.ac.uk/) (PLEF) national scenarios to Lower Super Output Areas (LSOA21 in England and Wales, Data Zones 2022 in Scotland) for housing and transport. The aim is to show where in Great Britain each change is likely to come early or late, and what that means for policy.

The pipeline is written in R and uses [targets](https://books.ropensci.org/targets/). It reads local data from the [Carbon & Place](https://www.carbon.place) build pipeline. See [`docs/plan.md`](docs/plan.md) for the research plan and decisions.

## Setup

This repo expects to sit next to the Carbon & Place repos:

```
PlaceBasedCarbonCalculator/
  build/          # C&P pipeline, with its _targets store built
  inputdata/      # needs inputdata/PLEF/PLEF Tables.xlsx
  downscale-plef/ # this repo
```

Paths are set in [`parameters.json`](parameters.json):

| key | meaning |
|---|---|
| `path_build` | the C&P build repo; objects are read from `<path_build>/_targets/objects/` |
| `path_data` | the C&P `inputdata` repo |
| `end_year` | last year modelled |
| `converge_year` | year by which rebased pathways rejoin the PLEF trajectory |
| `epc_year` | base year assigned to EPC-derived starting values |

Packages: `targets`, `tarchetypes`, `dplyr`, `tidyr`, `readxl`, `ggplot2`, `jsonlite`, `rlang`, and `testthat` for the tests.

```r
install.packages(c("targets", "tarchetypes", "dplyr", "tidyr", "readxl",
                   "ggplot2", "jsonlite", "rlang", "testthat"))
```

Using `renv` to pin these is recommended: run `renv::init()` once and commit `renv.lock`.

## Running

```r
library(targets)
tar_make()           # whole pipeline, a few minutes
tar_read(plef_pathways)
tar_visnetwork()
```

Tests for the downscaling engine:

```sh
Rscript tests/run_tests.R
```

## How it works

1. **National pathways** (`R/plef_inputs.R`). The pipeline builds a tidy annual table, `plef_pathways`, with one row per scenario, measure and year, from:
   - the PLEF report tables (`inputdata/PLEF/PLEF Tables.xlsx`);
   - the TEAM-UK transport model (`data/LED_TRN_analysis_v2.xlsx`);
   - UKTM grid intensity (`data/elec_ghg_intensity.xls`).

   Scenario mapping is a working assumption and lives in `scenario_lookup()`: TEAM LED0 is Ignore/Steer, LED1 is Shift and LED2 is Transform.
2. **Carbon & Place inputs** (`R/cp_inputs.R`). Objects are read straight from the C&P targets store. Each object is tracked as a file, so rebuilding C&P triggers a rebuild here. `lsoa_base` holds one row per LSOA with the weights, starting values and local factors.
3. **Rebasing.** National pathways start from observed values around the base year and blend onto the PLEF trajectory by `converge_year` (for shares), or apply PLEF's relative change (for activity measures). The results are PLEF-inspired, not an exact copy.
4. **Downscaling engine** (`R/downscale_core.R`). There are two methods:
   - Adoption shares follow per-LSOA S-curves between the observed base and a technical ceiling.
   - Activity levels change multiplicatively.

   A single national progress parameter is solved each year so the weighted LSOA mean matches the national target exactly. A prioritisation score (−1 to +1) makes areas move faster or slower. Per-LSOA rate limits (maximum annual change, floors, no un-adoption) apply inside the solve, so years that cannot meet the target within the limits are flagged rather than silently missed.
5. **Measures and approaches** (`R/measures.R`). Every measure is run under each scenario (Ignore, Steer, Shift, Transform) and each distributive approach:
   - `uniform`: the same speed everywhere;
   - `capability`: areas most able to change go first;
   - `equity`: the highest emitters go first;
   - `hybrid`: a 50/50 mix of capability and equity.

## Current pilot measures

| measure | national pathway | LSOA start | weight | ceiling / limits |
|---|---|---|---|---|
| `bev` | BEV share of car km (report A5a) | private BEVs ÷ private licensed cars, 2025 (DfT via C&P) | private cars | 100%; ≤10 pp/yr |
| `hp` | heat pump share of residential heat (report A6) | EPC main heating = heat pump | households | PLEF HP compatibility: 80.5% of houses, 11.5% of flats; ≤8 pp/yr |
| `car_km` | car km per person, PLEF relative change (report A5a) | C&P MOT-based car km per person, 2022 | population | floor 30% of base; ≤12%/yr |

Factor weights are first guesses and are expected to be calibrated against observed early adoption.

## Outputs (`outputs/`)

- `plef_pathways.csv`, `plots/plef_pathways.png`: national pathways.
- `downscale_national_check.csv`: target vs achieved for every run and year, with a `status` column (`target_above_feasible` marks years the rate limits could not deliver).
- `downscale_distribution.csv`, `plots/distribution_*.png`: LSOA percentiles over time.
- `la_summary.csv`: local authority means and shares of early and late adopter LSOAs.
- `lsoa_downscaled_2030_2040_2050.csv`: every LSOA, measure, scenario and approach. This file is large, is not committed, and is rebuilt by `tar_make()`.

## Licence

GNU Affero General Public License v3.0, as for the Carbon & Place build.
