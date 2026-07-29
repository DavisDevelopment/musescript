package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.ew.ForecastHostParityDump;
import musescript.ew.ForecastHostRuntime;

/**
 * Initiative 2.1 — lock ForecastHostParityDump.render() against golden, plus a
 * smoke that ForecastHostRuntime.forecast returns ok clouds for each kind.
 * Cross-target JVM↔node: `tools/forecast_host_parity_ci.ps1` / `.sh`.
 */
class TestForecastHostParity extends Test {
	static function loadGolden():String {
		var paths = [
			"testdata/forecast-host-parity.golden.txt",
			"../testdata/forecast-host-parity.golden.txt"
		];
		for (p in paths) {
			if (sys.FileSystem.exists(p)) {
				var s = sys.io.File.getContent(p);
				return StringTools.replace(s, "\r\n", "\n");
			}
		}
		return null;
	}

	public function testRenderMatchesGoldenFile() {
		var got = StringTools.replace(ForecastHostParityDump.render(), "\r\n", "\n");
		var golden = loadGolden();
		Assert.isTrue(golden != null && golden.length > 0, "missing testdata/forecast-host-parity.golden.txt");
		got = StringTools.trim(got) + "\n";
		golden = StringTools.trim(golden) + "\n";
		Assert.equals(golden, got, "ForecastHostParityDump.render drifted from golden — regenerate testdata if intentional");
	}

	public function testRenderIdempotent() {
		Assert.equals(ForecastHostParityDump.render(), ForecastHostParityDump.render());
	}

	public function testRuntimeKindsAndRegimeSmoke() {
		Assert.equals(3, ForecastHostRuntime.kinds().length);
		var bars:Array<Dynamic> = [];
		var px = 100.0;
		for (i in 0...50) {
			px += (i % 5 == 0 ? 0.5 : -0.2);
			bars.push({ open: px, high: px + 0.3, low: px - 0.3, close: px, volume: 1000, time: i });
		}
		// Tiny MCMC budget for unit-test speed.
		var r:Dynamic = ForecastHostRuntime.forecast("regime", bars, {
			seed: 1, horizon: 5, window: 40, steps: 80, burnIn: 20, nPaths: 20, k: 2
		});
		Assert.equals(true, Reflect.field(r, "ok"), Std.string(Reflect.field(r, "error")));
		Assert.equals("regime", Reflect.field(r, "kind"));

		var a:Dynamic = ForecastHostRuntime.forecast("auction", bars, { window: 20, horizon: 5 });
		Assert.equals(true, Reflect.field(a, "ok"), Std.string(Reflect.field(a, "error")));

		var l:Dynamic = ForecastHostRuntime.forecast("lattice", bars, { k: 3, fineThreshold: 0.02 });
		Assert.equals(true, Reflect.field(l, "ok"), Std.string(Reflect.field(l, "error")));
	}
}
