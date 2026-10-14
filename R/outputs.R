# Outputs: CSV tables and summary charts written to outputs/

write_output_csv = function(df, file, dir = "outputs") {
  dir.create(dir, showWarnings = FALSE, recursive = TRUE)
  path = file.path(dir, file)
  utils::write.csv(df, path, row.names = FALSE)
  path
}

save_output_plot = function(p, file, dir = "outputs/plots", width = 10, height = 6) {
  dir.create(dir, showWarnings = FALSE, recursive = TRUE)
  path = file.path(dir, file)
  ggplot2::ggsave(path, p, width = width, height = height, dpi = 150, bg = "white")
  path
}

plot_pathways = function(plef_pathways, measures = c("bev_share", "hp_share_heat",
                                                     "dh_share_heat", "res_heat_index",
                                                     "car_vkm_index", "cars_per_household",
                                                     "grid_gco2e_kwh")) {
  d = plef_pathways[plef_pathways$measure %in% measures, ]
  d$scenario = factor(d$scenario, SCENARIO_ORDER)
  ggplot2::ggplot(d, ggplot2::aes(year, value, colour = scenario)) +
    ggplot2::geom_line(linewidth = 0.8) +
    ggplot2::facet_wrap(~measure, scales = "free_y") +
    ggplot2::labs(x = NULL, y = NULL, colour = "Scenario",
                  title = "PLEF national pathways (annual, interpolated)") +
    ggplot2::theme_minimal()
}

SCENARIO_ORDER = c("Ignore", "Steer", "Shift", "Transform")
APPROACH_ORDER = c("uniform", "capability", "equity", "hybrid")

plot_distribution = function(distribution, national, measure) {
  d = distribution[distribution$measure == measure, ]
  n = national[national$measure == measure, ]
  d$scenario = factor(d$scenario, SCENARIO_ORDER)
  n$scenario = factor(n$scenario, SCENARIO_ORDER)
  d$approach = factor(d$approach, APPROACH_ORDER)
  n$approach = factor(n$approach, APPROACH_ORDER)
  ggplot2::ggplot(d, ggplot2::aes(year)) +
    ggplot2::geom_ribbon(ggplot2::aes(ymin = p05, ymax = p95), fill = "grey80") +
    ggplot2::geom_ribbon(ggplot2::aes(ymin = p25, ymax = p75), fill = "grey60") +
    ggplot2::geom_line(ggplot2::aes(y = p50), colour = "black") +
    ggplot2::geom_line(data = n, ggplot2::aes(y = achieved), colour = "firebrick",
                       linewidth = 0.8) +
    ggplot2::geom_line(data = n, ggplot2::aes(y = plef), colour = "firebrick",
                       linetype = "dashed") +
    ggplot2::facet_grid(approach ~ scenario) +
    ggplot2::labs(x = NULL, y = measure,
                  title = paste("Downscaled", measure),
                  subtitle = paste("Grey: LSOA 5-95% and 25-75% ranges, black: median,",
                                   "red: national (dashed = original PLEF)")) +
    ggplot2::theme_minimal()
}

# Local authority summary: weighted mean value by year 2030 and 2050 and the
# share of LSOAs that are early adopters (reach half of the 2050 national
# level before the national average does).
summarise_la = function(timing, national) {
  key = c("measure", "scenario", "approach")
  nat_half = merge(timing[!duplicated(timing[key]), key], national, by = key)
  nat_half = dplyr::summarise(dplyr::group_by(nat_half, measure, scenario, approach),
                              nat_year = year[which(achieved >= achieved[dplyr::n()] / 2)[1]],
                              .groups = "drop")
  t = merge(timing, nat_half, by = key)
  t$early = !is.na(t$year_half_national_2050) & t$year_half_national_2050 < t$nat_year
  t$late = is.na(t$year_half_national_2050) | t$year_half_national_2050 > t$nat_year
  as.data.frame(dplyr::summarise(
    dplyr::group_by(t, measure, scenario, approach, LAD25NM),
    lsoas = dplyr::n(),
    mean_base = mean(base, na.rm = TRUE),
    mean_2030 = mean(value_2030, na.rm = TRUE),
    mean_2050 = mean(value_2050, na.rm = TRUE),
    share_early = mean(early), share_late = mean(late),
    .groups = "drop"))
}

# Wide LSOA table: one row per LSOA and measure, one column per
# scenario x approach x year, for selected years
lsoa_wide = function(results, years = c(2030, 2040, 2050)) {
  parts = lapply(results, function(r) {
    yrs = intersect(as.character(years), colnames(r$values))
    v = r$values[, c(colnames(r$values)[1], yrs), drop = FALSE]
    colnames(v) = c("base", yrs)
    data.frame(measure = r$measure, LSOA21CD = rownames(v),
               key = paste(r$scenario, r$approach, sep = "_"),
               v, check.names = FALSE, row.names = NULL)
  })
  long = do.call(rbind, parts)
  long = tidyr::pivot_longer(long, -c(measure, LSOA21CD, key), names_to = "year")
  base = unique(long[long$year == "base", c("measure", "LSOA21CD", "value")])
  base = base[!duplicated(base[c("measure", "LSOA21CD")]), ]
  names(base)[3] = "base"
  long = long[long$year != "base", ]
  long$col = paste(long$key, long$year, sep = "_")
  wide = tidyr::pivot_wider(long[, c("measure", "LSOA21CD", "col", "value")],
                            names_from = col, values_from = value)
  as.data.frame(merge(base, wide, by = c("measure", "LSOA21CD")))
}
