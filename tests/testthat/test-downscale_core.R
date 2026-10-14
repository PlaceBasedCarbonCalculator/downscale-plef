set.seed(42)
n = 500
base = runif(n, 0, 0.05)
ceiling = runif(n, 0.3, 1)
score = rank_scale(rnorm(n))
weight = runif(n, 100, 1000)
years = 2025:2050
target = 0.03 + (0.6 - 0.03) * plogis((years - 2037) / 3)
target[1] = sum(base * weight) / sum(weight)

test_that("rank_scale maps to [-1, 1] and keeps order", {
  x = c(3, 1, 2, NA)
  r = rank_scale(x)
  expect_equal(r, c(1, -1, 0, 0))
})

test_that("make_score respects signs and is uniform on [-1, 1]", {
  df = data.frame(a = 1:11, b = 11:1)
  s = make_score(df, data.frame(factor = "a", weight = 1))
  expect_equal(s, seq(-1, 1, by = 0.2))
  s2 = make_score(df, data.frame(factor = c("a", "b"), weight = c(1, -1)))
  expect_equal(s2, s)
  expect_error(make_score(df, data.frame(factor = "zz", weight = 1)))
})

test_that("adoption matches national target every year", {
  r = downscale_adoption(base, ceiling, score, weight, years, target,
                         spread = 0.6, max_step = 0.1)
  expect_true(all(r$national$status %in% c("base", "ok")))
  expect_equal(r$national$achieved, target, tolerance = 1e-8)
  expect_silent(check_calibration(r))
})

test_that("adoption respects ceiling, monotonicity and max annual step", {
  r = downscale_adoption(base, ceiling, score, weight, years, target,
                         spread = 0.6, max_step = 0.1)
  v = r$values
  expect_true(all(v <= ceiling + 1e-12))
  steps = t(diff(t(v)))
  expect_true(all(steps >= -1e-12))
  expect_true(all(steps <= 0.1 + 1e-12))
})

test_that("higher score means earlier adoption", {
  r = downscale_adoption(rep(0.01, n), rep(1, n), score, weight, years, target,
                         spread = 0.6, max_step = 1)
  mid = r$values[, as.character(2037)]
  expect_gt(cor(mid, score, method = "spearman"), 0.99)
})

test_that("zero spread with equal starts gives identical trajectories", {
  r = downscale_adoption(rep(0.01, n), rep(1, n), score, weight, years, target,
                         spread = 0, max_step = 1)
  expect_lt(max(apply(r$values, 2, sd)), 1e-10)
})

test_that("zero-ceiling areas never adopt", {
  c0 = ceiling
  c0[1:10] = 0
  b0 = base
  b0[1:10] = 0
  r = downscale_adoption(b0, c0, score, weight, years, target, spread = 0.6)
  expect_true(all(r$values[1:10, ] == 0))
})

test_that("infeasible targets are flagged, not silently missed", {
  r = downscale_adoption(base, rep(0.2, n), score, weight, years, target,
                         spread = 0.6, max_step = 0.1)
  expect_true(any(r$national$status == "target_above_feasible"))
  expect_warning(check_calibration(r))
})

test_that("activity matches target, respects floor and max step", {
  b = runif(n, 2000, 12000)
  tgt = sum(b * weight) / sum(weight) * seq(1, 0.5, length.out = length(years))
  fl = 0.3 * b
  r = downscale_activity(b, score, weight, years, tgt, spread = 0.6,
                         max_step = 0.08, floor = fl)
  expect_equal(r$national$achieved, tgt, tolerance = 1e-8)
  v = r$values
  expect_true(all(v >= fl - 1e-9))
  rel = t(diff(t(v))) / v[, -ncol(v)]
  expect_true(all(abs(rel) <= 0.08 + 1e-9))
  # higher score reduces faster
  change = v[, ncol(v)] / v[, 1]
  expect_lt(cor(change, score, method = "spearman"), -0.9)
})

test_that("uniform activity reproduces the proportional reduction", {
  # The 'Uniform Reduction' column of docs/original PLEF/Downscaling Examples.xlsx
  b = c(120, 80, 60, 50, 45, 42, 40, 38, 35, 30)
  w = rep(1, 10)
  r = downscale_activity(b, rep(0, 10), w, 2020:2021, c(mean(b), mean(b) * 0.7),
                         spread = 0, max_step = 1)
  expect_equal(unname(r$values[, 2]), b * 0.7)
})

test_that("rebase_pathway blends to PLEF and keeps the end point", {
  path = data.frame(year = c(2020, 2030, 2040, 2050), value = c(0.01, 0.2, 0.6, 0.9))
  r = rebase_pathway(path, observed = 0.03, base_year = 2025, converge_year = 2040)
  expect_equal(r$target[1], 0.03)
  expect_equal(r$target[r$year == 2050], 0.9)
  expect_equal(r$target[r$year >= 2040], r$plef[r$year >= 2040])
  expect_true(all(diff(r$target) >= 0))
  r2 = rebase_pathway(path, observed = 0.05, base_year = 2025, method = "relative")
  expect_equal(r2$target / r2$target[1], r2$plef / r2$plef[1])
})

test_that("adoption starts exactly at the base and a flat target stays flat", {
  flat = rep(sum(base * weight) / sum(weight), length(years))
  r = downscale_adoption(base, ceiling, score, weight, years, flat, spread = 0.6)
  expect_equal(unname(r$values[, ncol(r$values)]), base)
  expect_true(all(r$national$status %in% c("base", "ok")))
})
