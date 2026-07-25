package musescript.evo;

/**
 * Deterministic MuseGene -> MuseScript expansion.
 *
 * Emits the MODERN typed surface (`strategy Name(...) { onBar { when cond: { ... } } }`),
 * NOT the legacy `{ @strategy("Name") @on(bar) { if (...) ...; } }` hscript-annotation dialect
 * this used to emit -- switched because (a) nobody hand-writes the annotation dialect anymore
 * (every real file under corpus/strategies/ already uses the modern surface) and (b) the
 * annotation dialect's braceless `if (cond) long(qty);` doesn't reverse-compile through
 * CorpusSeed.translateBool/translateStrategy at all (`guardedOrders` only recognizes `When`/the
 * general-`if` `EIf` shape with an `EBlock` then-branch, both modern-surface constructs) -- a real
 * gap surfaced by HumanLoopWindow's edit-source round trip, but really a pre-existing mismatch
 * between this file's OWN output and CorpusSeed's expectations any caller doing a Fitness.evaluate
 * -> Expand.expand -> CorpusSeed.translateSource round trip would have hit. `MuseParser.parse`
 * auto-dispatches to `StrategyParser` via `StrategyParser.looksLike` (checks for a leading
 * `strategy` token), so every EXISTING caller of `Expand.expand` (Fitness.evaluate, CorpusEvoRun's
 * champion printout, GeneRunner) needs zero changes -- same `new MuseParser().parse(...)` entry
 * point, it just now routes to the other front-end.
 */
class Expand {
	public static function expand(g:StrategyGenome):String {
		var paramList = g.params.length == 0 ? "" :
			"(" + [for (p in g.params) '${p.name} = ${num(p.defaultValue)}'].join(", ") + ")";
		var size = scalar(g.size, g.params);
		var lines = ['strategy ${g.name}$paramList {', "  onBar {"];
		// Guarded on `position()` so a STICKY entry condition (BCmp/BTrend-based, e.g. `rsi(...) <
		// 55` staying true for many consecutive bars -- unlike a transient crossover, which only
		// fires once) doesn't re-fire `long`/`short` every single bar it holds and pyramid an
		// unbounded position. `long`/`short` themselves stay generically additive at the LANGUAGE
		// level (a hand-written strategy that WANTS pyramiding can still call them directly,
		// unguarded) -- this guard is specific to genome-EXPANDED source, where `size` is meant as
		// a target exposure, not a per-bar increment. `<= 0`/`>= 0` (not `== 0`) deliberately still
		// allows a same-bar REVERSAL (short flips to long, long flips to short) to fire -- only
		// same-direction re-entry is blocked, matching executeLong/executeShort's own existing
		// "close the opposite side first" behavior.
		lines.push('    when (${bool(g.entryLong, g.params)}) && position() <= 0: { long($size) }');
		lines.push('    when (${bool(g.entryShort, g.params)}) && position() >= 0: { short($size) }');
		lines.push('    when (${bool(g.exitLong, g.params)}) || (${bool(g.exitShort, g.params)}): { flat() }');
		lines.push("  }");
		lines.push("}");
		return lines.join("\n");
	}

	static function num(x:Float):String {
		if (x == Std.int(x)) return Std.string(Std.int(x));
		return Std.string(x);
	}

	public static function series(n:SeriesNode):String {
		return switch (n) {
			case SPrice(f): '"' + f + '"';
			case SInd(name, field, window, src):
				if (src != null) '${name}(${series(src)}, $window)';
				else '${name}("$field", $window)';
		};
	}

	public static function scalar(n:ScalarNode, params:Array<EvoParam>):String {
		return switch (n) {
			case KConst(v): num(v);
			case KParam(i): params[i].name;
			case KSeries(s):
				switch (s) {
					case SPrice(f): f;
					case SInd(name, field, window, src):
						src != null ? '${name}(${series(src)}, $window)' : '${name}("$field", $window)';
				}
			case KLookback(s, k):
				switch (s) {
					case SPrice(f): '$f[$k]';
					default: '(${series(s)})[$k]';
				}
			case KFeature(name):
				name;
			case KArith(op, a, b):
				var as = scalar(a, params);
				var bs = scalar(b, params);
				if (op == "min" || op == "max") return '$op($as, $bs)';
				'($as $op $bs)';
			// Transparent: a hole is a mutation-eligibility marker only, invisible to the emitted
			// MuseScript -- see BoolNode.BHole's doc comment.
			case KHole(inner): scalar(inner, params);
		};
	}

	public static function bool(n:BoolNode, params:Array<EvoParam>):String {
		return switch (n) {
			case BCross(dir, a, b):
				var fn = dir == "over" ? "crossover" : "crossunder";
				'$fn(${series(a)}, ${series(b)})';
			case BCmp(op, a, b):
				'(${scalar(a, params)} $op ${scalar(b, params)})';
			case BTrend(dir, s, w):
				// dir is "over"/"under" (the SAME Palette.CROSS pool BCross's dir is drawn from
				// -- Variation.growBool literally does `rng.pick(Palette.CROSS)` for both), NOT
				// "up"/"down". This case used to check `dir == "up"`, which is never true for
				// any BTrend this codebase actually constructs (Variation.hx, CorpusSeed.hx) --
				// every BTrend genome, grown or reverse-compiled, silently rendered as "falling"
				// regardless of its real dir. Found via a corpus-evo walk-forward run reporting
				// suspiciously identical champion stats across unrelated genomes/tapes; traced
				// to this always-false comparison.
				var fn = dir == "over" ? "rising" : "falling";
				'$fn(${series(s)}, $w)';
			case BAnd(a, b): '(${bool(a, params)} && ${bool(b, params)})';
			case BOr(a, b): '(${bool(a, params)} || ${bool(b, params)})';
			case BNot(a): '(!${bool(a, params)})';
			case BHole(inner): bool(inner, params); // see scalar's KHole case
		};
	}
}
