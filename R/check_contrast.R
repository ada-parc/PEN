#!/usr/bin/env Rscript
# =============================================================================
# check_contrast.R
# -----------------------------------------------------------------------------
# Reads assets/tokens.css, resolves the role tokens
# for each theme (light, dark, contrast), and asserts the contrast floor on
# every foreground/background pair the site actually uses.
#
#   Rscript R/check_contrast.R          # prints a table, exits 1 on any failure
#
# This checks the TOKEN pairs. scripts/style_snapshot.mjs `scan` checks the
# rendered page (the effective background behind every text node, including
# hover and focus states). Both should pass; neither replaces the other.
#
# Floors: text 4.5:1 (AA), 7:1 in the high-contrast theme (AAA); meaningful
# non-text (borders, rails, focus ring, control fills) 3:1.
# =============================================================================

args <- commandArgs(trailingOnly = FALSE)
file_arg <- sub("^--file=", "", args[grepl("^--file=", args)])
repo_root <- if (length(file_arg) == 1) {
  normalizePath(file.path(dirname(file_arg), ".."))
} else {
  normalizePath(getwd())
}
css <- readLines(file.path(repo_root, "assets", "tokens.css"), warn = FALSE)

# --- Parse --pen-* declarations out of one top-level rule ---------------------
block <- function(header_pattern) {
  start <- grep(header_pattern, css)[1]
  if (is.na(start)) stop("no block matching ", header_pattern)
  end <- start + which(grepl("^\\s*\\}", css[(start + 1):length(css)]))[1]
  body <- css[(start + 1):end]
  body <- sub("/\\*.*?\\*/", "", body, perl = TRUE)          # strip trailing comments
  m <- regmatches(body, regexec("^\\s*--pen-([a-z0-9-]+):\\s*([^;]+);", body))
  m <- m[lengths(m) == 3]
  stats::setNames(vapply(m, function(x) trimws(x[3]), ""), vapply(m, function(x) x[2], ""))
}

light <- block("^:root \\{")
dark <- block("^\\s*:root\\[data-pen-theme=\"dark\"\\] \\{")
contrast <- block("^\\s*:root\\[data-pen-theme=\"contrast\"\\] \\{")
themes <- list(light = light, dark = dark, contrast = contrast)

# --- Resolve a role to a hex ---------------------------------------------------
resolve <- function(role, map) {
  v <- map[[role]]
  for (i in 1:10) {
    if (is.null(v) || is.na(v)) return(NA_character_)
    if (grepl("^#[0-9A-Fa-f]{6}$", v)) return(toupper(v))
    m <- regmatches(v, regexec("^var\\(--pen-([a-z0-9-]+)\\)$", v))[[1]]
    if (length(m) == 2) v <- map[[m[2]]] else return(NA_character_)
  }
  NA_character_
}

lum <- function(hex) {
  rgb <- strtoi(substring(hex, c(2, 4, 6), c(3, 5, 7)), 16L) / 255
  lin <- ifelse(rgb <= 0.03928, rgb / 12.92, ((rgb + 0.055) / 1.055)^2.4)
  sum(lin * c(0.2126, 0.7152, 0.0722))
}
ratio <- function(a, b) {
  la <- lum(a); lb <- lum(b)
  (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
}

# --- The pairs the site uses: fg, bg, kind (text | ui) -------------------------
pairs <- rbind(
  # text on the page and on cards
  c("ink", "bg", "text"), c("ink", "surface", "text"),
  c("ink-soft", "bg", "text"), c("ink-soft", "surface", "text"),
  c("ink-strong", "surface", "text"),
  c("link", "bg", "text"), c("link", "surface", "text"),
  c("link-hover", "bg", "text"), c("link-hover", "surface", "text"),
  c("accent", "bg", "text"), c("accent", "surface", "text"),
  # text on the row hover wash
  c("ink", "wash", "text"), c("link", "wash", "text"), c("accent", "wash", "text"),
  # text on fills
  c("on-accent", "accent", "text"), c("on-accent-soft", "accent", "text"),
  c("on-chrome", "chrome", "text"), c("on-chrome-soft", "chrome", "text"),
  c("on-chrome", "chrome-hover", "text"),
  c("on-band", "band", "text"), c("on-band-soft", "band", "text"),
  c("band-accent", "band", "text"), c("band-link", "band", "text"),
  c("band", "on-band", "text"),                    # the inverse button
  c("band", "band-accent", "text"),                # inverse button hover
  # meaningful non-text
  c("rule", "bg", "ui"), c("rule", "surface", "ui"),
  # The focus ring is drawn 2 to 3px outside the control (outline-offset), so it
  # is read against the page or card behind it, never against the control's own
  # fill. Rings on a band use --pen-band-link, checked below.
  c("focus", "bg", "ui"), c("focus", "surface", "ui"),
  c("band-link", "band", "ui"),                    # focus ring on the navbar
  c("chrome", "bg", "ui"), c("chrome", "surface", "ui"),
  c("accent", "bg", "ui"), c("accent", "surface", "ui")
)

rows <- list()
for (th in names(themes)) {
  map <- if (th == "light") light else utils::modifyList(as.list(light), as.list(themes[[th]]))
  for (i in seq_len(nrow(pairs))) {
    fg <- resolve(pairs[i, 1], map); bg <- resolve(pairs[i, 2], map)
    kind <- pairs[i, 3]
    need <- if (kind == "ui") 3 else if (th == "contrast") 7 else 4.5
    r <- if (is.na(fg) || is.na(bg)) NA_real_ else ratio(fg, bg)
    rows[[length(rows) + 1]] <- data.frame(
      theme = th, fg = pairs[i, 1], bg = pairs[i, 2], kind = kind,
      fg_hex = fg, bg_hex = bg, ratio = round(r, 2), need = need,
      ok = !is.na(r) && r >= need, stringsAsFactors = FALSE)
  }
}
res <- do.call(rbind, rows)

bad <- res[!res$ok, ]
cat(sprintf("Checked %d pairs across %d themes.\n", nrow(res), length(themes)))
if (nrow(bad)) {
  cat("\nFAILING:\n")
  print(bad[, c("theme", "fg", "bg", "kind", "fg_hex", "bg_hex", "ratio", "need")], row.names = FALSE)
  quit(status = 1)
}
cat("All pairs meet their floor.\n")
for (th in names(themes)) {
  r <- res[res$theme == th, ]
  cat(sprintf("  %-9s lowest text %.2f:1, lowest non-text %.2f:1\n", th,
              min(r$ratio[r$kind == "text"]), min(r$ratio[r$kind == "ui"])))
}
