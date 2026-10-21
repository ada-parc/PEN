# post_render.R
# Runs after every `quarto render` (post-render hook in _quarto.yml).
#
# Quarto 1.4 writes _site/search.json even with `search: false`. Nothing reads
# it (there is no search box), so remove it rather than publish a text index of
# every page. Quarto resolves hook paths from the project root, and sets
# QUARTO_PROJECT_OUTPUT_DIR for post-render scripts.

out <- Sys.getenv("QUARTO_PROJECT_OUTPUT_DIR", unset = "_site")
unlink(file.path(out, "search.json"))
