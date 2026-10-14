# Read Carbon & Place (C&P) build outputs
#
# The C&P build repo (../build) is a targets pipeline. Rather than copying its
# outputs, this project reads objects directly from its targets store. Each
# object is tracked as a file, so when the C&P build updates an object our
# pipeline re-runs everything downstream of it.


#' Make a pair of targets that track and read one C&P object
#'
#' Creates `<name>_file` (format = "file", the path in the C&P store) and
#' `cp_<name>` (the object itself).
#'
#' @param name Name of the target in the C&P build pipeline.
#' @return A list of two target objects.
tar_cp_object = function(name) {
  file_name = paste0("cpfile_", name)
  list(
    targets::tar_target_raw(
      file_name,
      substitute(cp_object_path(parameters, N), list(N = name)),
      format = "file"
    ),
    targets::tar_target_raw(
      paste0("cp_", name),
      substitute(cp_read(F), list(F = as.symbol(file_name)))
    )
  )
}

cp_object_path = function(parameters, name) {
  path = file.path(parameters$path_build, "_targets", "objects", name)
  if (!file.exists(path)) stop("C&P object not found: ", path,
                               ". Has it been built in the build repo?")
  path
}

cp_read = function(path) {
  x = readRDS(path)
  if (inherits(x, "grouped_df")) x = dplyr::ungroup(x)
  as.data.frame(x)
}

# Latest year in which a (zone, year) table covers at least `min_share` of
# the zones present in its most complete year.
latest_complete_year = function(df, value_col, min_share = 0.99) {
  ok = !is.na(df[[value_col]])
  n = tapply(ok, df$year, sum)
  yrs = as.integer(names(n))[n >= min_share * max(n)]
  max(yrs)
}

safe_div = function(a, b) ifelse(is.na(b) | b <= 0, NA_real_, a / b)


#' Build the LSOA baseline table
#'
#' One row per GB LSOA21 / DZ22 with the weights, starting values and local
#' factors used by the pilot measures. Each input uses its latest complete
#' year; `base_years` records which.
#'
#' @return List with `data` (data frame) and `base_years` (named integer).
build_lsoa_base = function(cp_population, cp_vehicle_summary, cp_epc_dom_summary,
                           cp_income_lsoa_msoa, cp_income_scot_dz22,
                           cp_lsoa_emissions_all, cp_lsoa_admin) {
  yrs = c(
    population = latest_complete_year(cp_population, "all_ages"),
    vehicles = latest_complete_year(cp_vehicle_summary, "Cars_Licensed_PRIVATE"),
    emissions = latest_complete_year(cp_lsoa_emissions_all, "car_km"),
    income_ew = max(cp_income_lsoa_msoa$year),
    income_scot = max(cp_income_scot_dz22$year)
  )

  pop = cp_population[cp_population$year == yrs[["population"]],
                      c("LSOA21CD", "all_ages", "households_est")]
  names(pop) = c("LSOA21CD", "population", "households")

  veh = cp_vehicle_summary[cp_vehicle_summary$year == yrs[["vehicles"]], ]
  veh = data.frame(
    LSOA21CD = veh$LSOA21CD,
    cars = veh$Cars_Licensed_PRIVATE,
    bev = veh$BEV_PRIVATE
  )
  veh$bev_share = pmin(safe_div(veh$bev, veh$cars), 1)

  e = cp_epc_dom_summary
  houses = rowSums(e[, grepl("^type_(house|bungalow)_", names(e))], na.rm = TRUE)
  flats = rowSums(e[, c("type_flat", "type_maisonette")], na.rm = TRUE)
  tenure_known = e$tenure_owner + e$tenure_privaterent + e$tenure_socialrent
  epc = data.frame(
    LSOA21CD = e$LSOA21CD,
    epc_total = e$epc_total,
    epc_score = e$epc_score_avg,
    houses_share = safe_div(houses, e$epc_total),
    flats_share = safe_div(flats, e$epc_total),
    owner_share = safe_div(e$tenure_owner, tenure_known),
    socialrent_share = safe_div(e$tenure_socialrent, tenure_known),
    offgas_share = 1 - safe_div(e$mainfuel_mainsgas, e$epc_total),
    hp_share = safe_div(e$mainheatdesc_heatpump, e$epc_total),
    dh_share = safe_div(e$mainheatdesc_community, e$epc_total)
  )

  inc_ew = cp_income_lsoa_msoa[cp_income_lsoa_msoa$year == yrs[["income_ew"]],
                               c("LSOA21CD", "total_annual_income")]
  inc_s = cp_income_scot_dz22[cp_income_scot_dz22$year == yrs[["income_scot"]],
                              c("DataZone22", "total_annual_income")]
  names(inc_s)[1] = "LSOA21CD"
  inc = rbind(inc_ew, inc_s)
  names(inc)[2] = "income"

  em = cp_lsoa_emissions_all[cp_lsoa_emissions_all$year == yrs[["emissions"]], ]
  em = data.frame(
    LSOA21CD = em$LSOA21CD,
    car_km = em$car_km,
    car_kgco2e_pc = em$car_kgco2e_percap,
    heat_kgco2e_pc = rowSums(cbind(em$dom_gas_kgco2e_percap,
                                   em$heating_other_kgco2e_percap), na.rm = TRUE)
  )

  admin = cp_lsoa_admin[, c("LSOA21CD", "LAD25CD", "LAD25NM")]

  d = Reduce(function(a, b) merge(a, b, by = "LSOA21CD", all.x = TRUE),
             list(admin, pop, veh, epc, inc, em))
  d$country = substr(d$LSOA21CD, 1, 1)
  d$cars_per_household = safe_div(d$cars, d$households)
  # car_km comes from the emissions year; use that year's population would be
  # better, but the difference is small and the base year is recorded.
  d$car_km_pc = safe_div(d$car_km, d$population)
  list(data = d, base_years = yrs)
}
