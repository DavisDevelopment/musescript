package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.parse.MuseParser;
import musescript.interp.MuseInterp;
import musescript.harness.HarnessContext;
import musescript.harness.BarFeed;
import musescript.builtins.TaSources;
import musescript.builtins.TaSourceRender;

/**
 * Parity harness for `ta.nativeSource(name)`: for each indicator that has one,
 * runs the native MuseScript reimplementation and the registered Haxe builtin
 * over the SAME bar tape and asserts they agree bar-for-bar (nulls included).
 * The point of a native reimplementation is that it's a genuine alternative
 * execution path (forkable, sometimes faster natively) — this is what proves
 * it's not just *a* MuseScript source, but the *same* indicator.
 *
 * Generic over every indicator that opts in via `nativeSource()` (see
 * TaSourceEntry.nativeSource's doc comment) — adding one to a new indicator
 * gets parity-checked here for free, no edit to this file required, AS LONG AS
 * the convention below holds: a native source's declared args are the
 * builtin's args with a single LEADING `TSeries` dropped (native bodies read
 * price via `close[i]` lookback directly, never as a passed argument — see
 * Cmo.nativeSource for the reference shape). Indicators with a non-leading or
 * multiple TSeries args (pair-input ports, "cross two series" style) aren't
 * representable by this convention yet and should be skipped by their own
 * nativeSource() simply not existing until that's designed.
 */
class TestNativeIndicatorParity extends Test {
	public function testEveryNativeSourceMatchesItsBuiltinOverASharedTape() {
		var bars = BarFeed.synthetic(80, 13).all();
		var checked = 0;
		for (name in TaSources.names()) {
			var entry = TaSources.get(name);
			if (entry.nativeSource == null) continue;
			checked++;

			var builtinArgs = TaSourceRender.defaultArgs(entry.argKinds);
			var nativeArgKinds = entry.argKinds.length > 0 && entry.argKinds[0] == "TSeries"
				? entry.argKinds.slice(1) : entry.argKinds;
			var nativeArgs = TaSourceRender.defaultArgs(nativeArgKinds);

			var nativeProg = new MuseParser().parse(entry.nativeSource + '
				@strategy("native")
				@on(bar) {
					var v = $name(${nativeArgs.join(", ")});
					log("v|" + v);
				}
			', "<native:" + name + ">");
			var nativeHarness = new HarnessContext();
			new MuseInterp(nativeHarness).runBacktest(nativeProg, new BarFeed(bars.copy()));
			var nativeVals = [for (l in nativeHarness.logs) l.msg.substr(2)];

			var builtinProg = new MuseParser().parse('
				@strategy("builtin")
				@on(bar) {
					var v = $name(${builtinArgs.join(", ")});
					log("v|" + v);
				}
			', "<builtin:" + name + ">");
			var builtinHarness = new HarnessContext();
			new MuseInterp(builtinHarness).runBacktest(builtinProg, new BarFeed(bars.copy()));
			var builtinVals = [for (l in builtinHarness.logs) l.msg.substr(2)];

			Assert.equals(builtinVals.length, nativeVals.length, '$name: bar count mismatch');
			for (i in 0...builtinVals.length) {
				var bStr = builtinVals[i], nStr = nativeVals[i];
				// Warmup sentinels differ by DESIGN, not by bug: the dispatched builtin path
				// (IndicatorCache.evalSeries) normalizes "not ready" to NaN for uniform numeric
				// typing at the call site, while a bare `MuseIndicator.update()` -- and the
				// native @indicator mirroring it 1:1 -- returns a real `null`. Both mean
				// "not ready yet"; only a value on ONE side while the other is ready is real.
				var bWarm = bStr == "null" || bStr == "NaN";
				var nWarm = nStr == "null" || nStr == "NaN";
				if (bWarm || nWarm) {
					Assert.equals(bWarm, nWarm, '$name bar $i: warmup mismatch (native=$nStr builtin=$bStr)');
					continue;
				}
				var b = Std.parseFloat(bStr), n = Std.parseFloat(nStr);
				Assert.isTrue(Math.abs(b - n) < 1e-9, '$name bar $i: native=$n builtin=$b');
			}
		}
		Assert.isTrue(checked >= 1, "expected at least one indicator with a nativeSource to check");
	}
}
