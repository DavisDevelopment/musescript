package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.parse.MuseParser;
import musescript.interp.MuseInterp;
import musescript.harness.HarnessContext;
import musescript.harness.BarFeed;

/**
 * IDE instrumentation surface: the equity curve, per-bar console log, executed
 * fill log, and chart commands the Strategy Studio consumes. All are collected
 * as a side effect of a normal backtest and must be populated after a run.
 * Uses the interp path so the assertions hold on both the JS and Python targets.
 */
class TestInstrumentation extends Test {
	public function testLogBufferCapturesPerBar() {
		var source = '
			@strategy("logtest")
			@on(bar) {
				log("bar", close);
			}
		';
		var harness = new HarnessContext();
		var prog = new MuseParser().parse(source);
		new MuseInterp(harness).runBacktest(prog, BarFeed.synthetic(20, 3));
		Assert.equals(20, harness.logs.length);
		// each entry is bar-tagged and carries the joined message
		Assert.isTrue(harness.logs[0].bar >= 0);
		Assert.isTrue(StringTools.startsWith(harness.logs[5].msg, "bar "));
	}

	public function testChartCommandsCaptured() {
		var source = '
			@strategy("charttest")
			@on(bar) {
				plot(close, "px");
			}
		';
		var harness = new HarnessContext();
		var prog = new MuseParser().parse(source);
		new MuseInterp(harness).runBacktest(prog, BarFeed.synthetic(15, 3));
		Assert.equals(15, harness.chart.commands.length);
		Assert.equals("plot", harness.chart.commands[0].kind);
		Assert.equals("px", harness.chart.commands[0].label);
	}

	public function testFillLogRecordsEntriesAndExits() {
		var source = '
			@strategy("filltest")
			@on(bar) {
				if (crossover(sma("close", 3), sma("close", 8))) long();
				if (crossunder(sma("close", 3), sma("close", 8))) flat();
			}
		';
		var harness = new HarnessContext();
		var prog = new MuseParser().parse(source);
		var result = new MuseInterp(harness).runBacktest(prog, BarFeed.synthetic(120, 7));
		var fills = harness.orders.fills;
		// fill count matches the trade counter, and each fill is a valid kind
		Assert.equals(result.trades, fills.length);
		Assert.isTrue(fills.length > 0);
		for (f in fills) {
			Assert.isTrue(f.kind == "long" || f.kind == "short" || f.kind == "flat");
			Assert.isTrue(f.bar >= 0);
		}
	}

	public function testResetForTrialClearsInstrumentation() {
		var harness = new HarnessContext();
		harness.pushLog("x");
		harness.orders.fills.push({ kind: "long", bar: 0, price: 1.0, qty: 1.0, pnl: 0.0 });
		harness.resetForTrial();
		Assert.equals(0, harness.logs.length);
		Assert.equals(0, harness.orders.fills.length);
	}
}
