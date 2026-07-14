package musescript.examples;

import musescript.parse.MuseParser;
import musescript.compile.MuseCompiler;
import musescript.harness.HarnessContext;
import musescript.harness.BarFeed;
import musescript.builtins.TradeBuiltins;

/**
 * Example 01 — MA crossover on synthetic bars (compiled JS by default).
 */
class HelloBar {
	static function main() {
		var source = '
		{
			@strategy("ma_cross")
			@param("fast", 10)
			@param("slow", 30)

			@on(bar) {
				var maFast = sma("close", fast);
				var maSlow = sma("close", slow);
				if (crossover(maFast, maSlow)) long();
				if (crossunder(maFast, maSlow)) flat();
				plot(maFast, "fast");
				plot(maSlow, "slow");
			}
		}
		';

		var harness = new HarnessContext();
		harness.params.register("fast", 10, 5, 50, 1, "grid");
		harness.params.register("slow", 30, 10, 100, 1, "grid");

		var prog = new MuseParser().parse(source, "01-hello-bar.ms");
		var feed = BarFeed.synthetic(400, 42);
		Reflect.setField(harness, "feed", feed);

		TradeBuiltins.resetCrossState();
		var ex = MuseCompiler.compileEx(prog, { target: "js", strict: true });
		var result:Dynamic = ex.fn(harness);

		Sys.println("=== MuseScript 01-hello-bar ===");
		Sys.println("strategy: ma_cross");
		Sys.println("backend: " + ex.backend);
		Sys.println("bars: " + feed.length());
		Sys.println("trades: " + result.trades);
		Sys.println("sharpe: " + result.sharpe);
		Sys.println("maxDD: " + result.maxDrawdown);
		Sys.println("finalEquity: " + result.finalEquity);
		Sys.println("chartCommands: " + harness.chart.commands.length);
	}
}
