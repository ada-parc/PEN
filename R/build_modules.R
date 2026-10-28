#!/usr/bin/env Rscript
# =============================================================================
# build_modules.R
# -----------------------------------------------------------------------------
# Generates, from content/modules.yml:
#   modules/module-XX.qmd          module landing page (from _module-template.qmd)
#   modules/module-XX-unit-YY.qmd  one page per unit (from _unit-template.qmd)
#   assets/pen-manifest.html       { "01": ["01","02","03","04"], ... },
#                                   module -> unit id map, read by
#                                   assets/progress-init.html and
#                                   certificate.qmd to know when a module
#                                   (all its units done) or the whole
#                                   series (all tracked modules done) is
#                                   complete.
#
# Run directly:      Rscript R/build_modules.R
# Runs automatically: as the `pre-render` step in _quarto.yml
#
# The only non-base dependency is the {yaml} package, which ships with a
# standard R install. If you add more, initialise renv.
#
# Module 4 ("Resources") is intentionally NOT generated here. It is a
# hand-authored page at modules/module-04.qmd with no units, so it sits
# outside progress tracking and the certificate gate. The last *generated*
# module (module 3) links forward to it and carries the certificate banner.
# =============================================================================

suppressPackageStartupMessages({
  if (!requireNamespace("yaml", quietly = TRUE)) {
    stop("The 'yaml' package is required. Install it with install.packages('yaml').")
  }
})

# --- Resolve paths relative to the repo root ---------------------------------
args <- commandArgs(trailingOnly = FALSE)
file_arg <- sub("^--file=", "", args[grepl("^--file=", args)])
repo_root <- if (length(file_arg) == 1) {
  normalizePath(file.path(dirname(file_arg), ".."))
} else {
  normalizePath(getwd())
}

spine_path      <- file.path(repo_root, "content", "modules.yml")
module_tpl_path <- file.path(repo_root, "modules", "_module-template.qmd")
unit_tpl_path   <- file.path(repo_root, "modules", "_unit-template.qmd")
out_dir         <- file.path(repo_root, "modules")
manifest_path   <- file.path(repo_root, "assets", "pen-manifest.html")

stopifnot(file.exists(spine_path), file.exists(module_tpl_path), file.exists(unit_tpl_path))

modules     <- yaml::read_yaml(spine_path)
module_tpl  <- paste(readLines(module_tpl_path, warn = FALSE), collapse = "\n")
unit_tpl    <- paste(readLines(unit_tpl_path, warn = FALSE), collapse = "\n")

# --- Small helpers ----------------------------------------------------------
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || identical(a, "")) b else a

# Only touch a file's mtime if its content actually changed. This hook reruns
# on every quarto preview request; rewriting all 14+ files unconditionally on
# every page load churns their mtimes and makes Quarto think the whole
# project needs re-rendering, which drags the preview's live-reload back to
# whichever generated file sorts last (module-03.qmd) on every navigation.
write_if_changed <- function(path, content) {
  if (file.exists(path)) {
    existing <- paste(readLines(path, warn = FALSE), collapse = "\n")
    if (identical(existing, content)) return(FALSE)
  }
  writeLines(content, path)
  TRUE
}

# Collapse a folded/multi-line YAML string to a single trimmed line.
oneline <- function(x) {
  if (is.null(x) || length(x) == 0) return("")
  gsub("\\s+", " ", trimws(paste(x, collapse = " ")))
}

fill <- function(tpl, subs) {
  for (nm in names(subs)) {
    tpl <- gsub(paste0("{{", nm, "}}"), subs[[nm]], tpl, fixed = TRUE)
  }
  tpl
}

md_list <- function(items, bullet = "-") {
  if (length(items) == 0) return("_None listed yet._")
  paste(sprintf("%s %s", bullet, items), collapse = "\n")
}

json_str_array <- function(x) {
  paste0("[", paste(sprintf('"%s"', x), collapse = ", "), "]")
}

# --- Section builders -----------------------------------------------------
build_status_banner <- function(status, noun) {
  status <- status %||% "draft"
  if (identical(status, "published")) return("")
  label <- c(draft = "Draft, content not final",
             review = "In review, content may still change")[status]
  label <- label %||% paste0(status, ", content may still change")
  sprintf(
    "::: {.callout-warning appearance=\"simple\"}\n**%s.** This page is scaffolding. The %s is a placeholder.\n:::\n",
    label, noun
  )
}

build_pages <- function(pages) {
  if (length(pages) == 0) return("_To be added._")
  # `_quarto.yml` sets link-external-newwindow/link-external-icon
  # site-wide, but on this Quarto version that processor never actually
  # fires (verified empty on every rendered page, including links with no
  # manual target at all), so it is not something to depend on. Built by
  # hand instead: target/rel for the real new-tab behavior, a decorative
  # aria-hidden glyph for the sighted "this leaves the site" cue, and a visually-hidden text label so a screen reader gets the
  # same information the icon gives a sighted reader, not just "opens in
  # a new tab" silently. `external-link-icon` is a real class in
  # pen.scss, not Quarto's (absent) generated one.
  rows <- vapply(pages, function(p) {
    host <- sub("^www\\.", "", sub("^https?://([^/]+).*$", "\\1", p$url))
    sprintf(paste0(
      "<li><a href=\"%s\" target=\"_blank\" rel=\"noopener\">",
      "<span class=\"resource-title\">%s<span class=\"visually-hidden\"> (opens in a new tab)</span></span>",
      "%s",
      "<span class=\"resource-foot\"><span class=\"resource-host\">%s</span>",
      "<span class=\"resource-icon\" aria-hidden=\"true\">",
      "<svg width=\"26\" height=\"26\" viewBox=\"0 0 24 24\" fill=\"none\">",
      "<path d=\"M8 16L17 7M9 7h8v8\" stroke=\"currentColor\" stroke-width=\"2.5\" ",
      "stroke-linecap=\"round\" stroke-linejoin=\"round\"/></svg></span></span></a></li>"),
      p$url, html_esc(p$label %||% p$url),
      if (is_set(p$description)) sprintf("<span class=\"resource-desc\">%s</span>", html_esc(oneline(p$description))) else "",
      html_esc(host))
  }, character(1))
  paste0("```{=html}\n<ul class=\"resource-list\">\n", paste(rows, collapse = "\n"), "\n</ul>\n```")
}


# Module-level `downloads` (plain list) plus one large card per unit that has
# a `slides` file. Raw HTML so the download attribute and layout survive
# pandoc. Hrefs are relative to modules/, hence the "../".
build_downloads <- function(dls, units = list()) {
  out <- character(0)
  if (length(dls) > 0) {
    out <- c(out, paste(vapply(dls, function(d) sprintf("- [%s](%s)", d$label %||% d$href, d$href),
                               character(1)), collapse = "\n"), "")
  }
  cards <- character(0)
  for (j in seq_along(units)) {
    u <- units[[j]]
    if (is_set(u$slides)) {
      cards <- c(cards, sprintf(paste0(
        "<li><a href=\"../%s\" download>",
        "<span class=\"slides-unit\" aria-hidden=\"true\">%s</span>",
        "<span class=\"slides-text\"><span class=\"slides-title\">%s<span class=\"visually-hidden\">, unit %s slides</span></span>",
        "<span class=\"slides-meta\">Download slides (PowerPoint)</span></span>",
        "<svg class=\"slides-icon\" width=\"28\" height=\"28\" viewBox=\"0 0 24 24\" fill=\"none\" aria-hidden=\"true\">",
        "<path d=\"M12 4v10m0 0l-4-4m4 4l4-4M5 19h14\" stroke=\"currentColor\" stroke-width=\"2.5\" ",
        "stroke-linecap=\"round\" stroke-linejoin=\"round\"/></svg></a></li>"),
        u$slides, unit_letter(j), html_esc(oneline(u$title)), unit_letter(j)))
    }
  }
  if (length(cards) > 0) {
    out <- c(out, paste0("```{=html}\n<ul class=\"slides-list\">\n",
                         paste(cards, collapse = "\n"), "\n</ul>\n```"))
  }
  if (length(out) == 0) return("_None yet._")
  paste(out, collapse = "\n")
}

# Units are lettered (A, B, C, ...) to tell them apart from the numbered
# modules and objectives.
unit_letter <- function(j) LETTERS[j]

# Learning objectives: a panel holding a lead-in sentence and an unordered list
# (the objectives have no sequence) with the leading verb bolded for scanning;
# see .objective-panel in pen.scss. Plain text only, escaped.
build_objectives <- function(items) {
  if (length(items) == 0) return("_None listed yet._")
  lis <- vapply(items, function(x) {
    x <- html_esc(oneline(x))
    sprintf("<li><span>%s</span></li>", sub("^(\\S+)", "<b>\\1</b>", x))
  }, character(1))
  paste0("```{=html}\n<div class=\"objective-panel\">\n<p class=\"objective-stem\">By the end of this module, you will be able to:</p>\n",
         "<ul class=\"objective-list\">\n", paste(lis, collapse = "\n"), "\n</ul>\n</div>\n```")
}

is_set <- function(x) !is.null(x) && length(x) > 0 && !identical(x, "TBD") && !identical(x, "")

# Slides / transcript button. Missing files render a disabled, worded button
# (state in words, not color alone), same TBD pattern as the media slot.
build_resource_button <- function(kind, path, title) {
  label <- if (kind == "slides") "Download slides" else "Read transcript"
  icon <- if (kind == "slides") {
    "M12 4v10m0 0l-4-4m4 4l4-4M5 19h14"
  } else {
    "M7 4h8l4 4v12H7zM10 12h6M10 16h6"
  }
  svg <- sprintf(paste0("<svg width=\"20\" height=\"20\" viewBox=\"0 0 24 24\" fill=\"none\" aria-hidden=\"true\">",
                        "<path d=\"%s\" stroke=\"currentColor\" stroke-width=\"2.5\" ",
                        "stroke-linecap=\"round\" stroke-linejoin=\"round\"/></svg>"), icon)
  # Until real transcripts are supplied, the button opens a shared placeholder.
  if (kind == "transcript" && !is_set(path)) path <- "assets/transcripts/sample-transcript.html"
  if (is_set(path)) {
    extra <- if (kind == "slides") " download" else " target=\"_blank\" rel=\"noopener\""
    sprintf("<a class=\"unit-resource\" href=\"../%s\"%s>%s<span>%s</span></a>",
            path, extra, svg, label)
  } else {
    sprintf(paste0("<span class=\"unit-resource is-unavailable\" role=\"link\" aria-disabled=\"true\">",
                   "%s<span>%s<span class=\"visually-hidden\"> for %s</span></span><span class=\"unit-resource-state\">Not available yet</span></span>"),
            svg, label, html_esc(title))
  }
}

# "9:54" -> list(short = "9 min 54 sec", spoken = "9 minutes 54 seconds"), or
# NULL if absent or malformed (the poster then shows the title alone).
parse_duration <- function(d) {
  if (is.null(d) || !grepl("^[0-9]+:[0-5][0-9]$", d)) return(NULL)
  parts <- as.integer(strsplit(d, ":", fixed = TRUE)[[1]])
  plural <- function(k, w) sprintf("%d %s%s", k, w, if (k == 1) "" else "s")
  list(short = sprintf("%d min %02d sec", parts[1], parts[2]),
       spoken = paste(plural(parts[1], "minute"), plural(parts[2], "second")))
}

# One native player with its poster frame, as a bare HTML string (no fence).
# `captions` is an optional path to a .vtt; when set, it is attached as an
# English <track kind="captions"> and shown by default, so a viewer who needs
# captions never has to find the toggle. Paths may contain spaces (the raw
# exports do), so they are percent-encoded for the URL. Emitted as raw HTML:
# left as plain markdown, pandoc wraps the poster's inline spans in a <p>,
# which breaks their flex layout.
url_path <- function(p) gsub(" ", "%20", html_esc(p), fixed = TRUE)

build_player <- function(video, title, duration = NULL, captions = NULL, part = 1) {
  dur <- parse_duration(duration)
  poster <- paste0(
    "<div class=\"video-poster is-hidden\" data-pen-poster aria-hidden=\"true\">\n",
    "<span class=\"poster-play\"><svg width=\"28\" height=\"28\" viewBox=\"0 0 24 24\" fill=\"currentColor\">",
    "<path d=\"M8 5v14l11-7z\"/></svg></span>\n",
    "<span class=\"poster-title\">", html_esc(title), "</span>\n",
    if (!is.null(dur)) paste0("<span class=\"poster-meta\">", dur$short, " video</span>\n") else "",
    "</div>\n")
  label <- paste0(html_esc(title), " video", if (!is.null(dur)) paste0(", ", dur$spoken) else "")
  track <- if (is_set(captions)) {
    sprintf("<track kind=\"captions\" src=\"../%s\" srclang=\"en\" label=\"English\" default>\n", url_path(captions))
  } else ""
  sprintf(
    paste0(
      "<div class=\"video-embed has-video\">\n",
      "<video controls preload=\"metadata\" playsinline data-pen-part=\"%d\" aria-label=\"%s\">\n",
      "<source src=\"../%s\" type=\"video/mp4\">\n%s",
      "<p>Your browser cannot play this video. ",
      "<a href=\"../%s\">Download it instead</a>.</p>\n",
      "</video>\n%s</div>"
    ),
    as.integer(part), label, url_path(video), track, url_path(video), poster
  )
}

# Transcript text file (paragraphs separated by blank lines) -> a native
# <details> in the Help page's .faq-list pattern, so the full text is on the
# page, below its player, without making the page long.
build_transcript <- function(path, title) {
  full <- file.path(repo_root, path)
  if (!file.exists(full)) stop("Transcript file not found: ", path)
  txt <- paste(readLines(full, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  paras <- Filter(nzchar, trimws(strsplit(txt, "\n[ \t]*\n")[[1]]))
  sprintf(paste0(
    "<div class=\"faq-list unit-transcript\">\n<details>\n",
    "<summary>Transcript<span class=\"visually-hidden\"> for %s</span></summary>\n%s\n",
    "</details>\n</div>"),
    html_esc(title),
    paste(sprintf("<p>%s</p>", html_esc(vapply(paras, oneline, character(1)))), collapse = "\n"))
}

# A unit made of several videos (units are one idea, even when it took more
# than one recording). Each video is a part with its own h2, player, captions
# and transcript; a short list of links at the top lets a keyboard or screen
# reader user jump straight to one. A one-video unit gets no part heading.
# "m:ss" -> seconds
duration_secs <- function(d) {
  if (is.null(d) || !grepl("^[0-9]+:[0-5][0-9]$", d)) return(NA_real_)
  p <- as.integer(strsplit(d, ":", fixed = TRUE)[[1]])
  p[1] * 60 + p[2]
}

build_videos <- function(videos) {
  n <- length(videos)
  secs <- vapply(videos, function(v) duration_secs(v$duration), numeric(1))
  total <- if (!anyNA(secs)) {
    sprintf("%d min %02d sec", sum(secs) %/% 60, sum(secs) %% 60)
  } else NULL
  nav <- ""
  if (n > 1) {
    items <- vapply(seq_len(n), function(k) {
      v <- videos[[k]]
      dur <- parse_duration(v$duration)
      sprintf(paste0("<li><a href=\"#part-%d\"><span class=\"unit-parts-title\">%s</span>",
                     "%s</a></li>"),
              k, html_esc(v$title),
              if (!is.null(dur)) sprintf("<span class=\"unit-parts-time\">%s</span>", dur$short) else "")
    }, character(1))
    nav <- paste0(
      "<nav class=\"unit-parts\" aria-label=\"Videos in this unit\">\n",
      sprintf("<p class=\"unit-parts-label\">This unit has %d videos%s. Watch them in order.</p>\n",
              n, if (!is.null(total)) paste0(", ", total, " in all") else ""),
      "<ol>\n", paste(items, collapse = "\n"), "\n</ol>\n</nav>\n")
  }
  parts <- vapply(seq_len(n), function(k) {
    v <- videos[[k]]
    paste0(
      "<section class=\"unit-part\"",
      if (n > 1) sprintf(" aria-labelledby=\"part-%d\"", k) else "", ">\n",
      if (n > 1) sprintf("<h2 class=\"unit-part-title\" id=\"part-%d\"><span class=\"unit-part-count\">Part %d of %d</span> %s</h2>\n",
                         k, k, n, html_esc(v$title)) else "",
      build_player(v$video, v$title, v$duration, v$captions, part = k), "\n",
      if (is_set(v$transcript)) paste0(build_transcript(v$transcript, v$title), "\n") else "",
      "</section>")
  }, character(1))
  paste0("```{=html}\n", nav, paste(parts, collapse = "\n"), "\n```")
}

# The video slot on a unit page. A unit with no `video`/`videos` yet gets an
# empty placeholder frame.
build_media <- function(video = NULL, title = "", duration = NULL, videos = NULL) {
  if (length(videos) > 0) return(build_videos(videos))
  if (!is.null(video) && !identical(video, "TBD")) {
    # Self-hosted video: native HTML5 player (keyboard accessible, no
    # third-party script). No captions or transcript here; a unit with
    # either uses `videos:` instead (even for one video).
    return(paste0("```{=html}\n", build_player(video, title, duration), "\n```"))
  }
  "<div class=\"video-embed is-placeholder\"></div>"
}

# List of unit rows for the module landing page. Same tracker-list row shape
# as the home page's Module Tracker (assets/pen.scss .unit-list, mirroring
# .hero-modules): the whole row is one link, so one line per unit.
build_unit_list <- function(module_id, units) {
  if (length(units) == 0) return("_No units listed yet._")
  rows <- vapply(seq_along(units), function(i) {
    u <- units[[i]]
    href <- sprintf("module-%s-unit-%s.qmd", module_id, u$id)
    sprintf(
      paste0(
        "- [<span class=\"unit-number\">%s</span>",
        "<span class=\"unit-title\">%s</span>",
        "<span class=\"unit-break\" aria-hidden=\"true\"></span>",
        "<span class=\"status-pill\" data-pen-unit=\"%s-%s\">Not started</span>",
        "<span class=\"unit-arrow\" aria-hidden=\"true\"><svg width=\"20\" height=\"20\" viewBox=\"0 0 24 24\" fill=\"none\"><path d=\"M9 5l7 7-7 7\" stroke=\"currentColor\" stroke-width=\"3.5\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/></svg></span>](%s)"
      ),
      unit_letter(i), oneline(u$title %||% sprintf("Unit %s", u$id)), module_id, u$id, href
    )
  }, character(1))
  paste(rows, collapse = "\n")
}

# Shown only on the last tracked module's page. Invites the trainee to their
# certificate once every unit in every tracked module is complete.
build_cert_banner <- function(is_last) {
  if (!is_last) return("")
  paste0(
    "<div class=\"cert-banner\" data-pen-certificate-ready hidden=\"hidden\">\n",
    "<p><strong>You've completed the training.</strong> ",
    "<a href=\"../certificate.qmd\">Get your certificate →</a></p>\n",
    "</div>\n"
  )
}

# --- Wayfinding: pager, breadcrumb, "up next" panel --------------------------
# All three emit raw HTML with no blank lines and no indentation, so pandoc
# keeps each as one HTML block (a blank line or 4 leading spaces would
# start a markdown paragraph or code block inside it).
html_esc <- function(x) {
  x <- gsub("&", "&amp;", x, fixed = TRUE)
  x <- gsub("<", "&lt;", x, fixed = TRUE)
  gsub(">", "&gt;", x, fixed = TRUE)
}

pager_arrow <- function(dir) {
  d <- if (dir == "prev") "M15 5l-7 7 7 7" else "M9 5l7 7-7 7"
  sprintf(paste0(
    "<span class=\"pager-arrow\" aria-hidden=\"true\">",
    "<svg width=\"20\" height=\"20\" viewBox=\"0 0 24 24\" fill=\"none\">",
    "<path d=\"%s\" stroke=\"currentColor\" stroke-width=\"3.5\" ",
    "stroke-linecap=\"round\" stroke-linejoin=\"round\"/></svg></span>"), d)
}

# One large link: a small label ("Next unit") over the destination's title.
pager_link <- function(dir, label, title, href) {
  text <- sprintf(paste0(
    "<span class=\"pager-text\"><span class=\"pager-label\">%s</span>",
    "<span class=\"pager-title\">%s</span></span>"),
    html_esc(label), html_esc(title))
  inner <- if (dir == "prev") paste0(pager_arrow(dir), text) else paste0(text, pager_arrow(dir))
  sprintf("<a class=\"pager-link pager-%s\" href=\"%s\">%s</a>", dir, href, inner)
}

# `prev` and `nxt` are list(label=, title=, href=).
build_pager <- function(aria, prev, nxt) {
  paste0(
    "<nav class=\"pager\" aria-label=\"", aria, "\">\n",
    pager_link("prev", prev$label, prev$title, prev$href), "\n",
    pager_link("next", nxt$label, nxt$title, nxt$href), "\n",
    "</nav>"
  )
}

# crumbs: list of list(text=, href=); the last has no href and is the
# current page.
build_breadcrumb <- function(crumbs) {
  items <- vapply(seq_along(crumbs), function(k) {
    cr <- crumbs[[k]]
    if (k < length(crumbs)) {
      sprintf("<li><a href=\"%s\">%s</a></li>", cr$href, html_esc(cr$text))
    } else {
      sprintf("<li aria-current=\"page\">%s</li>", html_esc(cr$text))
    }
  }, character(1))
  paste0("<nav class=\"pen-breadcrumb\" aria-label=\"Breadcrumb\">\n<ol>\n",
         paste(items, collapse = "\n"), "\n</ol>\n</nav>")
}

# The "Up next" part of a completed unit, inside the "Mark unit complete"
# box (shown by assets/progress-init.html once the unit is marked complete).
# The link is the next unit when there is one; on a module's
# last unit it points at the module overview, and the script swaps in the
# certificate link instead when the whole series is done (data-cert-href).
build_after_complete <- function(label, title, href, last) {
  sprintf(paste0(
    "<div class=\"after-complete\" data-pen-after-complete%s>\n",
    "<p class=\"after-complete-label\" data-pen-after-label>%s</p>\n",
    "<a class=\"btn btn-primary\" href=\"%s\" data-pen-after-link ",
    "data-cert-href=\"../certificate.html\">%s</a>\n",
    "</div>"),
    if (last) " data-last-unit" else "",
    html_esc(label), href, html_esc(title))
}

# --- Generate module + unit pages -----------------------------------
n <- length(modules)
written <- character(0)
manifest_entries <- character(0)

for (i in seq_len(n)) {
  mod <- modules[[i]]
  mid <- mod$id %||% sprintf("%02d", i)
  units <- mod$units %||% list()
  is_last <- identical(i, n)

  mtitle <- function(k) oneline(modules[[k]]$title %||% sprintf("Module %s", modules[[k]]$id))
  mod_prev <- if (i > 1) {
    list(label = "Previous module", title = sprintf("Module %d: %s", i - 1, mtitle(i - 1)),
         href = sprintf("module-%s.qmd", modules[[i - 1]]$id))
  } else {
    list(label = "Back to the start", title = "Home", href = "../index.qmd")
  }
  mod_next <- if (i < n) {
    list(label = "Next module", title = sprintf("Module %d: %s", i + 1, mtitle(i + 1)),
         href = sprintf("module-%s.qmd", modules[[i + 1]]$id))
  } else {
    list(label = "Next module", title = "Module 4: Resources", href = "module-04.qmd")
  }
  mod_crumbs <- list(
    list(text = "Home", href = "../index.qmd"),
    list(text = sprintf("Module %d", i))
  )

  # -- module landing page --
  page <- fill(module_tpl, list(
    ID           = mid,
    NUMBER       = as.integer(i),
    TITLE        = oneline(mod$title %||% sprintf("Module %s", mid)),
    STATUS_BANNER = build_status_banner(mod$status, "content"),
    SUMMARY      = oneline(mod$summary),
    OBJECTIVES   = build_objectives(mod$objectives),
    UNIT_LIST    = build_unit_list(mid, units),
    ADAPARC_PAGES = build_pages(mod$adaparc_pages),
    DOWNLOADS_SECTION = if (isTRUE(mod$no_slides) && length(mod$downloads) == 0) "" else
      paste0("## Slides Download\n\n", build_downloads(mod$downloads, units)),
    CERT_BANNER  = build_cert_banner(is_last),
    BREADCRUMB   = build_breadcrumb(mod_crumbs),
    PAGER        = build_pager("Module navigation", mod_prev, mod_next)
  ))
  header <- paste0(
    "<!-- GENERATED FILE. Do not edit by hand.\n",
    "     Source: content/modules.yml + modules/_module-template.qmd\n",
    "     Rebuild: Rscript R/build_modules.R -->\n"
  )
  out_file <- file.path(out_dir, sprintf("module-%s.qmd", mid))
  if (write_if_changed(out_file, paste0(header, page))) {
    written <- c(written, basename(out_file))
  }

  # -- unit pages --
  m <- length(units)
  unit_ids <- character(0)
  for (j in seq_len(m)) {
    u <- units[[j]]
    uid <- u$id %||% sprintf("%02d", j)
    unit_ids <- c(unit_ids, uid)

    mod_label <- sprintf("Module %d: %s", i, oneline(mod$title %||% sprintf("Module %s", mid)))
    overview <- list(label = "Module overview", title = mod_label,
                     href = sprintf("module-%s.qmd", mid))
    uprev <- if (j > 1) {
      list(label = "Previous unit", title = oneline(units[[j - 1]]$title),
           href = sprintf("module-%s-unit-%s.qmd", mid, units[[j - 1]]$id))
    } else overview
    unext <- if (j < m) {
      list(label = "Next unit", title = oneline(units[[j + 1]]$title),
           href = sprintf("module-%s-unit-%s.qmd", mid, units[[j + 1]]$id))
    } else overview
    ucrumbs <- list(
      list(text = "Home", href = "../index.qmd"),
      list(text = sprintf("Module %d", i), href = sprintf("module-%s.qmd", mid)),
      list(text = sprintf("Unit %s", unit_letter(j)))
    )
    after <- if (j < m) {
      build_after_complete("Up next", sprintf("Unit %s: %s", unit_letter(j + 1), unext$title), unext$href, FALSE)
    } else {
      build_after_complete(sprintf("You have finished the last unit in Module %d.", i),
                           sprintf("Back to the Module %d overview", i), overview$href, TRUE)
    }

    # Units whose videos carry their own on-page transcripts (below each
    # player) drop the "Read transcript" button: it would only point at a
    # placeholder.
    inline_transcripts <- any(vapply(u$videos %||% list(), function(v) is_set(v$transcript), logical(1)))

    # Modules flagged `no_slides` (each unit is a live demo of the ADA-PARC
    # site) get no slides button or landing-page section. The resource row
    # sits under the "Mark unit complete" box and is left out entirely when
    # it would be empty.
    no_slides <- isTRUE(mod$no_slides)
    resource_btns <- c(
      if (no_slides) NULL else build_resource_button("slides", u$slides, oneline(u$title)),
      if (inline_transcripts) NULL else build_resource_button("transcript", u$transcript, oneline(u$title))
    )
    progress_control <- if (length(resource_btns) == 0) "" else
      paste0("<div class=\"progress-control\">\n", paste(resource_btns, collapse = "\n"), "\n</div>")

    upage <- fill(unit_tpl, list(
      ID           = paste0(mid, "-", uid),
      NUMBER       = as.integer(i),
      MODULE_TITLE = oneline(mod$title %||% sprintf("Module %s", mid)),
      UNIT_NUMBER  = as.integer(j),
      UNIT_TOTAL   = as.integer(m),
      UNIT_TITLE   = oneline(u$title %||% sprintf("Unit %s", uid)),
      MEDIA        = build_media(u$video, u$title, u$duration, u$videos),
      PROGRESS_CONTROL = progress_control,
      BREADCRUMB   = build_breadcrumb(ucrumbs),
      AFTER_COMPLETE = after,
      PAGER        = build_pager("Unit navigation", uprev, unext)
    ))
    uheader <- paste0(
      "<!-- GENERATED FILE. Do not edit by hand.\n",
      "     Source: content/modules.yml + modules/_unit-template.qmd\n",
      "     Rebuild: Rscript R/build_modules.R -->\n"
    )
    uout_file <- file.path(out_dir, sprintf("module-%s-unit-%s.qmd", mid, uid))
    if (write_if_changed(uout_file, paste0(uheader, upage))) {
      written <- c(written, basename(uout_file))
    }
  }

  manifest_entries <- c(manifest_entries, sprintf('  "%s": %s', mid, json_str_array(unit_ids)))
}

if (length(written) > 0) {
  message(sprintf("build_modules.R: wrote %d page(s): %s",
                  length(written), paste(written, collapse = ", ")))
} else {
  message("build_modules.R: no pages changed")
}

# --- Manifest for the progress script + certificate page --------------------
# Inlined as a <script> (like assets/progress-init.html) rather than linked by
# src="/assets/...", so a GitHub Pages project subpath cannot break the URL.
manifest_html <- paste0(
  "<!-- GENERATED FILE. Do not edit by hand.\n",
  "     Source: content/modules.yml. Rebuild: Rscript R/build_modules.R -->\n",
  "<script>\n",
  "// Module id -> ordered list of its unit ids. Used by\n",
  "// assets/progress-init.html and certificate.qmd to compute module and\n",
  "// series completion without hard-coding counts in multiple places.\n",
  "// Module 4 (Resources) is intentionally absent. It has no units and is\n",
  "// not part of progress tracking.\n",
  "window.penManifest = {\n",
  paste(manifest_entries, collapse = ",\n"),
  "\n};\n",
  "</script>\n"
)
if (write_if_changed(manifest_path, manifest_html)) {
  message("build_modules.R: wrote assets/pen-manifest.html")
}
