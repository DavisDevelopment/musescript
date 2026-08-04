package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.builtins.MuseHost;
import musescript.builtins.StatsBuiltins;
import musescript.compile.MuseHostLower;
import musescript.compile.MusePrinter;
import musescript.harness.Bar;
import musescript.harness.BarFeed;
import musescript.harness.ChartSink;
import musescript.harness.DiagPack;
import musescript.harness.HarnessContext;
import musescript.harness.Metrics;
import musescript.interp.MuseInterp;
import musescript.parse.MuseParser;
import musescript.runtime.MuseRuntime;
import musescript.types.PluginCapabilities;
import musescript.types.PluginKind;

/**
 * Post-run muse.diag / DiagPack — ACF + kiss-the-curve ChartSink pack.
 */
class TestDiagPack extends Test {
	static function risingEquity():Array<Float> {
		return [100.0, 110.0, 121.0, 133.1];
	}

	static function kissEquity():Array<Float> {
		// Peak at 120, underwater mid, kiss again at end.
		return [100.0, 120.0, 90.0, 100.0, 120.0];
	}

	public function testResolveFlatDiag() {
		Assert.equals("diag_pack", MuseHost.resolveFlat("diag", "pack"));
		Assert.equals("diag_kiss", MuseHost.resolveFlat("diag", "kiss"));
		Assert.equals("diag_acf", MuseHost.resolveFlat("diag", "acf"));
		Assert.equals("diag_running_max", MuseHost.resolveFlat("diag", "running_max"));
	}

	public function testMuseHostLowerRewritesDiag() {
		var src = '
			strategy S {
			  onBar {
			    muse.diag.pack(null, 10, 20)
			    muse.diag.acf([1.0, 2.0], 5)
			  }
			}
		';
		var prog = MuseHostLower.lower(new MuseParser().parse(src));
		var printed = new MusePrinter().printProgram(prog);
		Assert.isTrue(printed.indexOf("diag_pack(") >= 0, printed);
		Assert.isTrue(printed.indexOf("diag_acf(") >= 0, printed);
		Assert.isTrue(printed.indexOf("muse.diag") < 0, printed);
	}

	public function testRunningMaxAndDrawdown() {
		var eq = kissEquity();
		var peak = DiagPack.runningMax(eq);
		Assert.same([100.0, 120.0, 120.0, 120.0, 120.0], peak);
		var dd = DiagPack.drawdownSeries(eq);
		Assert.floatEquals(0.0, dd[0]);
		Assert.floatEquals(0.0, dd[1]);
		Assert.floatEquals(0.25, dd[2]); // (120-90)/120
		Assert.floatEquals(Metrics.maxDrawdown(eq), 0.25);
		Assert.equals(3, DiagPack.peakTouchCount(eq, peak)); // indices 0,1,4
	}

	public function testAcfMatchesStatAutocorr() {
		var rets = [0.1, -0.05, 0.02, 0.03, -0.01, 0.04, -0.02, 0.01];
		var got = DiagPack.acf(rets, 3);
		Assert.equals(3, got.length);
		Assert.floatEquals(StatsBuiltins.autocorr(rets, 1), got[0]);
		Assert.floatEquals(StatsBuiltins.autocorr(rets, 2), got[1]);
		Assert.floatEquals(StatsBuiltins.autocorr(rets, 3), got[2]);
	}

	public function testRollingLag1Acf() {
		var rets = [for (i in 0...30) (i % 3 == 0 ? 0.02 : -0.01)];
		var roll = DiagPack.rollingAcf(rets, 10, 1);
		Assert.equals(30, roll.length);
		Assert.isTrue(Math.isNaN(roll[8]));
		Assert.isFalse(Math.isNaN(roll[9]));
		var slice = [for (j in 0...10) rets[j]];
		Assert.floatEquals(StatsBuiltins.autocorr(slice, 1), roll[9]);
	}

	public function testEmitPackChartCommands() {
		var chart = new ChartSink();
		var eq = kissEquity();
		var r = DiagPack.emit(chart, eq, { maxLag: 4, rollingWindow: 3, prefix: "diag" });
		Assert.equals(4, r.acf.length);
		Assert.isTrue(r.commandsAdded > 0);
		Assert.floatEquals(0.25, r.maxDrawdown);

		var kinds = [for (c in chart.commands) c.kind];
		Assert.isTrue(kinds.indexOf("plot") >= 0);
		Assert.isTrue(kinds.indexOf("hline") >= 0);

		var labels = [for (c in chart.commands) c.label];
		Assert.isTrue(labels.indexOf("diag.equity") >= 0);
		Assert.isTrue(labels.indexOf("diag.peak") >= 0);
		Assert.isTrue(labels.indexOf("diag.dd") >= 0);
		Assert.isTrue(labels.indexOf("diag.dd.zero") >= 0);
		Assert.isTrue(labels.indexOf("diag.acf") >= 0);
		Assert.isTrue(labels.indexOf("diag.acf.zero") >= 0);
		Assert.isTrue(labels.indexOf("diag.acf.roll1") >= 0);

		var acfCmds = [for (c in chart.commands) if (c.label == "diag.acf") c];
		Assert.equals(4, acfCmds.length);
		Assert.equals(1, acfCmds[0].barIndex);
		Assert.equals(4, acfCmds[3].barIndex);
	}

	public function testEmitKissOnly() {
		var chart = new ChartSink();
		DiagPack.emitKiss(chart, risingEquity());
		var labels = [for (c in chart.commands) c.label];
		Assert.isTrue(labels.indexOf("diag.equity") >= 0);
		Assert.isTrue(labels.indexOf("diag.peak") >= 0);
		Assert.isTrue(labels.indexOf("diag.dd") < 0);
		Assert.isTrue(labels.indexOf("diag.acf") < 0);
	}

	public function testMuseDiagPackInterp() {
		var src = '
			@strategy("diag-pack")
			@on(bar) {
				if (close > open) long();
			}
		';
		var bars:Array<Bar> = [for (i in 0...40)
			{ open: 100.0 + i, high: 101.0 + i, low: 99.0 + i, close: 100.5 + i,
			  volume: 1000.0, time: (i : Float), index: i, data: null }];
		var h = new HarnessContext();
		new MuseInterp(h).runBacktest(new MuseParser().parse(src), new BarFeed(bars));
		var before = h.chart.commands.length;
		var muse = MuseHost.build(h);
		var pack:Dynamic = Reflect.field(muse, "diag");
		var fn:Dynamic = Reflect.field(pack, "pack");
		var summary:Dynamic = Reflect.callMethod(pack, fn, [null, 8, 10]);
		Assert.isTrue(h.chart.commands.length > before);
		Assert.isTrue(Reflect.hasField(summary, "lag1"));
		Assert.isTrue(Reflect.hasField(summary, "acf"));
		Assert.isTrue(Std.int(Reflect.field(summary, "commandsAdded")) > 0);
	}

	public function testMuseRuntimeDiagPack() {
		var eq = kissEquity();
		var out:Dynamic = MuseRuntime.diagPack(eq, { maxLag: 5, rollingWindow: 3 });
		Assert.equals(true, Reflect.field(out, "ok"));
		var chart:Array<Dynamic> = Reflect.field(out, "chart");
		Assert.isTrue(chart.length > 0);
		var summary:Dynamic = Reflect.field(out, "summary");
		Assert.floatEquals(0.25, Reflect.field(summary, "maxDrawdown"));
	}

	public function testPluginCapabilitiesDiag() {
		Assert.equals(PluginCapabilities.CAP_CHART, PluginCapabilities.capabilityOf("diag_pack"));
		Assert.equals(PluginCapabilities.CAP_CHART, PluginCapabilities.capabilityOf("diag_kiss"));
		Assert.equals(PluginCapabilities.CAP_COMPUTE, PluginCapabilities.capabilityOf("diag_acf"));
		Assert.isTrue(PluginCapabilities.allows(PluginKind.Chart, "diag_pack"));
		Assert.isTrue(PluginCapabilities.allows(PluginKind.Compute, "diag_acf"));
		Assert.isFalse(PluginCapabilities.allows(PluginKind.Compute, "diag_pack"));
	}
}
