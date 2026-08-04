package musescript.cli;

import musescript.harness.PanelLoader;
import musescript.runtime.MuseRuntime;

/**
 * PanelRunner — headless multi-symbol (panel/portfolio) fitness bridge.
 *
 * The panel sibling of GeneRunner: reads a MuseScript portfolio strategy (file
 * or stdin), loads offline panel data via `PanelLoader`, calendar-aligns them
 * via `MuseRuntime.runPanel` (PanelFeed), backtests, and prints ONE line of JSON
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
 *   node build/js/panel-runner.js --source strat.ms --panel data/fund_panel.json
 *
 * Honesty defaults: `--fill-next-open` defaults TRUE (decide at close[t], fill
 * at open[t+1] — kills the same-bar close->close lookahead), and the repro
 * stamp is seeded from `--seed`. Panel supports tiers `js` and `interp` only;
 * `--tier wasm` is rejected by MuseRuntime with an honest error (still exit 0).
 *
 * Prefer GeneRunner `--panel` / `--tapes` for a unified CLI; this entry remains
 * for existing PanelFitnessHost callers.
 *
 * Ingest: `--ingest` with `--fs-root` / `--fixture-dir` / `--http` / `--grants`
 * (same as GeneRunner) — no `--panel`/`--tapes` required for that path.
 */
class PanelRunner {
	static function argVal(name:String, def:String):String {
		var a = Sys.args();
		for (i in 0...a.length) if (a[i] == name && i + 1 < a.length) return a[i + 1];
		return def;
	}

	static function argFlag(name:String):Bool {
		for (a in Sys.args()) if (a == name) return true;
		return false;
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
		var panelPath = argVal("--panel", "");
		var tier = argVal("--tier", "js");
		var costBps = Std.parseFloat(argVal("--cost-bps", "0"));
		if (Math.isNaN(costBps)) costBps = 0;
		var fillNextOpen = argBool("--fill-next-open", true);
		var seed = intArg("--seed", 42);
		var ingestMode = argFlag("--ingest");
		var httpMode = argVal("--http", "");
		var fsRoot = argVal("--fs-root", "");
		var fixtureDir = argVal("--fixture-dir", "");
		var allowHosts = argVal("--allow-hosts", "");
		var grantsPath = argVal("--grants", "");

		var source = sourcePath != "" ? readFile(sourcePath) : readStdin();
		if (StringTools.trim(source) == "") {
			emit({ ok: false, error: "PanelRunner: empty strategy source (--source file or stdin)" });
			return;
		}

		if (ingestMode) {
			emit(runIngestCli(source, grantsPath, fsRoot, fixtureDir, allowHosts, httpMode));
			return;
		}

		if (tapesArg == "" && panelPath == "") {
			emit({ ok: false, error: "PanelRunner: --tapes SYM=path[,SYM=path...] or --panel <json|csv|dir> is required" });
			return;
		}

		var bySymMap = tapesArg != ""
			? PanelLoader.fromTapesSpecMap(tapesArg)
			: PanelLoader.loadMap(panelPath);
		var bySym:Dynamic = PanelLoader.toBySymDyn(bySymMap);
		var symbols:Array<String> = [for (s in bySymMap.keys()) s];
		symbols.sort(Reflect.compare);

		var res:Dynamic = MuseRuntime.runPanel(source, bySym, {
			tier: tier,
			costBps: costBps,
			fillNextOpen: fillNextOpen,
			initialCash: 100000,
			instrument: false,
			seed: seed,
			fitness: true
		});
		// Echo the honesty-relevant settings so the JSON line is self-describing.
		Reflect.setField(res, "costBps", costBps);
		Reflect.setField(res, "fillNextOpen", fillNextOpen);
		Reflect.setField(res, "seed", seed);
		Reflect.setField(res, "panelSymbols", symbols);
		emit(res);
	}

	static function runIngestCli(
		source:String, grantsPath:String, fsRoot:String, fixtureDir:String,
		allowHosts:String, httpMode:String
	):Dynamic {
		var grantOpts:Dynamic = {};
		if (grantsPath != "") {
			try {
				Reflect.setField(grantOpts, "grants", musescript.io.CliIoGrants.parseJson(readFile(grantsPath)));
			} catch (e:Dynamic) {
				return { ok: false, error: "PanelRunner --grants: " + Std.string(e) };
			}
		}
		if (fsRoot != "") {
			#if (sys || nodejs)
			Reflect.setField(grantOpts, "fsRoot", sys.FileSystem.absolutePath(fsRoot));
			#else
			Reflect.setField(grantOpts, "fsRoot", fsRoot);
			#end
		}
		if (fixtureDir != "") {
			#if (sys || nodejs)
			Reflect.setField(grantOpts, "fixtureDir", sys.FileSystem.absolutePath(fixtureDir));
			#else
			Reflect.setField(grantOpts, "fixtureDir", fixtureDir);
			#end
		}
		if (allowHosts != "") Reflect.setField(grantOpts, "allowHosts", allowHosts);
		if (httpMode != "") Reflect.setField(grantOpts, "http", httpMode);
		var grants = musescript.io.CliIoGrants.fromOpts(grantOpts);
		if (grants == null)
			return {
				ok: false,
				error: "PanelRunner --ingest requires --grants JSON and/or --fs-root / --fixture-dir"
			};
		var opts:Dynamic = {
			grants: grants,
			kind: "ingest",
			isBacktest: false,
			fitness: false
		};
		if (httpMode != "") Reflect.setField(opts, "http", httpMode);
		return MuseRuntime.runIngest(source, opts);
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
