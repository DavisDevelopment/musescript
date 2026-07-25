package musescript.evo;

import musescript.harness.HarnessContext;
import musescript.harness.Bar;
import musescript.harness.BarFeed;
import musescript.interp.MuseInterp;
import musescript.parse.MuseParser;
import musescript.compile.TemplateExpand;
import musescript.compile.ModuleExpand;
import musescript.compile.SeriesLowering;
import musescript.compile.GeneratorLower;
import musescript.compile.TailCallPass;
import musescript.compile.StaticInlinePass;
import musescript.compile.ConstFold;
import musescript.compile.CommonSubexprElim;
import musescript.builtins.TradeBuiltins;

/**
 * Advance ONE genome ONE bar at a time, returning the POSITION DELTA since the last call as a
 * `{side, qty}` decision -- the load-bearing primitive for Phase 2 of the MurmurationSim x
 * corpus-evo integration plan ("genome-in-the-loop": genomes as market agents whose orders
 * actually move a shared book, not price-takers replaying a frozen tape).
 *
 * Reuses the EXACT per-bar sequence `BacktestEngine.run`'s bulk loop already executes --
 * `beginBar -> observeBar -> execBar -> mark` -- confirmed identical to
 * `musescript.runtime.MuseDebugSession.stepBar()` (built for the IDE's bar-stepping debugger,
 * parity-tested against a full run). This class is a thinner, non-Dynamic, `StrategyGenome`-typed
 * sibling of that debugger session for this specific use, not a replacement for it.
 *
 * Semantics: a genome decides using the bar that JUST closed (same-close execution, like every
 * other MuseScript strategy), so `decide(bar)` should be called with the PREVIOUS tick's fully-
 * settled bar, never the current tick's -- the current tick's own high/low/close aren't known
 * until AFTER the auction this decision feeds into clears (see MurmurationRules.hx's `Evolved`
 * case). This is a one-tick decision lag, identical in spirit to `BacktestEngine.run`'s own
 * "causal mode" comment (execute bar t-1 signals at bar t open before exposing bar t's OHLCV).
 *
 * `decide`'s returned qty is a RAW position delta, not yet risk-capped for a competitive auction
 * -- `OrderSim.riskCappedQty`'s 25% cap already bounds how large a single call's delta can be
 * relative to this genome's OWN (private, decision-only) ledger, but the caller is responsible
 * for whatever further sizing/capital rules apply to the SHARED book (see MurmurationPopulation's
 * separate real cash/inventory ledger, updated via `settle()` from actual auction fills -- this
 * class never touches that ledger, only the genome's own private decision-making one).
 */
class GenomeStepper {
	var harness:HarnessContext;
	var interp:MuseInterp;
	var lastPosition:Float = 0;
	/** Once a `decide()` call throws, this instance is DONE for good -- every subsequent call
	 * returns a flat {side:0, qty:0} without re-invoking the interpreter. A single genome's
	 * runtime bug (or an interp/genome-expansion interop gap not yet root-caused -- see
	 * `decide`'s doc comment) must never be able to crash a shared multi-agent
	 * MurmurationSim run for every OTHER agent in it; a faulted genome just stops trading and
	 * scores on whatever wealth it had accumulated up to the fault, same as any other
	 * underperforming competitor. */
	public var faulted(default, null):Bool = false;
	public var faultReason(default, null):Null<String> = null;

	public function new(g:StrategyGenome) {
		harness = new HarnessContext();
		// No real bars array exists at construction time (they arrive one at a time via
		// `decide()`) -- an empty feed just matches MuseDebugSession's own "always assign
		// harness.feed before setupRun" convention.
		harness.feed = new BarFeed([]);
		var source = Expand.expand(g);
		var prog = new MuseParser().parse(source, "<evolved-agent>");
		// The FULL MuseCompiler.compileEx transform pipeline, in its exact order, minus the actual
		// backend dispatch (this class always executes via raw MuseInterp.execBar, stepped one bar
		// at a time, never JsBackend/WASM). Running the WHOLE pipeline -- not just the passes that
		// happened to matter for one test genome -- is deliberate: MuseDebugSession's own
		// (TemplateExpand+ModuleExpand only) pipeline is normally fed HAND-WRITTEN source, which
		// never needs SeriesLowering/GeneratorLower/TailCallPass/StaticInlinePass/ConstFold/
		// CommonSubexprElim to execute correctly -- but genome-EXPANDED source (Expand.hx) and
		// especially CORPUS-DERIVED genomes (reverse-compiled from real, sometimes structurally
		// complex strategies) are exactly the inputs those passes exist for. First found via
		// SeriesLowering specifically (quoted-string series args, e.g. `crossover("close", ...)`,
        // evaluate as the literal STRING "close" without it, silently never firing) and confirmed
		// a SECOND time when a real corpus genome crashed inside raw MuseInterp with a
		// ClassCastException (a stateful-builtin closure reference reaching `binop` as if it were a
		// plain value) that this same full pipeline resolves -- treated as one lesson, not two
		// separate patches: match compileEx exactly rather than re-deriving which subset "should"
		// be needed.
		prog = TemplateExpand.expand(prog);
		prog = ModuleExpand.expand(prog);
		prog = SeriesLowering.lower(prog);
		prog = GeneratorLower.lower(prog);
		prog = TailCallPass.transform(prog);
		prog = StaticInlinePass.transform(prog);
		prog = ConstFold.transform(prog);
		prog = CommonSubexprElim.transform(prog);
		// Matches Fitness.evaluate / MuseDebugSession's own setup sequence -- see
		// TradeBuiltins.resetCrossState's doc comment for why a fresh run needs this even though
		// CallsiteIds-based crossover/crossunder state (the common case) already lives on this
		// instance's OWN harness, not the legacy global slot-keyed fallback.
		TradeBuiltins.resetCrossState();
		interp = new MuseInterp(harness);
		interp.setupRun(prog);
	}

	/** Feed one already-CLOSED bar; returns this call's position delta as `{side, qty}` (side is
	 * 0 when unchanged -- flat call, or the strategy simply didn't act this bar, or this instance
	 * has already `faulted`). A caught exception permanently faults this instance -- see the
	 * `faulted`/`faultReason` doc comment; a KNOWN, still-open gap is at least one real
	 * corpus-derived genome hitting a `ClassCastException` deep in `MuseInterp.binop` (a
	 * stateful-builtin closure reaching a numeric context) that survives running the exact same
	 * transform pipeline `MuseCompiler.compileEx` runs -- root cause not yet isolated; this
	 * catch is the deliberate containment boundary until it is. */
	public function decide(bar:Bar):{side:Int, qty:Float} {
		if (faulted) return {side: 0, qty: 0};
		try {
			harness.orders.beginBar(bar.open, bar.index, bar.high, bar.low);
			harness.observeBar(bar);
			interp.execBar(bar);
			harness.orders.mark(bar.close);
		} catch (e:Dynamic) {
			faulted = true;
			faultReason = Std.string(e);
			return {side: 0, qty: 0};
		}
		var newPosition = harness.orders.position;
		var delta = newPosition - lastPosition;
		lastPosition = newPosition;
		if (delta == 0) return {side: 0, qty: 0};
		return {side: delta > 0 ? 1 : -1, qty: Math.abs(delta)};
	}

	/** This genome's own private-ledger position as of the last `decide()` call -- for callers
	 * that want to inspect current exposure without waiting for the next delta. */
	public function currentPosition():Float return lastPosition;

	/** This genome's own private-ledger trade count so far (`OrderSim.trades`) -- e.g. for a
	 * `tradesPerBar` behavioral descriptor, the same source a tape-based eval's `CachedEval.trades`
	 * comes from. */
	public function tradeCount():Int return harness.orders.trades;

	/** This genome's own private-ledger fills so far -- e.g. for `MapElites.describeFills`
	 * (behavioral niche descriptors), the same source a tape-based eval's fills come from, just
	 * from this genome's OWN decision-making ledger rather than a real auction settlement. */
	public function fills():Array<musescript.harness.Fill> return harness.orders.fills;
}
