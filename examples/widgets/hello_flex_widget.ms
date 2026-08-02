# Hello FlexLayout widget — MuseScript panel (executable)
#
# Host: kalshai/mobile/src/terminal/widgets/
# Docs: mobile/src/terminal/widgets/MUSESCRIPT_WIDGETS.md
#
# @widget id=hello
# @surface table
# @placement panel
# @bindings symbol, bars, truth.verdict
# @honestyGated true
#
# Contract: plot() → series / last values; log("key=value") → table rows.

{
  @indicator("sma") function(len) {
    if (bar_index + 1 < len) return null;
    var s = 0.0; var i = 0;
    while (i < len) { s = s + close[i]; i = i + 1; }
    return s / len;
  }
  @strategy("hello_panel") @param("n", 20)
  @on(bar) {
    var m = sma(n);
    plot(close, "close");
    plot(m, "sma");
    log("close=" + close);
    if (m != null) { log("sma=" + m); }
  }
}
