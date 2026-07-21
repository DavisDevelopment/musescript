package musescript.examples;

import haxe.Timer;
import musescript.harness.Bar;
import musescript.harness.HarnessContext;
import musescript.harness.OhlcvCsv;
import musescript.indicators.IndicatorRegistry;
import musescript.indicators.IndicatorSpec;
import musescript.types.MuseType;

/**
 * Full-registry × full-tape-inventory indicator benchmark, built for the JVM
 * target so it runs under GraalVM's JIT (`haxe ... --jvm build/jvm/indicator-bench.jar`,
 * then `$GRAALVM_HOME/bin/java -jar ...`).
 *
 * For EVERY registered indicator (IndicatorRegistry — the same table the
 * builtins/ta toolbelt dispatch from) against EVERY OHLCV CSV tape under the
 * repo's tape directories: fresh HarnessContext, feed each bar once, call the
 * indicator's `spec().eval` per bar exactly like the interp/JS engines do.
 * Default args are synthesized from the typed signature with the same rules
 * as the registry safety-net test (series→close, windows→5,10,15…, scalar→0.5);
 * an indicator whose constructor rejects that combo ("must be …") is counted
 * as skipped, not failed — same convention as testEveryRegisteredIndicatorIsCallable.
 *
 * Two full passes: pass 1 cold (JIT warming on every indicator's code path),
 * pass 2 warm — the reported numbers. Writes a JSON artifact with the full
 * per-indicator and per-tape matrix to build/bench/indicator-tape-bench.json.
 */
class IndicatorTapeBench {
	static var TAPE_DIRS = [
		"corpus/tapes",
		"data/real",
		"examples/strategy-tournament/tapes",
		"examples/strategy-tournament/tapes-crypto-fx",
	];

	public static function main():Void {
		var root = Sys.args().length > 0 ? Sys.args()[0] : ".";

		Sys.println("=== MuseScript indicator × tape benchmark (JVM/GraalVM) ===");
		#if jvm
		Sys.println("jvm:  " + java.lang.System.getProperty("java.vm.name")
			+ " " + java.lang.System.getProperty("java.vm.version"));
		#end

		// ── inventory ────────────────────────────────────────────────────────
		var tapes:Array<{path:String, bars:Array<Bar>}> = [];
		for (dir in TAPE_DIRS) {
			var full = root + "/" + dir;
			if (!sys.FileSystem.exists(full)) continue;
			var names = sys.FileSystem.readDirectory(full);
			names.sort(Reflect.compare);
			for (n in names) {
				if (!StringTools.endsWith(n, ".csv")) continue;
				var p = full + "/" + n;
				try {
					var bars = OhlcvCsv.load(p);
					if (bars.length > 0) tapes.push({ path: dir + "/" + n, bars: bars });
				} catch (e:Dynamic) {
					Sys.println('  ! skipping unreadable tape $p: $e');
				}
			}
		}

		var specs:Array<IndicatorSpec> = [for (_ => s in IndicatorRegistry.all()) s];
		specs.sort((a, b) -> Reflect.compare(a.name, b.name));

		var totalBars = 0;
		for (t in tapes) totalBars += t.bars.length;
		Sys.println('tapes: ${tapes.length} (${totalBars} bars total)   indicators: ${specs.length}');
		Sys.println('grid:  ${specs.length} indicators x ${tapes.length} tapes = ${specs.length * tapes.length} runs/pass, ${specs.length * totalBars} evals/pass');

		// ── two passes: cold (JIT warmup) + warm (reported) ──────────────────
		var cold = runPass(specs, tapes, "pass 1 (cold, JIT warming)");
		var warm = runPass(specs, tapes, "pass 2 (warm)");

		// ── report ────────────────────────────────────────────────────────────
		var indRows = warm.perIndicator;
		indRows.sort((a, b) -> a.ms < b.ms ? 1 : (a.ms > b.ms ? -1 : 0));

		Sys.println("\n--- top 15 slowest indicators (warm, total across all tapes) ---");
		for (i in 0...Std.int(Math.min(15, indRows.length))) {
			var r = indRows[i];
			Sys.println('  ${pad(r.name, 32)} ${fmt(r.ms, 8)} ms   ${fmt(r.evals / (r.ms / 1000.0) / 1e6, 6)} M evals/s');
		}
		Sys.println("\n--- top 10 fastest indicators (warm) ---");
		var k = indRows.length - 1;
		var shown = 0;
		while (k >= 0 && shown < 10) {
			var r = indRows[k];
			if (r.evals > 0) {
				Sys.println('  ${pad(r.name, 32)} ${fmt(r.ms, 8)} ms   ${fmt(r.evals / (r.ms / 1000.0) / 1e6, 6)} M evals/s');
				shown++;
			}
			k--;
		}

		Sys.println("\n--- per-tape totals (warm, all indicators) ---");
		for (t in warm.perTape) {
			Sys.println('  ${pad(t.path, 64)} ${pad(Std.string(t.bars), 6)} bars  ${fmt(t.ms, 9)} ms');
		}

		var coldRate = warm.totalEvals / (cold.totalMs / 1000.0) / 1e6;
		var warmRate = warm.totalEvals / (warm.totalMs / 1000.0) / 1e6;
		Sys.println("\n--- summary ---");
		Sys.println('runs ok: ${warm.ok}   constructor-skipped: ${warm.skipped}   errors: ${warm.errors}');
		Sys.println('pass 1 (cold): ${fmt(cold.totalMs, 1)} ms   (${fmt(coldRate, 3)} M indicator-evals/s)');
		Sys.println('pass 2 (warm): ${fmt(warm.totalMs, 1)} ms   (${fmt(warmRate, 3)} M indicator-evals/s)');
		Sys.println('JIT speedup:   ${fmt(cold.totalMs / warm.totalMs, 2)}x');

		// ── JSON artifact ──────────────────────────────────────────────────────
		var outDir = root + "/build/bench";
		if (!sys.FileSystem.exists(outDir)) sys.FileSystem.createDirectory(outDir);
		var artifact = {
			schema: "musescript.bench/indicator-tape/1",
			generatedAt: Date.now().toString(),
			jvm: #if jvm java.lang.System.getProperty("java.vm.name") + " " + java.lang.System.getProperty("java.vm.version") #else "n/a" #end,
			indicators: specs.length,
			tapes: [for (t in tapes) { path: t.path, bars: t.bars.length }],
			totals: {
				evals: warm.totalEvals,
				coldMs: cold.totalMs,
				warmMs: warm.totalMs,
				ok: warm.ok, skipped: warm.skipped, errors: warm.errors
			},
			perIndicator: [for (r in warm.perIndicator) {
				name: r.name, ms: r.ms, evals: r.evals,
				coldMs: lookupMs(cold.perIndicator, r.name),
				status: r.status
			}],
			perTape: warm.perTape
		};
		var outPath = outDir + "/indicator-tape-bench.json";
		sys.io.File.saveContent(outPath, haxe.Json.stringify(artifact, null, "  "));
		Sys.println('\nwrote $outPath');
	}

	static function runPass(specs:Array<IndicatorSpec>, tapes:Array<{path:String, bars:Array<Bar>}>, label:String) {
		Sys.println('\n--- $label ---');
		var perIndicator:Array<{name:String, ms:Float, evals:Int, status:String}> = [];
		var perTape:Array<{path:String, bars:Int, ms:Float}> = [for (t in tapes) { path: t.path, bars: t.bars.length, ms: 0.0 }];
		var ok = 0, skipped = 0, errors = 0;
		var totalMs = 0.0, totalEvals = 0;
		var passStart = Timer.stamp();

		for (spec in specs) {
			var args = synthArgs(spec);
			var indMs = 0.0, indEvals = 0;
			var status = "ok";

			for (ti in 0...tapes.length) {
				var tape = tapes[ti];
				var h = new HarnessContext();
				var t0 = Timer.stamp();
				try {
					for (bar in tape.bars) {
						h.observeBar(bar);
						spec.eval(h, args);
					}
					var dt = (Timer.stamp() - t0) * 1000.0;
					indMs += dt;
					indEvals += tape.bars.length;
					perTape[ti].ms += dt;
				} catch (e:Dynamic) {
					// Constructor-time arg validation ("must be ..." / "requires ...",
					// both phrasings verbatim from the Rust panics) = the default
					// combo doesn't satisfy this indicator; anything else is a bug.
					var msg = Std.string(e);
					if (msg.indexOf("must be") >= 0 || msg.indexOf("requires") >= 0) status = "skipped";
					else { status = "error: " + msg; }
					break;
				}
			}

			switch (status) {
				case "ok": ok++;
				case "skipped": skipped++;
				default:
					errors++;
					Sys.println('  ! ${pad(specName(spec), 30)} $status');
			}
			totalMs += indMs;
			totalEvals += indEvals;
			perIndicator.push({ name: spec.name, ms: indMs, evals: indEvals, status: status });
		}

		Sys.println('  wall: ${fmt((Timer.stamp() - passStart) * 1000.0, 1)} ms   measured: ${fmt(totalMs, 1)} ms   evals: $totalEvals');
		return { perIndicator: perIndicator, perTape: perTape, ok: ok, skipped: skipped, errors: errors, totalMs: totalMs, totalEvals: totalEvals };
	}

	/** Same synthesis rules as TestIndicatorPorts.testEveryRegisteredIndicatorIsCallable. */
	static function synthArgs(spec:IndicatorSpec):Array<Dynamic> {
		var windowIdx = 0;
		return [for (t in spec.args) {
			switch (t) {
				case TSeries: ("close" : Dynamic);
				case TWindow: { windowIdx++; ((5 * windowIdx : Float) : Dynamic); }
				case TString: ("x" : Dynamic);
				default: (0.5 : Dynamic);
			}
		}];
	}

	static function lookupMs(rows:Array<{name:String, ms:Float, evals:Int, status:String}>, name:String):Float {
		for (r in rows) if (r.name == name) return r.ms;
		return -1;
	}

	static inline function specName(s:IndicatorSpec):String return s.name;

	static function pad(s:String, n:Int):String {
		while (s.length < n) s += " ";
		return s;
	}

	static function fmt(v:Float, w:Int):String {
		var s = Math.abs(v) >= 100 ? Std.string(Math.round(v)) : Std.string(Math.round(v * 100) / 100);
		while (s.length < w) s = " " + s;
		return s;
	}
}
