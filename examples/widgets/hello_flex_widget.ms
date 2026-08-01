# Hello FlexLayout widget — MuseScript side (scaffold)
#
# Documents the *intent* of a user-authored terminal panel.
# Instrument Terminal mounts it today as an honesty-gated `pre` stub
# (FlexLayout component id `ms:hello`). A future runtime will execute
# panel compute and push a typed view-model — not raw JSX.
#
# Manifest (host): kalshai/mobile/src/terminal/widgets/museScriptWidgets.js
# Design: production_terminal_inspo/MUSESCRIPT_FLEX_WIDGETS.md
#
# @widget id=hello
# @surface pre
# @bindings symbol, truth.verdict
# @honestyGated true
#
# Pseudocode contract (not executed by the stub host):
#   panel view:
#     title: "Hello MuseScript"
#     lines: symbol, verdict (or "—")
#     gate: require truth.verdict before any metric paint
#
# Prefer declaring bindings + honesty gates over inventing confidence chrome.
