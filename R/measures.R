# Measure definitions
#
# Each measure says which national pathway it follows, how the LSOA starting
# value, ceiling and weight are built, the rate limits, and the local factors
# behind each distributive approach. Factor weights are signed: positive means
# a higher value makes the area move earlier/faster in the direction of the
# national change. Weights are first guesses from the literature summary in
# docs/AI Summary of Factors.docx and are expected to be calibrated later
# against observed early adoption.

# PLEF/UKTM maximum share of dwellings compatible with a heat pump (report
# Shelter appendix): cavity/solid houses 82%/79%, cavity/solid flats 13%/10%.
HP_COMPAT_HOUSE = 0.805
HP_COMPAT_FLAT = 0.115

measure_specs = function() {
  list(
    bev = list(
      label = "Battery electric share of private cars",
      type = "adoption",
      pathway = "bev_share",
      rebase = "blend",
      value = function(d) d$bev_share,
      ceiling = function(d) rep(1, nrow(d)),
      weight = function(d) d$cars,
      max_step = 0.10, spread = 0.6, seed = 0.002,
      base_year_from = "vehicles",
      capability = data.frame(
        factor = c("income", "houses_share", "bev_share", "cars_per_household"),
        weight = c(1, 1, 1, 0.5)),
      equity = data.frame(factor = "car_kgco2e_pc", weight = 1)
    ),
    hp = list(
      label = "Heat pump share of homes",
      type = "adoption",
      pathway = "hp_share_heat",
      rebase = "blend",
      value = function(d) d$hp_share,
      ceiling = function(d) {
        c = HP_COMPAT_HOUSE * d$houses_share + HP_COMPAT_FLAT * d$flats_share
        c[is.na(c)] = HP_COMPAT_HOUSE * 0.8 + HP_COMPAT_FLAT * 0.2
        c
      },
      weight = function(d) d$households,
      max_step = 0.08, spread = 0.6, seed = 0.002,
      base_year_from = "epc",
      capability = data.frame(
        factor = c("income", "houses_share", "owner_share", "epc_score",
                   "offgas_share", "hp_share"),
        weight = c(1, 1, 0.5, 1, 1, 0.5)),
      equity = data.frame(factor = "heat_kgco2e_pc", weight = 1)
    ),
    car_km = list(
      label = "Car km per person",
      type = "activity",
      pathway = "car_vkm_index",
      rebase = "relative",
      value = function(d) d$car_km_pc,
      floor = function(d) 0.3 * d$car_km_pc,
      weight = function(d) d$population,
      max_step = 0.12, spread = 0.6,
      base_year_from = "emissions",
      capability = data.frame(
        factor = c("flats_share", "cars_per_household", "income"),
        weight = c(1, -1, 0.5)),
      equity = data.frame(factor = "car_kgco2e_pc", weight = 1)
    )
  )
}


#' Prepare the LSOA inputs for one measure
#'
#' @param lsoa_base Output of build_lsoa_base().
#' @param spec One element of measure_specs().
#' @return List: ids, base, ceiling, weight, floor, scores (one per approach),
#'   base_year, observed national value.
prep_measure = function(lsoa_base, spec, epc_year = 2025) {
  d = lsoa_base$data
  w = spec$weight(d)
  v = spec$value(d)
  keep = !is.na(w) & w > 0 & !is.na(v)
  d = d[keep, ]
  w = w[keep]
  v = v[keep]

  base_year = if (spec$base_year_from == "epc") epc_year else
    unname(lsoa_base$base_years[[spec$base_year_from]])

  cap = make_score(d, spec$capability)
  eq = make_score(d, spec$equity)
  scores = list(uniform = rep(0, nrow(d)), capability = cap, equity = eq,
                hybrid = mix_scores(cap, eq, 0.5))

  list(
    ids = d$LSOA21CD, lad = d$LAD25NM, base = v,
    ceiling = if (!is.null(spec$ceiling)) spec$ceiling(d) else NULL,
    floor = if (!is.null(spec$floor)) spec$floor(d) else 0,
    weight = w, scores = scores, base_year = base_year,
    observed = sum(v * w) / sum(w),
    n_dropped = sum(!keep)
  )
}


#' Run one measure x scenario x approach
#'
#' @return List with `values` (LSOA x year matrix, rownames = LSOA21CD),
#'   `national` (target vs achieved), and metadata.
run_downscale = function(inputs, plef_pathways, spec, scenario, approach,
                         end_year = 2050, converge_year = 2040) {
  path = plef_pathways[plef_pathways$measure == spec$pathway &
                         plef_pathways$scenario == scenario, ]
  if (nrow(path) == 0) stop("No pathway for ", spec$pathway, " / ", scenario)
  nat = rebase_pathway(path, inputs$observed, inputs$base_year, end_year,
                       converge_year, method = spec$rebase)
  score = inputs$scores[[approach]]
  # Uniform: everyone moves at the national speed
  spread = if (approach == "uniform") 0 else spec$spread

  if (spec$type == "adoption") {
    res = downscale_adoption(inputs$base, inputs$ceiling, score, inputs$weight,
                             nat$year, nat$target, spread = spread,
                             max_step = spec$max_step, seed = spec$seed)
  } else {
    res = downscale_activity(inputs$base, score, inputs$weight, nat$year,
                             nat$target, spread = spread,
                             max_step = spec$max_step, floor = inputs$floor)
  }
  res$national$plef = nat$plef
  suppressWarnings(check_calibration(res))
  rownames(res$values) = inputs$ids
  res$measure = spec$pathway
  res$scenario = scenario
  res$approach = approach
  res
}


#' Summarise a downscaled result
#'
#' @return List of data frames: `national` (target, achieved, PLEF),
#'   `distribution` (weighted percentiles by year), `timing` (per LSOA:
#'   year reaching half the 2050 national level, for adoption measures).
summarise_downscale = function(res, inputs, type = "adoption") {
  tag = data.frame(measure = res$measure, scenario = res$scenario,
                   approach = res$approach)
  v = res$values
  years = as.integer(colnames(v))
  probs = c(0.05, 0.25, 0.5, 0.75, 0.95)
  dist = do.call(rbind, lapply(seq_along(years), function(k) {
    q = weighted_quantile(v[, k], inputs$weight, probs)
    data.frame(year = years[k], p05 = q[1], p25 = q[2], p50 = q[3],
               p75 = q[4], p95 = q[5])
  }))
  national = cbind(tag, res$national)
  distribution = cbind(tag, dist)

  # Timing only makes sense for adoption (rising shares)
  if (identical(type, "adoption")) {
    half = res$national$achieved[length(years)] / 2
    reach = apply(v, 1, function(x) {
      i = which(x >= half)[1]
      if (is.na(i)) NA_integer_ else years[i]
    })
  } else {
    reach = rep(NA_integer_, nrow(v))
  }
  timing = data.frame(tag[rep(1, nrow(v)), ], LSOA21CD = rownames(v),
                      LAD25NM = inputs$lad, base = v[, 1],
                      value_2030 = v[, as.character(min(2030, max(years)))],
                      value_2050 = v[, ncol(v)],
                      year_half_national_2050 = reach,
                      max_annual_change = apply(abs(t(diff(t(v)))), 1, max),
                      score = inputs$scores[[res$approach]],
                      row.names = NULL)
  list(national = national, distribution = distribution, timing = timing)
}


weighted_quantile = function(x, w, probs) {
  o = order(x)
  x = x[o]
  w = w[o]
  cw = cumsum(w) / sum(w)
  vapply(probs, function(p) x[which(cw >= p)[1]], numeric(1))
}
