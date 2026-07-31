package musescript.cli;

import musescript.harness.Bar;
import musescript.harness.OhlcvCsv;
import musescript.runtime.MuseRuntime;

/**
 * PanelRunner — headless multi-symbol (panel/portfolio) fitness bridge.
 *
 * The panel sibling of GeneRunner: reads a MuseScript portfolio strategy (file
 * or stdin), loads one CSV tape per symbol, calendar-aligns them via
 * `MuseRuntime.runPanel` (PanelFeed), backtests, and prints ONE line of JSON
 * metrics to stdout. Designed to be shelled out to from Python
 * (muse_fincog's PanelFitnessHost).
 *
 * On any failure it still prints valid JSON (`{"ok":false,"error":...}`) and
 * exits 0, so the caller always parses a result instead of catching a crash.
 *
 *   node build/js/panel-runner.js --source strat.ms \
 *     --tapes AAPL=data/real/aapl.csv,MSFT=data/real/msft.csv \
 *     --cost-bps 20 --tier js --seed 42
 *
 * Honesty defaults: `--fill-next-open` defaults TRUE (decide at close[t], fill
 * at open[t+1] — kills the same-bar close->close lookahead), and the repro
 * stamp is seeded from `--seed`. Panel supports tiers `js` and `interp` only;
 * `--tier wasm` is rejected by MuseRuntime with an honest error (still exit 0).
 */
class PanelRunner {
	static function argVal(name:String, def:String):String {
		var a = Sys.args();
		for (i in 0...a.length) if (a[i] == name && i + 1 < a.length) return a[i + 1];
		return def;
	}

	/** Default-true boolean flag: absent -> def; bare flag -> true;
	 * `--flag false` / `--flag 0` -> false. */
	static function argBool(name:String, def:Bool):Bool {
		var a = Sys.args();
		for (i in 0...a.length) {
			if (a[i] != name) continue;
			if (i + 1 < a.length) {
				var v = a[i + 1].toLowerCase();
				if (v == "false" || v == "0") return false;
				if (v == "true" || v == "1") return true;
			}
			return true; // bare flag
		}
		return def;
	}

	static function intArg(name:String, def:Int):Int {
		var v = Std.parseInt(argVal(name, Std.string(def)));
		return v != null ? v : def;
	}

	static function main() {
		try {
			run();
		} catch (e:Dynamic) {
			emit({ ok: false, error: Std.string(e) });
		}
	}

	static function run():Void {
		var sourcePath = argVal("--source", "");
		var tapesArg = argVal("--tapes", "");
		var tier = argVal("--tier", "js");
		var costBps = Std.parseFloat(argVal("--cost-bps", "0"));
		if (Math.isNaN(costBps)) costBps = 0;
		var fillNextOpen = argBool("--fill-next-open", true);
		var seed = intArg("--seed", 42);

		if (tapesArg == "") {
			emit({ ok: false, error: "PanelRunner: --tapes SYM=path[,SYM=path...] is required" });
			return;
		}

		var source = sourcePath != "" ? readFile(sourcePath) : readStdin();
		if (StringTools.trim(source) == "") {
			emit({ ok: false, error: "PanelRunner: empty strategy source (--source file or stdin)" });
			return;
		}

		// `MuseRuntime.toPanel` reads bySym with Reflect.fields, so this must be a
		// plain anonymous object keyed by symbol — NOT a haxe.ds.StringMap.
		var bySym:Dynamic = {};
		var symbols:Array<String> = [];
		for (spec in tapesArg.split(",")) {
			var s = StringTools.trim(spec);
			if (s == "") continue;
			var eq = s.indexOf("=");
			if (eq <= 0 || eq == s.length - 1) {
				emit({ ok: false, error: 'PanelRunner: bad --tapes entry "$s" (want SYM=path)' });
				return;
			}
			var sym = StringTools.trim(s.substr(0, eq));
			var path = StringTools.trim(s.substr(eq + 1));
			var bars:Array<Bar>;
			try {
				bars = OhlcvCsv.parse(readFile(path));
			} catch (e:Dynamic) {
				emit({ ok: false, error: 'PanelRunner: failed to load tape for $sym at $path: ' + Std.string(e) });
				return;
			}
			if (bars.length == 0) {
				emit({ ok: false, error: 'PanelRunner: tape for $sym at $path parsed to 0 bars' });
				return;
			}
			Reflect.setField(bySym, sym, bars);
			symbols.push(sym);
		}
		if (symbols.length == 0) {
			emit({ ok: false, error: "PanelRunner: --tapes parsed to no symbols" });
			return;
		}

		var res:Dynamic = MuseRuntime.runPanel(source, bySym, {
			tier: tier,
			costBps: costBps,
			fillNextOpen: fillNextOpen,
			initialCash: 100000,
			instrument: false,
			seed: seed
		});
		// Echo the honesty-relevant settings so the JSON line is self-describing.
		Reflect.setField(res, "costBps", costBps);
		Reflect.setField(res, "fillNextOpen", fillNextOpen);
		Reflect.setField(res, "seed", seed);
		emit(res);
	}

	static function emit(o:Dynamic):Void {
		Sys.println(haxe.Json.stringify(o));
	}

	static function readFile(path:String):String {
		return js.Syntax.code("require('fs').readFileSync({0}, 'utf8')", path);
	}

	static function readStdin():String {
		try {
			return js.Syntax.code("require('fs').readFileSync(0, 'utf8')");
		} catch (_:Dynamic) {
			return "";
		}
	}
}
