# Downscaling the CREDS Positive Low Energy Futures (PLEF) to LSOAs
# Run with targets::tar_make(); see README.md

library(targets)
library(tarchetypes)

tar_option_set(
  packages = c("dplyr", "tidyr", "readxl", "ggplot2"),
  format = "rds"
)

tar_source()

# Static settings for the branched part of the pipeline
MEASURES = c("bev", "hp", "car_km")
SCENARIOS = c("Ignore", "Steer", "Shift", "Transform")
APPROACHES = c("uniform", "capability", "equity", "hybrid")

C_AND_P_OBJECTS = c("population", "vehicle_summary", "epc_dom_summary",
                    "income_lsoa_msoa", "income_scot_dz22",
                    "lsoa_emissions_all", "lsoa_admin")

# One input-preparation target per measure
inputs_map = tar_map(
  values = list(measure = MEASURES),
  names = "measure",
  tar_target(inputs, prep_measure(lsoa_base, measure_specs()[[measure]],
                                  epc_year = parameters$epc_year))
)

# Every measure x scenario x approach
runs = expand.grid(measure = MEASURES, scenario = SCENARIOS,
                   approach = APPROACHES, stringsAsFactors = FALSE)
runs$inputs = rlang::syms(paste0("inputs_", runs$measure))

downscale_map = tar_map(
  values = runs,
  names = c("measure", "scenario", "approach"),
  tar_target(ds, run_downscale(inputs, plef_pathways, measure_specs()[[measure]],
                               scenario, approach,
                               end_year = parameters$end_year,
                               converge_year = parameters$converge_year)),
  tar_target(sm, summarise_downscale(ds, inputs, measure_specs()[[measure]]$type))
)

list(
  # Settings -----------------------------------------------------------------
  tar_target(param_file, "parameters.json", format = "file"),
  tar_target(parameters, jsonlite::read_json(param_file, simplifyVector = TRUE)),

  # National PLEF pathways ---------------------------------------------------
  tar_target(team_file, "data/LED_TRN_analysis_v2.xlsx", format = "file"),
  tar_target(uktm_elec_file, "data/elec_ghg_intensity.xls", format = "file"),
  tar_target(plef_tables_file, file.path(parameters$path_data, "PLEF", "PLEF Tables.xlsx"),
             format = "file"),

  tar_target(plef_heat, read_plef_heat_tech(plef_tables_file)),
  tar_target(plef_car_vkm, read_plef_car_vkm(plef_tables_file)),
  tar_target(team_passtravel, read_team_passtravel(team_file)),
  tar_target(team_sociodem, read_team_sociodem(team_file)),
  tar_target(team_car_stock, read_team_car_stock(team_file)),
  tar_target(uktm_grid, read_uktm_grid_intensity(uktm_elec_file)),

  tar_target(plef_pathways, build_plef_pathways(plef_heat, plef_car_vkm, team_passtravel,
                                                team_sociodem, team_car_stock, uktm_grid)),

  # Carbon & Place inputs (read from ../build/_targets) -------------------------
  lapply(C_AND_P_OBJECTS, tar_cp_object),

  tar_target(lsoa_base, build_lsoa_base(cp_population, cp_vehicle_summary,
                                        cp_epc_dom_summary, cp_income_lsoa_msoa,
                                        cp_income_scot_dz22, cp_lsoa_emissions_all,
                                        cp_lsoa_admin)),

  # Downscaling ----------------------------------------------------------------
  inputs_map,
  downscale_map,

  tar_combine(ds_national, downscale_map[["sm"]],
              command = dplyr::bind_rows(lapply(list(!!!.x), `[[`, "national"))),
  tar_combine(ds_distribution, downscale_map[["sm"]],
              command = dplyr::bind_rows(lapply(list(!!!.x), `[[`, "distribution"))),
  tar_combine(ds_timing, downscale_map[["sm"]],
              command = dplyr::bind_rows(lapply(list(!!!.x), `[[`, "timing"))),
  tar_combine(ds_lsoa_wide, downscale_map[["ds"]],
              command = lsoa_wide(list(!!!.x), years = c(2030, 2040, 2050))),

  tar_target(la_summary, summarise_la(ds_timing[ds_timing$measure %in%
                                                  c("bev_share", "hp_share_heat"), ],
                                      ds_national)),

  # Outputs ------------------------------------------------------------------
  tar_target(out_pathways_csv, write_output_csv(plef_pathways, "plef_pathways.csv"),
             format = "file"),
  tar_target(out_national_csv, write_output_csv(ds_national, "downscale_national_check.csv"),
             format = "file"),
  tar_target(out_distribution_csv, write_output_csv(ds_distribution, "downscale_distribution.csv"),
             format = "file"),
  tar_target(out_la_csv, write_output_csv(la_summary, "la_summary.csv"), format = "file"),
  tar_target(out_lsoa_csv, write_output_csv(ds_lsoa_wide, "lsoa_downscaled_2030_2040_2050.csv"),
             format = "file"),
  tar_target(out_pathways_plot, save_output_plot(plot_pathways(plef_pathways),
                                                 "plef_pathways.png"), format = "file"),
  tar_map(
    values = list(m = c("bev_share", "hp_share_heat", "car_vkm_index")),
    names = "m",
    tar_target(out_dist_plot,
               save_output_plot(plot_distribution(ds_distribution, ds_national, m),
                                paste0("distribution_", m, ".png"), height = 9),
               format = "file")
  )
)
