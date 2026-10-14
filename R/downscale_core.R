# Core downscaling engine
#
# Two allocation methods share one idea: every LSOA follows its own curve,
# driven by a single national "progress" parameter theta(t) that is solved
# each year so the weighted LSOA average matches the national target exactly.
# A prioritisation score p (-1..+1) makes some areas move faster (p > 0) or
# slower (p < 0) than the national average; `spread` sets how much faster.
#
# * downscale_adoption(): technology shares (0..ceiling), S-shaped in time.
#   a_i(theta) = b_i + (c_i - b_i) * G_i(theta), where G_i is a logistic in
#   theta * (1 + spread * p_i) rescaled to run from 0 (base) to 1 (ceiling)
# * downscale_activity(): continuous quantities (km, trips, kWh).
#   x_i(theta) = x0_i * exp(theta * (1 + spread * p_i))
#
# In both cases each LSOA's value is clamped to plausible bounds relative to
# the previous year (max annual change, monotonic adoption, floors), and the
# clamp is applied inside the root finding so the national total still holds.
# Both functions are monotonic in theta, so a bracketing root finder always
# converges when the target is feasible.


#' Rescale a numeric vector to percent ranks on [-1, 1]
#'
#' @param x Numeric vector. NAs are returned as 0 (neutral).
#' @return Numeric vector the same length as `x`.
rank_scale = function(x) {
  out = rep(0, length(x))
  ok = !is.na(x)
  if (sum(ok) < 2 || length(unique(x[ok])) < 2) return(out)
  r = rank(x[ok], ties.method = "average")
  out[ok] = 2 * (r - 1) / (sum(ok) - 1) - 1
  out
}


#' Combine local factors into a prioritisation score
#'
#' @param df Data frame holding the factor columns.
#' @param spec Data frame with columns `factor` (column name in `df`) and
#'   `weight` (signed: positive means a higher value makes the area an
#'   earlier/faster adopter).
#' @return Numeric score on [-1, 1], uniformly distributed (percent ranks),
#'   so the spread of adoption does not depend on how correlated factors are.
make_score = function(df, spec) {
  if (is.null(spec) || nrow(spec) == 0) return(rep(0, nrow(df)))
  missing = setdiff(spec$factor, names(df))
  if (length(missing) > 0) stop("Missing factor columns: ", paste(missing, collapse = ", "))
  parts = vapply(seq_len(nrow(spec)), function(j) {
    spec$weight[j] * rank_scale(df[[spec$factor[j]]])
  }, numeric(nrow(df)))
  parts = matrix(parts, nrow = nrow(df))
  raw = rowSums(parts) / sum(abs(spec$weight))
  rank_scale(raw)
}


#' Mix two scores and re-rank (used for the hybrid approach)
mix_scores = function(a, b, alpha = 0.5) {
  rank_scale(alpha * a + (1 - alpha) * b)
}


# Internal: solve theta for one year given a function value(theta) returning
# LSOA values, the weights and the target weighted mean.
solve_theta = function(value_fun, w, target, lower, upper) {
  f = function(theta) sum(w * value_fun(theta)) / sum(w) - target
  f_lo = f(lower)
  f_hi = f(upper)
  tol = 1e-9 * max(abs(target), 1e-12)
  if (abs(f_lo) <= tol) return(list(theta = lower, status = "ok"))
  if (f_lo > 0) return(list(theta = lower, status = "target_below_feasible"))
  if (abs(f_hi) <= tol) return(list(theta = upper, status = "ok"))
  if (f_hi < 0) return(list(theta = upper, status = "target_above_feasible"))
  r = stats::uniroot(f, lower = lower, upper = upper, f.lower = f_lo,
                     f.upper = f_hi, tol = 1e-10)
  list(theta = r$root, status = "ok")
}


#' Downscale a technology adoption share
#'
#' @param base Baseline share per LSOA (0..1) in the first year.
#' @param ceiling Technical maximum share per LSOA (0..1).
#' @param score Prioritisation score per LSOA (-1..1).
#' @param weight Weight per LSOA (e.g. households or cars).
#' @param years Integer vector of years; the first is the base year.
#' @param target National weighted-mean share for each year in `years`.
#' @param spread 0 = everyone progresses at the same logit speed (closest to
#'   uniform); towards 1 = early adopters progress up to (1 + spread) times,
#'   late adopters (1 - spread) times, the national speed.
#' @param max_step Maximum increase in share per LSOA per year.
#' @param seed Minimum starting share as a fraction of the ceiling, so areas
#'   with zero current uptake can still start.
#' @return List with `values` (LSOA x year matrix), `national` (data frame of
#'   target vs achieved) and `theta`.
downscale_adoption = function(base, ceiling, score, weight, years, target,
                              spread = 0.5, max_step = 0.1, seed = 0.002) {
  n = length(base)
  stopifnot(length(ceiling) == n, length(score) == n, length(weight) == n,
            length(years) == length(target), spread >= 0, spread < 1)
  base[is.na(base)] = 0
  ceiling = pmax(pmin(ceiling, 1), 0)
  ceiling = pmax(ceiling, base)
  weight[is.na(weight)] = 0
  score[is.na(score)] = 0

  has_cap = ceiling > base
  # Each LSOA starts on the logistic curve at its own position (seeded so
  # zero-uptake areas can start), and the curve is rescaled so it passes
  # exactly through the observed base value and approaches the ceiling.
  s0 = pmin(pmax(base / ifelse(ceiling > 0, ceiling, 1), seed), 1 - 1e-6)
  z0 = stats::qlogis(s0)
  F0 = stats::plogis(z0)
  speed = 1 + spread * score

  out = matrix(NA_real_, n, length(years), dimnames = list(NULL, years))
  out[, 1] = base
  theta = numeric(length(years))
  status = character(length(years))
  status[1] = "base"

  for (k in seq_along(years)[-1]) {
    prev = out[, k - 1]
    hi = pmin(prev + max_step, ceiling)
    value_fun = function(th) {
      prog = (stats::plogis(z0 + th * speed) - F0) / (1 - F0)
      v = ifelse(has_cap, base + (ceiling - base) * prog, base)
      pmin(pmax(v, prev), hi)
    }
    # lower = 0 reproduces last year (values are clamped to prev), so the
    # search never depends on whether the previous year was feasible
    s = solve_theta(value_fun, weight, target[k], lower = 0, upper = 200)
    theta[k] = s$theta
    status[k] = s$status
    out[, k] = value_fun(s$theta)
  }

  achieved = colSums(out * weight) / sum(weight)
  list(values = out, theta = theta,
       national = data.frame(year = years, target = target, achieved = achieved,
                             status = status))
}


#' Downscale a continuous activity level
#'
#' @param base Baseline value per LSOA (e.g. car km per person).
#' @param score Prioritisation score (-1..1); positive = changes faster in the
#'   direction of the national change.
#' @param weight Weight per LSOA (e.g. population).
#' @param years Integer vector of years; the first is the base year.
#' @param target National weighted mean for each year.
#' @param spread As for `downscale_adoption()`.
#' @param max_step Maximum relative change per LSOA per year (0.08 = 8%).
#' @param floor Minimum value per LSOA (scalar or vector).
#' @return As `downscale_adoption()`.
downscale_activity = function(base, score, weight, years, target,
                              spread = 0.5, max_step = 0.08, floor = 0) {
  n = length(base)
  stopifnot(length(score) == n, length(weight) == n,
            length(years) == length(target), spread >= 0, spread < 1)
  base[is.na(base)] = 0
  weight[is.na(weight)] = 0
  score[is.na(score)] = 0
  floor = rep_len(floor, n)
  speed = 1 + spread * score

  out = matrix(NA_real_, n, length(years), dimnames = list(NULL, years))
  out[, 1] = base
  theta = numeric(length(years))
  status = character(length(years))
  status[1] = "base"

  for (k in seq_along(years)[-1]) {
    prev = out[, k - 1]
    lo = pmax(prev * (1 - max_step), pmin(floor, prev))
    hi = prev * (1 + max_step)
    value_fun = function(th) pmin(pmax(base * exp(th * speed), lo), hi)
    s = solve_theta(value_fun, weight, target[k], lower = -50, upper = 50)
    theta[k] = s$theta
    status[k] = s$status
    out[, k] = value_fun(s$theta)
  }

  achieved = colSums(out * weight) / sum(weight)
  list(values = out, theta = theta,
       national = data.frame(year = years, target = target, achieved = achieved,
                             status = status))
}


#' Check a downscaled result matches the national target
#'
#' @param res Output of a downscale_* function.
#' @param tol Relative tolerance.
#' @return `res`, invisibly; errors if any feasible year misses its target.
check_calibration = function(res, tol = 1e-6) {
  nat = res$national
  ok_rows = nat$status %in% c("ok", "base")
  err = abs(nat$achieved - nat$target) / pmax(abs(nat$target), 1e-12)
  bad = ok_rows & err > tol
  if (any(bad)) stop("Calibration failed in years: ", paste(nat$year[bad], collapse = ", "))
  infeasible = !ok_rows
  if (any(infeasible)) {
    warning("Target not reachable within constraints in years: ",
            paste(nat$year[infeasible], collapse = ", "),
            " (", paste(unique(nat$status[infeasible]), collapse = ", "), ")")
  }
  invisible(res)
}
