# Read and tidy the national PLEF pathways
#
# Sources:
# * PLEF Tables.xlsx (inputdata/PLEF): tables transcribed from the 2021
#   report, four scenarios (Ignore, Steer, Shift, Transform), 5-yearly.
# * LED_TRN_analysis_v2.xlsx (data/): TEAM-UK transport model, annual,
#   policies LED0 (BAU), LED1 (High Ambition), LED2 (Transformative).
# * elec_ghg_intensity.xls (data/): UKTM grid intensity, LED-RF/HA/TC.


#' Lookup between PLEF scenario names and model run codes
#'
#' Working assumption (to be confirmed with the PLEF authors): TEAM LED0 is
#' the service-demand case for Ignore and Steer (Steer has the same service
#' demand as Ignore), LED1 is Shift and LED2 is Transform. UKTM LED-RF is the
#' reference run, used for Ignore and Steer.
scenario_lookup = function() {
  data.frame(
    scenario = c("Ignore", "Steer", "Shift", "Transform"),
    team = c("LED0", "LED0", "LED1", "LED2"),
    uktm = c("LED-RF", "LED-RF", "LED-HA", "LED-TC")
  )
}

# "–" and similar placeholders in the report tables mean zero
as_num = function(x) {
  x = suppressWarnings(as.numeric(as.character(x)))
  x[is.na(x)] = 0
  x
}


#' Residential useful heat by technology (report Figure A6)
#'
#' @param path Path to `PLEF Tables.xlsx`.
#' @return Long data frame: scenario, technology, year, pj.
read_plef_heat_tech = function(path) {
  x = readxl::read_excel(path, sheet = "A6")
  x = tidyr::pivot_longer(x, -c(Scenario, Technology), names_to = "year",
                          values_to = "pj", values_transform = list(pj = as.character))
  data.frame(scenario = x$Scenario, technology = x$Technology,
             year = as.integer(x$year), pj = as_num(x$pj))
}


#' Car vehicle km by fuel (report Figure A5a)
#'
#' @param path Path to `PLEF Tables.xlsx`.
#' @return Long data frame: scenario, year, fuel, bvkm (billion vehicle km).
read_plef_car_vkm = function(path) {
  x = readxl::read_excel(path, sheet = "A5a")
  x = tidyr::pivot_longer(x, -c(Scenario, Year), names_to = "fuel",
                          values_to = "bvkm", values_transform = list(bvkm = as.character))
  data.frame(scenario = x$Scenario, year = as.integer(x$Year), fuel = x$fuel,
             bvkm = as_num(x$bvkm))
}


#' TEAM-UK passenger travel table (annual, by journey purpose)
#'
#' @param path Path to `LED_TRN_analysis_v2.xlsx`.
#' @return Wide data frame, one row per policy (LED0/1/2) and year.
read_team_passtravel = function(path) {
  x = readxl::read_excel(path, sheet = "PassTravel")
  x = x[!is.na(x$PolicyNA) & !is.na(x$Year), ]
  # Only the first block of columns is the annual table; later columns are
  # pivot-table workings in the spreadsheet.
  keep = seq_len(which(names(x) == "OR_avg")[1])
  x = as.data.frame(x[, keep])
  names(x)[names(x) == "PolicyNA"] = "team"
  names(x)[names(x) == "Year"] = "year"
  x$year = as.integer(x$year)
  x[x$year <= 2050, ]
}


#' TEAM-UK socio-demographic assumptions (identical across scenarios)
read_team_sociodem = function(path) {
  x = readxl::read_excel(path, sheet = "SocioDem")
  x = as.data.frame(x[!is.na(x$Year), c("Year", "Pop", "NHH_tot", "shPopTeleWork")])
  names(x) = c("year", "population", "households", "share_telework")
  x$year = as.integer(x$year)
  x[x$year <= 2050, ]
}


#' TEAM-UK car stock by fuel and hybrid type
#'
#' @return Data frame: team, year, cars_total, cars_bev.
read_team_car_stock = function(path) {
  x = readxl::read_excel(path, sheet = "NumVeh", range = readxl::cell_cols("A:L"))
  x = x[x$VehicleType == "Car" & x$VehicleCategory == "Total", ]
  x$bev = x$Fuel == "Electricity" & x$Hybrid == "Non-hybrid"
  g = dplyr::summarise(dplyr::group_by(x, team = TDVSNA, year = as.integer(Year)),
                       cars_total = sum(Value), cars_bev = sum(Value[bev]),
                       .groups = "drop")
  as.data.frame(g[g$year <= 2050, ])
}


#' UKTM grid carbon intensity (gCO2e/kWh)
#'
#' @param path Path to `elec_ghg_intensity.xls`.
#' @return Data frame: uktm, year, gco2e_per_kwh.
read_uktm_grid_intensity = function(path) {
  x = readxl::read_excel(path, sheet = "TAB_EMIS-CO2", col_names = FALSE)
  x = as.data.frame(x)
  # readxl drops empty leading columns, so locate the label column by content
  lab = which(vapply(x, function(col) any(col %in% "Scenario"), logical(1)))[1]
  ycols = (lab + 1):(lab + 9)
  hdr = which(x[[lab]] == "Scenario")[1]
  years = as.integer(unlist(x[hdr, ycols]))
  start = which(grepl("^Grid intensity", x[[lab]]))[1]
  rows = x[(start + 1):nrow(x), ]
  rows = rows[!is.na(rows[[lab]]) & grepl("^LED", rows[[lab]]), ]
  do.call(rbind, lapply(seq_len(nrow(rows)), function(i) {
    data.frame(uktm = sub("_ghg100$", "", rows[i, lab]), year = years,
               gco2e_per_kwh = as.numeric(unlist(rows[i, ycols])))
  }))
}


# Linear interpolation of a 5-yearly series to annual values
to_annual = function(df, value = "value", years = 2020:2050,
                     group = c("scenario", "measure", "unit", "source")) {
  sp = split(df, interaction(df[group], drop = TRUE))
  do.call(rbind, lapply(sp, function(d) {
    d = d[order(d$year), ]
    y = years[years >= min(d$year) & years <= max(d$year)]
    res = d[rep(1, length(y)), group, drop = FALSE]
    res$year = y
    res[[value]] = stats::approx(d$year, d[[value]], xout = y, rule = 1)$y
    res
  }))
}


#' Assemble the national pathways table
#'
#' One tidy table of annual national values per scenario and measure. Shares
#' are fractions (0-1); activity measures are per person or per household.
#'
#' Measures:
#' * `bev_share`: battery-electric share of car vehicle km (report A5a).
#' * `hp_share_heat`: heat pump share of residential useful heat (A6).
#' * `dh_share_heat`: heat network share of residential useful heat (A6).
#' * `res_heat_index`: total residential useful heat, index 2020 = 1 (A6).
#' * `car_vkm_index`: car vehicle km per person, index 2020 = 1 (A5a and
#'   TEAM population).
#' * `pkm_pp_<mode>`: TEAM passenger km per person per year by mode.
#' * `cars_per_household`: TEAM car stock per household.
#' * `grid_gco2e_kwh`: UKTM grid intensity.
#'
#' @return Data frame: scenario, measure, year, value, unit, source.
build_plef_pathways = function(plef_heat, plef_car_vkm, team_passtravel,
                               team_sociodem, team_car_stock, uktm_grid,
                               scenarios = scenario_lookup()) {
  out = list()

  # Heating technology shares
  heat = plef_heat
  heat$group = dplyr::case_when(
    grepl("heat pump|HP", heat$technology, ignore.case = TRUE) ~ "hp",
    heat$technology == "Network heat" ~ "dh",
    TRUE ~ "other")
  h = dplyr::summarise(dplyr::group_by(heat, scenario, year),
                       total = sum(pj), hp = sum(pj[group == "hp"]),
                       dh = sum(pj[group == "dh"]), .groups = "drop")
  h = dplyr::group_by(h, scenario)
  h = dplyr::mutate(h, idx = total / total[year == 2020])
  h = as.data.frame(h)
  out$hp = data.frame(scenario = h$scenario, measure = "hp_share_heat", year = h$year,
                      value = h$hp / h$total, unit = "share", source = "PLEF report A6")
  out$dh = data.frame(scenario = h$scenario, measure = "dh_share_heat", year = h$year,
                      value = h$dh / h$total, unit = "share", source = "PLEF report A6")
  out$heat = data.frame(scenario = h$scenario, measure = "res_heat_index", year = h$year,
                        value = h$idx, unit = "index_2020", source = "PLEF report A6")

  # Cars: BEV share and vkm per person
  pop = team_sociodem[, c("year", "population", "households")]
  cv = dplyr::summarise(dplyr::group_by(plef_car_vkm, scenario, year),
                        total = sum(bvkm), bev = sum(bvkm[fuel == "Electric"]),
                        .groups = "drop")
  cv = merge(as.data.frame(cv), pop, by = "year")
  cv$vkm_pp = cv$total * 1e9 / cv$population
  cv = dplyr::mutate(dplyr::group_by(cv, scenario), idx = vkm_pp / vkm_pp[year == 2020])
  cv = as.data.frame(cv)
  out$bev = data.frame(scenario = cv$scenario, measure = "bev_share", year = cv$year,
                       value = cv$bev / cv$total, unit = "share", source = "PLEF report A5a")
  out$vkm = data.frame(scenario = cv$scenario, measure = "car_vkm_index", year = cv$year,
                       value = cv$idx, unit = "index_2020", source = "PLEF report A5a")

  out = lapply(out, to_annual)

  # TEAM: annual already. Map policies to scenarios. The td_* columns are
  # distance travelled per person per year in miles (NTS convention; the
  # 2017 total is ~6,600 miles per person).
  tp = team_passtravel
  modes = c(car_driver = "td_card", car_passenger = "td_carp", bus = "td_bus",
            rail = "td_rail", walk = "td_walk", bike = "td_bike")
  modes = modes[modes %in% names(tp)]
  team_long = do.call(rbind, lapply(names(modes), function(m) {
    data.frame(team = tp$team, year = tp$year, measure = paste0("pkm_pp_", m),
               value = tp[[modes[[m]]]] * 1.609344,
               unit = "km_per_person", source = "TEAM-UK PassTravel")
  }))
  cs = merge(team_car_stock, pop, by = "year")
  team_long = rbind(team_long, data.frame(
    team = cs$team, year = cs$year, measure = "cars_per_household",
    value = cs$cars_total / cs$households, unit = "cars_per_household",
    source = "TEAM-UK NumVeh"))
  team_long = merge(team_long, scenarios[, c("scenario", "team")], by = "team")
  team_long$team = NULL
  out$team = team_long[team_long$year >= 2020, ]

  g = merge(uktm_grid, scenarios[, c("scenario", "uktm")], by = "uktm")
  g = data.frame(scenario = g$scenario, measure = "grid_gco2e_kwh", year = g$year,
                 value = g$gco2e_per_kwh, unit = "gCO2e_per_kWh", source = "UKTM")
  out$grid = to_annual(g)

  res = do.call(rbind, out)
  rownames(res) = NULL
  res = res[order(res$measure, res$scenario, res$year),
            c("scenario", "measure", "year", "value", "unit", "source")]
  res
}


#' Rebase a national pathway to an observed starting value
#'
#' PLEF starts in 2020 and the world has moved on, so the downscaled pathways
#' are "PLEF-inspired" rather than exact. Two methods:
#' * `blend` (shares): start at the observed value and close the gap to the
#'   PLEF trajectory linearly by `converge_year`, then follow PLEF. Keeps the
#'   PLEF end-point; adoption shares are kept non-decreasing.
#' * `relative` (activity): apply PLEF's relative change from the base year to
#'   the observed starting value.
#'
#' @param path Data frame with `year` and `value` for one scenario/measure.
#' @param observed Observed national value in `base_year`.
#' @return Data frame: year, plef, target.
rebase_pathway = function(path, observed, base_year, end_year = 2050,
                          converge_year = 2040, method = c("blend", "relative")) {
  method = match.arg(method)
  path = path[order(path$year), ]
  years = base_year:end_year
  p = stats::approx(path$year, path$value, xout = years, rule = 2)$y
  if (method == "blend") {
    w = pmax(0, 1 - (years - base_year) / (converge_year - base_year))
    target = p + (observed - p[1]) * w
    target = pmin(pmax(cummax(target), 0), 1)
  } else {
    target = observed * p / p[1]
  }
  data.frame(year = years, plef = p, target = target)
}
