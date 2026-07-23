package musescript.evo.graal;

import musescript.evo.Canonical;
import musescript.evo.StrategyGenome;
import musescript.harness.Bar;

/** One genome's raw backtest outcome on a fixed tape -- the pre-scoring facts (trades/sharpe/
 * equity), NOT a fitness. Parsimony, min-trade filtering, and MAP-Elites descriptors are all
 * derived from THIS plus the genome at the point of use, so the memo never has to be invalidated
 * when a run changes its parsimony lambda or descriptor binning: the cached thing is "what the
 * strategy did on these bars", which is immutable for a given (structural key, tape). */
typedef CachedEval = {
	var trades:Int;
	var sharpe:Float;
	var finalEquity:Float;
	/** Behavioral-descriptor inputs for MAP-Elites (see MapElites.hx) -- derived once from the
	 * backtest's fills at the point of a FRESH eval and persisted alongside the fitness numbers so
	 * a warm-started genome (loaded from disk, never re-run this session) still has a cell to
	 * offer itself into. Optional so an OLDER on-disk cache file (pre-dating this field) still
	 * loads: `load()` defaults both to the "unknown behavior" neutral values (0 hold, 0.5 mixed
	 * bias) rather than failing the whole line, matching this module's existing tolerant-parse
	 * convention (a malformed/short line is skipped, not fatal).
	 */
	var ?avgHold:Float;
	var ?longFrac:Float;
}

/**
 * Structural-key -> raw-eval memo, the single source of truth for "have we already run this exact
 * program on this exact tape?" Both backends (native WASM workers and the JS/interp fallback) and
 * every consumer (per-generation scoring, successive-halving triage, MAP-Elites archiving) read
 * and write it, so a genome that recurs -- which the corpus-evo runs demonstrably do CONSTANTLY,
 * whole populations collapsing to clones of one champion by gen 3 -- is backtested exactly once
 * per run instead of once per generation. Elitism alone guarantees the champion re-appears in
 * every subsequent generation; without this memo each of those re-appearances paid a full
 * 5000-bar backtest for a byte-identical answer.
 *
 * Keyed on `Canonical.structuralKey` (same 16-char structural hash the module cache already uses),
 * so two genomes that render to the same program share a cache slot even if they arrived via
 * different lineages. The memo is scoped to a TAPE SIGNATURE by the caller (one file per tape), so
 * IS and OOS evaluations -- genuinely different backtests -- never collide.
 *
 * Optional disk persistence makes the memo survive across RUNS: a re-run on the same tape
 * warm-starts from every genome the last run already evaluated, which is exactly the common
 * inner-loop case while tuning `--parsimony-*` / `--pop` / `--gens` (same seeds, same tape, only
 * the selection knobs change). Format is append-only TSV (`key\ttrades\tsharpe\tequity`), flushed
 * on every put so a killed run still banks everything it computed up to the kill.
 */
class EvoCache {
	var mem:Map<String, CachedEval> = new Map();
	var path:Null<String>;
	var out:Null<sys.io.FileOutput>;
	public var hits(default, null):Int = 0;
	public var misses(default, null):Int = 0;

	public function new(?path:String) {
		this.path = path;
		if (path != null) {
			if (sys.FileSystem.exists(path)) load(path);
			// Reopen in append mode AFTER loading so we don't truncate the file we just read.
			out = sys.io.File.append(path, false);
		}
	}

	public inline function keyFor(g:StrategyGenome):String
		return Canonical.structuralKey(g);

	/** Returns the cached eval or null; bumps hit/miss counters for the run's cache-efficiency line. */
	public function get(key:String):Null<CachedEval> {
		var v = mem.get(key);
		if (v != null) hits++ else misses++;
		return v;
	}

	public inline function has(key:String):Bool
		return mem.exists(key);

	/** First write for a key wins and is persisted; repeats are ignored (same key on the same tape
	 * is deterministic, so a second write can only be identical -- see CorpusEvoRun's champion
	 * determinism check, which asserts exactly this). */
	public function put(key:String, e:CachedEval):Void {
		if (mem.exists(key)) return;
		mem.set(key, e);
		if (out != null) {
			var avgHold = e.avgHold != null ? e.avgHold : 0.0;
			var longFrac = e.longFrac != null ? e.longFrac : 0.5;
			out.writeString('$key\t${e.trades}\t${e.sharpe}\t${e.finalEquity}\t$avgHold\t$longFrac\n');
			out.flush();
		}
	}

	public function size():Int {
		var n = 0;
		for (_ in mem.keys()) n++;
		return n;
	}

	public function close():Void {
		if (out != null) { out.close(); out = null; }
	}

	function load(p:String):Void {
		var content = sys.io.File.getContent(p);
		for (line in content.split("\n")) {
			if (line.length == 0) continue;
			var parts = line.split("\t");
			if (parts.length < 4) continue;
			var trades = Std.parseInt(parts[1]);
			var sharpe = Std.parseFloat(parts[2]);
			var equity = Std.parseFloat(parts[3]);
			if (trades == null || Math.isNaN(sharpe)) continue;
			// avgHold/longFrac columns are OPTIONAL (added after this cache format's first
			// version) -- an older on-disk file simply won't have them, so this genome comes back
			// with the "unknown behavior" neutral defaults until it's freshly re-evaluated.
			var avgHold = parts.length > 4 ? Std.parseFloat(parts[4]) : 0.0;
			var longFrac = parts.length > 5 ? Std.parseFloat(parts[5]) : 0.5;
			if (Math.isNaN(avgHold)) avgHold = 0.0;
			if (Math.isNaN(longFrac)) longFrac = 0.5;
			mem.set(parts[0], {trades: trades, sharpe: sharpe, finalEquity: equity, avgHold: avgHold, longFrac: longFrac});
		}
	}

	/** A cheap, order-sensitive signature of a tape so the on-disk memo is scoped to the exact bar
	 * sequence it was computed on -- length plus a rolling checksum of closes. Two different tapes
	 * (or the same symbol re-extracted with different adjustment) get different files; the same
	 * tape re-run gets the same file and warm-starts. Not cryptographic -- just needs to change
	 * when the bars change, which a summed close-weighted-by-index does. */
	public static function tapeSignature(bars:Array<Bar>):String {
		var acc = 1469598103.0; // arbitrary nonzero seed
		for (i in 0...bars.length) {
			var c = bars[i].close;
			acc = (acc * 1.0000001 + c * (i + 1)) % 2147483647.0;
		}
		var h = Std.int(Math.abs(acc));
		return '${bars.length}_$h';
	}
}
