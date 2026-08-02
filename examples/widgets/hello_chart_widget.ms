# Hello on-chart widget — MuseScript overlay (executable)
#
# Registered as glcharts indicator id MSW_<ID> when placement is chart|both.
# Docs: mobile/src/terminal/widgets/MUSESCRIPT_WIDGETS.md
#
# @widget id=hello_chart
# @placement chart
# @surface pre
# @chart.target overlay
# @chart.labels mid=sma

{
  @indicator("sma") function(len) {
    if (bar_index + 1 < len) return null;
    var s = 0.0; var i = 0;
    while (i < len) { s = s + close[i]; i = i + 1; }
    return s / len;
  }
  @strategy("hello_chart") @param("n", 20)
  @on(bar) { plot(sma(n), "sma"); }
}
