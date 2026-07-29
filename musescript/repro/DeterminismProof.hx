package musescript.repro;

import musescript.evo.FillHash;
import musescript.ew.mcmc.DetParityDump;
import musescript.runtime.MuseRuntime;

/**
 * Productized determinism proof surface (Initiative 4.1).
 *
 * Wraps the Bucket-D4 `DetParityDump` foundation and adds a callable strategy
 * proof: same source + bars + seed → bit-identical equity across engines
 * (interp / js / wasm as available). Does not mutate DetParityDump golden output.
 *
 * JS / Studio: `MuseRuntime.proveDeterminism(source, bars, opts)`.
 */
class DeterminismProof {
	public static inline var SCHEMA = 1;

	/** 16-hex digest of the DetParityDump foundation transcript. */
	public static function foundationDigest():String {
		return haxe.crypto.Sha1.encode(DetParityDump.render()).substr(0, 16);
	}

	public static inline function equityDigest(equity:Null<Array<Float>>):String {
		return EquityDigest.of(equity);
	}

	/**
	 * Prove a strategy run is bit-identical across engines (and within the first
	 * engine via a double-exec). Returns a plain Dynamic for the JS boundary:
	 * `{ ok, identical, badge, seed, equityDigest, fillDigest, foundationDigest,
	 *    engines:[{engine,equityDigest,fillDigest,trades,finalEquity}], reason }`.
	 *
	 * `opts.engines` — array of tier names; default `["interp","js"]`.
	 * `opts.seed` — stamped into the proof (default 42); forwarded to each run.
	 */
	public static function prove(source:String, ?bars:Array<Dynamic>, ?opts:Dynamic):Dynamic {
		var seed = optInt(opts, "seed", ReproStamp.DEFAULT_SEED);
		var engines = optEngines(opts);
		if (engines.length == 0) engines = ["interp", "js"];

		var stamp = ReproStamp.make({
			seed: seed,
			bootSeed: optInt(opts, "bootSeed", seed),
			profile: optStr(opts, "profile", "studio"),
			backend: engines[0]
		});

		var engineRows:Array<Dynamic> = [];
		var firstEquity:Null<Array<Float>> = null;
		var firstFillDigest:String = null;
		var identical = true;
		var failReason:String = null;

		for (eng in engines) {
			var runOpts = mergeTier(opts, eng, seed);
			var r:Dynamic = MuseRuntime.run(source, bars, runOpts);
			if (Reflect.field(r, "ok") != true) {
				return failProof(stamp, 'engine=$eng: ${Std.string(Reflect.field(r, "error"))}');
			}
			var eq:Null<Array<Float>> = Reflect.field(r, "equity");
			var fills:Dynamic = Reflect.field(r, "fills");
			var dig = EquityDigest.of(eq);
			var fd = FillHash.of(fills);
			if (firstEquity == null) {
				firstEquity = eq;
				firstFillDigest = fd;
			} else if (!EquityDigest.identical(firstEquity, eq)) {
				identical = false;
				failReason = 'equity diverged: ${engines[0]} vs $eng';
			}
			engineRows.push({
				engine: eng,
				equityDigest: dig,
				fillDigest: fd,
				trades: Reflect.field(r, "trades"),
				finalEquity: Reflect.field(r, "finalEquity")
			});
		}

		// Within-engine double-exec on the lead tier (CorpusEvoRun champion pattern).
		var lead = engines[0];
		var a:Dynamic = MuseRuntime.run(source, bars, mergeTier(opts, lead, seed));
		var b:Dynamic = MuseRuntime.run(source, bars, mergeTier(opts, lead, seed));
		if (Reflect.field(a, "ok") != true || Reflect.field(b, "ok") != true) {
			return failProof(stamp, 'double-exec failed on $lead');
		}
		var eqA:Null<Array<Float>> = Reflect.field(a, "equity");
		var eqB:Null<Array<Float>> = Reflect.field(b, "equity");
		if (!EquityDigest.identical(eqA, eqB)) {
			identical = false;
			failReason = 'non-deterministic within engine=$lead';
		}

		var eqDigest = EquityDigest.of(firstEquity);
		return {
			ok: true,
			identical: identical,
			badge: identical ? "BIT_IDENTICAL" : "DIVERGED",
			schemaVersion: SCHEMA,
			seed: stamp.seed,
			bootSeed: stamp.bootSeed,
			profile: stamp.profile,
			equityDigest: eqDigest,
			fillDigest: firstFillDigest,
			foundationDigest: foundationDigest(),
			engines: engineRows,
			repro: stamp.toJson(),
			reason: identical
				? "equity curve bit-identical across engines (and within lead engine)"
				: (failReason != null ? failReason : "equity curves diverged")
		};
	}

	static function failProof(stamp:ReproStamp, reason:String):Dynamic {
		return {
			ok: false,
			identical: false,
			badge: "ERROR",
			schemaVersion: SCHEMA,
			seed: stamp.seed,
			bootSeed: stamp.bootSeed,
			profile: stamp.profile,
			equityDigest: null,
			fillDigest: null,
			foundationDigest: foundationDigest(),
			engines: [],
			repro: stamp.toJson(),
			reason: reason,
			error: reason
		};
	}

	static function mergeTier(opts:Dynamic, tier:String, seed:Int):Dynamic {
		var out:Dynamic = {};
		if (opts != null) {
			for (k in Reflect.fields(opts)) {
				if (k == "engines" || k == "tier") continue;
				Reflect.setField(out, k, Reflect.field(opts, k));
			}
		}
		Reflect.setField(out, "tier", tier);
		Reflect.setField(out, "seed", seed);
		Reflect.setField(out, "instrument", true);
		Reflect.setField(out, "skipTruthReport", true);
		return out;
	}

	static function optEngines(opts:Dynamic):Array<String> {
		if (opts == null || !Reflect.hasField(opts, "engines")) return [];
		var v:Dynamic = Reflect.field(opts, "engines");
		if (v == null || !Std.isOfType(v, Array)) return [];
		var arr:Array<Dynamic> = cast v;
		return [for (x in arr) Std.string(x)];
	}

	static function optInt(opts:Dynamic, key:String, def:Int):Int {
		if (opts == null || !Reflect.hasField(opts, key)) return def;
		var v:Dynamic = Reflect.field(opts, key);
		if (v == null) return def;
		return Std.isOfType(v, Int) ? cast v : Std.int((v : Float));
	}

	static function optStr(opts:Dynamic, key:String, def:String):String {
		if (opts == null || !Reflect.hasField(opts, key)) return def;
		var v = Reflect.field(opts, key);
		return v == null ? def : Std.string(v);
	}
}
