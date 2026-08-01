package musescript.ew;

import musescript.evo.rigor.PlantedCoEvo;
import musescript.evo.rigor.PreregGate;
import musescript.evo.rigor.SeedRobustness;
import musescript.harness.OhlcvCsv;
import musescript.harness.TapeLinter;

/**
 * Multi-CLI `--seed` restart matrix → {@link SeedRobustness.verdict}.
 *
 * Each seed is a full restart of bounded planted co-evo (not elite/host-seed median alone).
 *
 * ```
 * haxe build-seed-restart-matrix.hxml
 * node build/js/seed-restart-matrix.js --tape corpus/tapes/spy_oos_2022_2026.csv --seeds 42,7,99 --gens 2 --pop 6
 * ```
 */
class SeedRestartMatrixCli {
	static function main() {
		var tapePath = argStr("--tape", "corpus/tapes/spy_oos_2022_2026.csv");
		var seedsArg = argStr("--seeds", "42,7,99");
		var pop = argInt("--pop", 6);
		var gens = argInt("--gens", 2);
		var minTrades = argInt("--min-trades", 20);
		var nTrials = argInt("--n-trials", 5);
		var threshold = argFloat("--threshold", 0.0);
		var requireGo = argFlag("--require-go");
		var preregOn = argFlag("--prereg");
		var preregThreshold = argFloat("--prereg-threshold", 0.0);
		var maxBars = argInt("--max-bars", 800);

		Sys.println("=== SeedRestartMatrix (multi-CLI --seed → SeedRobustness) ===");
		Sys.println('tape=$tapePath seeds=$seedsArg pop=$pop gens=$gens threshold=$threshold');

		if (!OhlcvCsv.exists(tapePath)) {
			Sys.println('BLOCKER: tape not found at $tapePath');
			Sys.exit(2);
		}
		var bars = OhlcvCsv.load(tapePath);
		if (maxBars > 0 && bars.length > maxBars)
			bars = bars.slice(bars.length - maxBars, bars.length);
		Sys.println('bars=${bars.length} (max-bars=$maxBars)');
		var lint = TapeLinter.lint(bars, {allowZeroVolume: true});
		Sys.println(TapeLinter.formatReport(lint, 8));
		if (!TapeLinter.isClean(bars, {allowZeroVolume: true})) {
			Sys.println("VERDICT: NO-GO — tape failed integrity lint");
			Sys.exit(1);
		}

		var seeds = parseSeeds(seedsArg);
		if (seeds.length < 2) {
			Sys.println("BLOCKER: need ≥2 seeds for a restart matrix");
			Sys.exit(2);
		}

		var prereg = preregOn ? PreregGate.seal(preregThreshold, 5) : null;
		if (prereg != null) Sys.println("prereg SEALED: " + prereg.describe());

		var matrix = PlantedCoEvo.seedMatrix(bars, seeds, {
			pop: pop, gens: gens, minTrades: minTrades, nTrials: nTrials, threshold: threshold
		});

		for (r in matrix.runs) {
			Sys.println('[seed-restart] seed=${r.seed} gens=${r.gens}'
				+ ' oosSharpe=${fmt(r.championOosSharpe, 4)}'
				+ ' trades=${r.championTrades}'
				+ ' oos=${r.go ? "GO" : "NO-GO"}'
				+ ' null=${Reflect.field(r.nullOos, "go") == true ? "GO" : "NO-GO"}');
		}

		var v = matrix.verdict;
		Sys.println('[rigor seed-matrix] n=${v.n} median=${fmt(v.median, 4)} max=${fmt(v.max, 4)}'
			+ ' threshold=${fmt(v.threshold, 4)} => ${v.go ? "GO" : "NO-GO"}'
			+ ' (median across CLI --seed restarts)');

		var exitCode = 0;
		if (prereg != null && matrix.metrics.length > 0) {
			var pv = prereg.evaluate(v.median);
			Sys.println(PreregGate.formatLine(pv));
			if (pv.abort) exitCode = 1;
		}
		if (requireGo && !v.go) {
			Sys.println("REQUIRE-GO failed: seed-matrix median did not clear threshold");
			exitCode = 1;
		}

		if (exitCode == 0) Sys.println("SEED_RESTART_MATRIX_OK");
		else Sys.println("SEED_RESTART_MATRIX_NOGO");
		Sys.exit(exitCode);
	}

	static function parseSeeds(s:String):Array<Int> {
		var out:Array<Int> = [];
		for (part in s.split(",")) {
			var t = StringTools.trim(part);
			if (t.length == 0) continue;
			var n = Std.parseInt(t);
			if (n != null) out.push(n);
		}
		return out;
	}

	static function fmt(x:Float, n:Int):String {
		if (!Math.isFinite(x)) return "n/a";
		var m = Math.pow(10, n);
		return Std.string(Math.ffloor(x * m + 0.5) / m);
	}

	static function argStr(name:String, def:Null<String>):Null<String> {
		var a = Sys.args(); var i = 0;
		while (i < a.length - 1) { if (a[i] == name) return a[i + 1]; i++; }
		return def;
	}
	static function argInt(name:String, def:Int):Int {
		var v = argStr(name, null);
		return v == null ? def : Std.parseInt(v);
	}
	static function argFloat(name:String, def:Float):Float {
		var v = argStr(name, null);
		return v == null ? def : Std.parseFloat(v);
	}
	static function argFlag(name:String):Bool {
		for (a in Sys.args()) if (a == name) return true;
		return false;
	}
}
