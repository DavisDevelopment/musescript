package musescript.evo;

/**
 * Archipelago helpers for the Rivalry co-evo loop: deme sizing (~128/deme), per-deme
 * telemetry, and selection-fitness blending with a sparse rivalry channel.
 *
 * The actual island tournament / migration lives in `EvolutionEngine.stepDemes` (`--deme-size`).
 * This module does not touch NMA eval — deme split only changes who mates with whom.
 */
class Archipelago {
	/** Locked preference: target island size; D = ceil(pop / TARGET_DEME_SIZE). */
	public static inline var TARGET_DEME_SIZE = 128;

	/**
	 * Resolve island size from CLI knobs. All off → 0 (panmictic, bit-identical to today).
	 * Priority: explicit `--deme-size` > `--archipelago D` (derive size from pop/D) >
	 * `--rivalry` default TARGET_DEME_SIZE when pop is large enough for ≥2 demes.
	 */
	public static function resolveDemeSize(pop:Int, demeSize:Int, archipelagoD:Int, rivalryOn:Bool):Int {
		if (demeSize > 0) return demeSize;
		if (archipelagoD > 0) {
			if (pop < archipelagoD * 2) return 0;
			return Std.int(Math.ceil(pop / archipelagoD));
		}
		if (rivalryOn && pop >= TARGET_DEME_SIZE * 2) return TARGET_DEME_SIZE;
		return 0;
	}

	public static function demeCount(pop:Int, demeSize:Int):Int {
		if (demeSize <= 0 || pop < demeSize * 2) return 1;
		return Std.int(Math.ceil(pop / demeSize));
	}

	/** Per-deme best/mean for CompeteViz (contiguous index islands, same layout as stepDemes). */
	public static function demeStats(fitness:Array<Float>, demeSize:Int):Array<DemeStat> {
		var n = fitness.length;
		if (demeSize <= 0 || n == 0) {
			var best = Fitness.NEG_INF;
			var sum = 0.0;
			var valid = 0;
			for (f in fitness) {
				if (f == Fitness.NEG_INF) continue;
				valid++;
				sum += f;
				if (f > best) best = f;
			}
			return [{id: 0, n: n, best: best, mean: valid > 0 ? sum / valid : 0.0}];
		}
		var nDemes = demeCount(n, demeSize);
		var out:Array<DemeStat> = [];
		for (d in 0...nDemes) {
			var lo = d * demeSize;
			var hi = Std.int(Math.min(n, lo + demeSize));
			var best = Fitness.NEG_INF;
			var sum = 0.0;
			var valid = 0;
			for (i in lo...hi) {
				var f = fitness[i];
				if (f == Fitness.NEG_INF) continue;
				valid++;
				sum += f;
				if (f > best) best = f;
			}
			out.push({id: d, n: hi - lo, best: best, mean: valid > 0 ? sum / valid : 0.0});
		}
		return out;
	}

	/**
	 * Blend tape/NMA fitness with a carried rivalry channel for selection only.
	 * `rivalry[i] == NEG_INF` (or null channel) → leave tape score alone for that slot.
	 * Weight 0 → exact prior (same array reference when possible).
	 *
	 * Scale-safe: among slots with BOTH channels valid, z-normalize tape and rivalry, blend
	 * z-scores by `weight`, then rematerialize onto the tape mean/std. Raw linear mix of Sharpe
	 * and arena z was too weak — tape-only elites kept seats. Default `--rivalry-weight` under
	 * `--rivalry` is 0.40 so a ~2σ arena gap can overturn a ~1.3σ tape lead.
	 */
	public static function blendSelection(
		tape:Array<Float>,
		rivalry:Null<Array<Float>>,
		weight:Float
	):Array<Float> {
		if (rivalry == null || weight <= 0) return tape;
		if (weight > 1) weight = 1;
		var n = Std.int(Math.min(tape.length, rivalry.length));
		var idxs:Array<Int> = [];
		for (i in 0...n) {
			if (tape[i] == Fitness.NEG_INF || rivalry[i] == Fitness.NEG_INF) continue;
			idxs.push(i);
		}
		if (idxs.length == 0) return tape;
		var meanT = 0.0, meanR = 0.0;
		for (i in idxs) {
			meanT += tape[i];
			meanR += rivalry[i];
		}
		meanT /= idxs.length;
		meanR /= idxs.length;
		var varT = 0.0, varR = 0.0;
		for (i in idxs) {
			var dt = tape[i] - meanT;
			var dr = rivalry[i] - meanR;
			varT += dt * dt;
			varR += dr * dr;
		}
		varT /= idxs.length;
		varR /= idxs.length;
		var stdT = Math.sqrt(varT);
		var stdR = Math.sqrt(varR);
		var out = tape.copy();
		for (i in idxs) {
			var zt = stdT > 1e-9 ? (tape[i] - meanT) / stdT : 0.0;
			var zr = stdR > 1e-9 ? (rivalry[i] - meanR) / stdR : 0.0;
			var zb = (1 - weight) * zt + weight * zr;
			out[i] = meanT + zb * (stdT > 1e-9 ? stdT : 1.0);
		}
		return out;
	}
}

@:structInit
class DemeStat {
	public var id:Int;
	public var n:Int;
	public var best:Float;
	public var mean:Float;
}
