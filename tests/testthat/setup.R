# Load project functions (this repo is a targets project, not a package)
for (f in list.files(testthat::test_path("..", "..", "R"), pattern = "\\.R$", full.names = TRUE)) {
  source(f, local = FALSE)
}
