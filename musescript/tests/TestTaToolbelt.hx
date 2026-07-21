package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.builtins.TaSources;
import musescript.builtins.TradeBuiltins;
import musescript.compile.MuseCompiler;
import musescript.harness.Bar;
import musescript.harness.BarFeed;
import musescript.harness.HarnessContext;
import musescript.indicators.IndicatorRegistry;
import musescript.interp.MuseInterp;
import musescript.parse.MuseParser;

/**
 * The `ta` toolbelt: TaSourcesMacro bakes a generated MuseScript source per
 * ported indicator (reflection-accessible via TaSources), and TaToolbelt
 * exposes the same registry + those sources inside the language as the `ta`
 * global. These tests gate the three promises: total coverage of the
 * registry, generated sources that actually PARSE as MuseScript, and
 * in-language `ta.*` behavior identical to the flat builtins.
 */
class TestTaToolbelt extends Test {
	static function bar(o:Float, h:Float, l:Float, c:Float, v:Float, i:Int):Bar {
		return { open: o, high: h, low: l, close: c, volume: v, time: (i : Float), index: i };
	}

	static function randomBars(n:Int, seed:Int):Array<Bar> {
		var s = seed;
		function rnd():Float {
			s = (s * 1103515245 + 12345) & 0x7fffffff;
			return (s % 1000) / 1000.0;
		}
		var price = 100.0;
		return [for (i in 0...n) {
			var c = price + (rnd() - 0.5) * 2.0;
			var b = bar(price, Math.max(price, c) + 0.5, Math.min(price, c) - 0.5, c, 100.0 + rnd() * 50, i);
			price = c;
			b;
		}];
	}

	// ── coverage ─────────────────────────────────────────────────────────────

	public function testEveryRegisteredIndicatorHasASource() {
		for (name in IndicatorRegistry.all().keys()) {
			var e = TaSources.get(name);
			Assert.notNull(e, 'no ta source for registered indicator "$name"');
			if (e == null) continue;
			Assert.isTrue(e.source.length > 0, '"$name" has an empty source');
			Assert.isTrue(e.sig.indexOf(name + "(") == 0, '"$name" sig malformed: ${e.sig}');
		}
	}

	public function testMacroBakedSourcesAreTheCommonPath() {
		// The runtime fallback marks entries with file == "?" — the macro's
		// literal-spec extraction should cover essentially everything, so a
		// fallback-heavy table means the extractor regressed.
		var total = 0, baked = 0;
		for (n in TaSources.names()) {
			total++;
			if (TaSources.get(n).file != "?") baked++;
		}
		Assert.isTrue(total >= 400, 'expected the full ported set, got $total');
		Assert.isTrue(baked / total > 0.95, 'only $baked/$total ta sources were macro-baked');
	}

	public function testKnownEntryIsBakedWithDocAndFile() {
		var e = TaSources.get("cmo");
		Assert.notNull(e);
		Assert.equals("Cmo.hx", e.file);
		Assert.isTrue(e.doc.length > 0, "doc title should come from the class doc comment");
		Assert.isTrue(e.source.indexOf("cmo(close, 5)") >= 0, e.source);
	}

	// ── generated sources are real MuseScript ────────────────────────────────

	public function testEveryGeneratedSourceParses() {
		var parser = new MuseParser();
		for (name in TaSources.names()) {
			var e = TaSources.get(name);
			try {
				var prog = parser.parse(e.source);
				Assert.notNull(prog, '"$name" source parsed to null');
			} catch (ex:Dynamic) {
				Assert.fail('generated source for "$name" does not parse: $ex\n${e.source}');
			}
		}
	}

	public function testEveryGeneratedSourceRunsAsABacktest() {
		// The generated demo strategies must not just parse — they must run.
		// Same net as testEveryRegisteredIndicatorIsCallable: constructor-time
		// argument-validation throws ("must be ...") prove correct wiring with
		// an unsatisfiable default combo and are not failures.
		var bars = randomBars(60, 1234);
		for (name in TaSources.names()) {
			var e = TaSources.get(name);
			var harness = new HarnessContext();
			try {
				new MuseInterp(harness).runBacktest(
					new MuseParser().parse(e.source), new BarFeed(bars.copy()));
			} catch (ex:Dynamic) {
				var msg = Std.string(ex);
				if (msg.indexOf("must be") == -1 && msg.indexOf("requires") == -1)
					Assert.fail('generated source for "$name" failed to run: $ex\n${e.source}');
			}
		}
		Assert.pass();
	}

	// ── the `ta` global inside the language ──────────────────────────────────

	public function testTaCallMatchesFlatBuiltin() {
		var source = '
			@strategy("ta-parity")
			@on(bar) {
				var flat = cmo(close, 14);
				var belted = ta.cmo(close, 14);
				if (!na(flat) && flat != belted) long();
			}
		';
		var harness = new HarnessContext();
		var result = new MuseInterp(harness).runBacktest(
			new MuseParser().parse(source), new BarFeed(randomBars(120, 7)));
		// ta.cmo and cmo share the registry (though separate cached instances) —
		// identical inputs must give identical outputs, so the long() never fires.
		Assert.equals(0, result.trades);
	}

	public function testTaCallInterpJsParity() {
		// Same discipline as TestIndicatorPorts' interp<->compiled-JS parity
		// net: a strategy trading off ta.* values must behave identically in
		// both execution paths (exercises JsEmitter's ta.-call series-name
		// argument case + the JsBackend `ta` frame install).
		var source = '
			@strategy("ta-js-parity")
			@on(bar) {
				var m = ta.cmo(close, 14);
				var w = ta.williams_r(10);
				if (!na(m) && m > 30 && w > -50) long();
				if (!na(m) && m < -30) flat();
			}
		';
		var bars = randomBars(200, 42);

		var interpHarness = new HarnessContext();
		var interpResult = new MuseInterp(interpHarness).runBacktest(
			new MuseParser().parse(source), new BarFeed(bars.copy()));

		#if js
		var jsHarness = new HarnessContext();
		jsHarness.feed = new BarFeed(bars.copy());
		TradeBuiltins.resetCrossState();
		var ex = MuseCompiler.compileEx(new MuseParser().parse(source), { target: "js", strict: false });
		Assert.equals("js", ex.backend);
		var jsResult = ex.fn(jsHarness);
		Assert.equals(interpResult.trades, jsResult.trades);
		Assert.floatEquals(interpResult.finalEquity, jsResult.finalEquity);
		#end
	}

	public function testTaIntrospectionBuiltinsInLanguage() {
		var source = '
			@strategy("ta-introspect")
			@on(bar) {
				var names = ta.names();
				var ok = ta.has("cmo") && !ta.has("nope_never");
				var src = ta.source("cmo");
				var sig = ta.sig("cmo");
				if (ok && count(names) > 400 && str_contains(src, "@strategy") && str_contains(sig, "cmo(")) long();
			}
		';
		var harness = new HarnessContext();
		var result = new MuseInterp(harness).runBacktest(
			new MuseParser().parse(source), new BarFeed(randomBars(30, 3)));
		Assert.isTrue(result.trades > 0, "ta introspection surface should be visible in-language");
	}

	// ── reflection access on the Haxe side ───────────────────────────────────

	public function testEntriesAreReflectionAccessible() {
		var e:Dynamic = TaSources.get("obv");
		Assert.notNull(e);
		Assert.isTrue(Reflect.hasField(e, "source"));
		Assert.isTrue(Reflect.hasField(e, "sig"));
		Assert.isTrue(Reflect.hasField(e, "doc"));
		Assert.isTrue(Reflect.hasField(e, "file"));
		var src:String = Reflect.field(e, "source");
		Assert.isTrue(src.indexOf("obv()") >= 0);
	}
}
