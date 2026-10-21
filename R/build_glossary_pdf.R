# Regenerate assets/downloads/glossary.pdf from assets/downloads/glossary.html.
#
# The Help page's "Download the glossary (PDF)" button serves this file
# directly, so a real file downloads instead of relying on the browser's
# print dialog (Safari's print-to-PDF has already produced blank output on
# this site once, see the certificate fix). Rerun this whenever
# glossary.html changes, then `quarto render` to copy it into _site.
#
# Not part of the pre-render hook: it needs a local Chrome or Chromium, which
# the build otherwise does not. Run from the repository root:
#
#   Rscript R/build_glossary_pdf.R

src <- normalizePath("assets/downloads/glossary.html", mustWork = TRUE)
out <- file.path(dirname(src), "glossary.pdf")

candidates <- c(
  Sys.getenv("CHROME_PATH"),
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  "/Applications/Chromium.app/Contents/MacOS/Chromium",
  Sys.which(c("google-chrome", "chromium", "chromium-browser"))
)
chrome <- candidates[nzchar(candidates) & file.exists(candidates)][1]
if (is.na(chrome)) {
  stop("No Chrome or Chromium found. Set CHROME_PATH to its executable.")
}

status <- system2(chrome, c(
  "--headless", "--disable-gpu", "--no-pdf-header-footer",
  # Give the Bitter web font time to load before printing.
  "--virtual-time-budget=5000",
  shQuote(paste0("--print-to-pdf=", out)),
  shQuote(paste0("file://", src))
), stdout = FALSE, stderr = FALSE)

if (status != 0 || !file.exists(out)) stop("PDF generation failed.")
message("Wrote ", out)
