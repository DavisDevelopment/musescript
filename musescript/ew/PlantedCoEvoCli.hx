package musescript.ew;

import musescript.evo.rigor.PlantedCoEvo;
import musescript.evo.rigor.OosVerdict;
import musescript.evo.rigor.PreregGate;
import musescript.harness.OhlcvCsv;
import musescript.harness.TapeLinter;

/**
 * Bounded multi-gen planted-edge co-evo on a real tape → hardened OOS GO/NO-GO.
 *
 * Prefer long available tapes (`corpus/tapes/spy_*.csv` or `data/real/tsla.csv`).
 *
 * ```
 * haxe build-planted-coevo.hxml
 * node build/js/planted-coevo.js --tape corpus/tapes/spy_oos_2022_2026.csv --gens 4 --pop 8 --seed 42
 * ```
 */
class PlantedCoEvoCli {
	static function main() {
		var tapePath = argStr("--tape", "corpus/tapes/spy_oos_2022_2026.csv");
		var seed = argInt("--seed", 42);
		var pop = argInt("--pop", 8);
		var gens = argInt("--gens", 4);
		var minTrades = argInt("--min-trades", 20);
		var nTrials = argInt("--n-trials", 5);
		var maxBars = argInt("--max-bars", 1200);
		var preregOn = argFlag("--prereg");
		var preregThreshold = argFloat("--prereg-threshold", 0.0);
		var requireGo = argFlag("--require-go");

		Sys.println("=== PlantedCoEvo (multi-gen planted edge → hardened OOS) ===");
		Sys.println('tape=$tapePath seed=$seed pop=$pop gens=$gens');

		if (!OhlcvCsv.exists(tapePath)) {
			Sys.println('BLOCKER: tape not found at $tapePath');
			Sys.exit(2);
		}
		var bars = OhlcvCsv.load(tapePath);
		if (maxBars > 0 && bars.length > maxBars)
			bars = bars.slice(bars.length - maxBars, bars.length);
		Sys.println('bars=${bars.length}');
		var lint = TapeLinter.lint(bars, {allowZeroVolume: true});
		Sys.println(TapeLinter.formatReport(lint, 8));
		if (!TapeLinter.isClean(bars, {allowZeroVolume: true})) {
			Sys.println("VERDICT: NO-GO — tape failed integrity lint");
			Sys.exit(1);
		}

		var prereg = preregOn ? PreregGate.seal(preregThreshold, 5) : null;
		if (prereg != null) Sys.println("prereg SEALED: " + prereg.describe());

		var r = PlantedCoEvo.runOnce(bars, {
			seed: seed, pop: pop, gens: gens, minTrades: minTrades, nTrials: nTrials
		});

		var oos:Dynamic = r.oos;
		var nullOos:Dynamic = r.nullOos;
		Sys.println(OosVerdict.formatLine(oos,
			'planted champion OOS trades=${r.championTrades} sharpe=${fmt(r.championOosSharpe, 4)} bh=${fmt(r.bhSharpe, 4)}'));
		Sys.println(OosVerdict.formatLine(nullOos, "null-host control on same genome (must stay NO-GO)"));
		Sys.println('[rigor champion-oos] metric=${fmt(r.championOosSharpe, 4)} seed=$seed gens=${r.gens}');

		var exitCode = 0;
		if (prereg != null) {
			var pv = prereg.evaluate(r.championOosSharpe);
			Sys.println(PreregGate.formatLine(pv));
			if (pv.abort) exitCode = 1;
		}
		if (requireGo && !r.go) {
			Sys.println("REQUIRE-GO failed: planted champion OOS is NO-GO");
			exitCode = 1;
		}
		// Null control must remain NO-GO — instrument break if it GOs.
		if (Reflect.field(nullOos, "go") == true) {
			Sys.println("CONTROL FAILED: null-host cleared hardened OOS (J1 broken)");
			exitCode = 1;
		}

		if (r.go) Sys.println("PLANTED_COEVO_VERDICT: GO");
		else Sys.println("PLANTED_COEVO_VERDICT: NO-GO");

		if (exitCode == 0) Sys.println("PLANTED_COEVO_OK");
		else Sys.println("PLANTED_COEVO_FAIL");
		Sys.exit(exitCode);
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
