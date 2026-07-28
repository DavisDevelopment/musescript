package musescript.evo;

import musescript.ast.Decl;
import musescript.parse.MuseParser;
import musescript.compile.MuseCompiler;
import musescript.harness.HarnessContext;
import musescript.harness.BarFeed;
import musescript.harness.Bar;
import musescript.interp.MuseInterp;
import musescript.builtins.TradeBuiltins;
import musescript.BarStrategyFn;

/**
 * Typed fitness evaluation for genomes.
 * Prefer WASM when available; fall back to interp while keeping backend label honest.
 *
 * When `preferNma` is true (CorpusEvoRun `--nma`), `evaluate` tries the columnar NMA path first
 * and falls back to Expand→compile→run on `KFeature` / NMA errors — see `muse_nse_spec.md` §8 P1c.
 *
 * «εὑρήκαμεν, συγκάθομεν· Βάκχος ἡγεῖται.»
 */
class Fitness {
	/**
	 * Optional host-backed projection provider. When set, `evaluateCompiled` decorates bars with
	 * `PSHost` aux columns before running Expand→compile so trading logic can read `SProj` fields.
	 * Null (default) ⇒ prior behaviour; genomes without `PSHost` are unaffected either way.
	 */
	public static var projectionProvider:Null<ProjectionProvider> = null;

	/**
	 * Compiled-program cache keyed on `(structural key, target, strict)` -- `Expand.expand(g)`
	 * is a pure function of the genome, and structurally-identical genomes (same
	 * `Canonical.structuralKey`) always produce byte-identical source, so the ENTIRE
	 * parse+TemplateExpand+ModuleExpand+...+CallsiteIds pipeline inside `MuseCompiler.compileEx`
	 * is redundant work on a repeat. This matters enormously for the evo package specifically:
	 * `Variation.attributedSubtreeCrossover`/`attributedPointMutate` call `Fitness.evaluate` as an
	 * ablation ORACLE hundreds of times per generation (baseline + per-site ablations + donor
	 * candidates), on the SAME handful of recurring parent/ablated shapes -- re-parsing and
	 * re-compiling every one of those calls was measured as the dominant cost of a whole
	 * corpus-evo generation (see PLAN_EVO_SPEED.md), dwarfing the actual WASM-accelerated fitness
	 * pass. Only the compiled `fn` + its `decls` (still needed per-call for
	 * `registerDeclPublic` -- see below) are cached; a fresh `HarnessContext`/`MuseInterp`/
	 * `BarFeed`/cross-state reset still happens on EVERY call, so this is a pure compile-cache,
	 * not a memoized RESULT (a genome run on a different tape or cost still gets a correct fresh
	 * execution through the same cached `fn`).
	 *
	 * «Βρόμιε, λῦσον μελάθρων· θύρσος πατάσσει.»
	 */
	static var fnCache:Map<String, {fn:BarStrategyFn, decls:Array<Decl>, backend:String}> = new Map();
	static inline var FN_CACHE_MAX = 4096;

	/**
	 * Thread contract (JIT guide §27) for the process-global caches on this class. Every one of
	 * them is reachable from a `CorpusEvoRun` fallback worker, and `haxe.ds.StringMap` corrupts
	 * under a concurrent resize, so each map's get/set pairs run inside its own lock. Separate
	 * locks rather than one because nothing here ever holds two — keep it that way.
	 *
	 * `fnCache` stores compiled programs, which are immutable once built and re-entrant across
	 * calls (a fresh `HarnessContext` per evaluation is what makes that true), so guarding the map
	 * is enough. The same is NOT true of `nmaWorking`, whose packs are live mutable trees — see
	 * its own note below.
	 */
	static final fnCacheLock = new EvoLock();
	static final workingLock = new EvoLock();
	static final popMemoStatsLock = new EvoLock();

	/**
	 * P1c strangler switch: when true, `evaluate` tries `NmaFitness` first (columnar, no parse/
	 * compile). Off by default — zero behavior change for every existing caller. CorpusEvoRun
	 * sets this from `--nma`. Champion determinism still double-executes through this same entry
	 * (real OrderSim twice; NMA column cache may warm between calls, which is compile-cache-
	 * equivalent reuse, not CachedEval replay).
	 *
	 * «Διόνυσος ἐλθέ· ναρθηκοφόροι σε δέχονται.»
	 */
	public static var preferNma:Bool = false;

	/**
	 * When true with `preferNma`, every successful NMA eval is cross-checked against Expand→compile
	 * (`--nma-verify`). Mismatch throws. Off by default (double cost).
	 */
	public static var nmaVerify:Bool = false;

	/**
	 * Generation-scoped content-addressed column memo for NMA (`--nma` / preferNma). Cleared each
	 * generation by CorpusEvoRun; null disables pop-memo (per-node + SInd tape cache still apply).
	 */
	public static var nmaPopMemo:Null<musescript.evo.nma.NmaColumnCache> = null;
	public static var nmaPopMemoHits:Int = 0;

	// Per-generation backend telemetry (reset in beginNmaPopMemo): how many evaluations the
	// columnar NMA path actually served vs fell through to Expand→parse→compile, and how many
	// fresh compiles that fallback cost. The strangler's coverage is a first-class perf metric —
	// a blocked genome pays ~ms of parse+compile, a columnar one pays ~µs of column reuse.
	public static var nmaOkCount:Int = 0;
	public static var nmaFallCount:Int = 0;
	public static var fnCompileCount:Int = 0;
	public static var nmaErrorCount:Int = 0;
	public static var lastNmaError:Null<String> = null;
	/** Falls whose backend was `nma-unsupported` (KFeature / nested SInd) — not a thrown error. */
	public static var nmaUnsupportedCount:Int = 0;

	/**
	 * Tape + OrderSim knobs closed over by CorpusEvoRun's attribution oracle. When set together
	 * with `preferNma`, `Variation`'s attributed mutate/crossover batch ablations through
	 * `NmaAttr` (dirty-spine) instead of N× full `evalFn` compile/column cold starts.
	 *
	 * «Ἴακχ᾽ ὦ Ἴακχε νυκτιφάης λαμπάδηφόρε.»
	 */
	public static var nmaTape:Null<Array<Bar>> = null;
	public static var nmaCostBps:Float = 0;
	public static var nmaInitialCash:Float = 100000;
	public static var nmaEquityFloor:Float = 0;

	/**
	 * Probability that `Variation.attributedPointMutate` takes the semantic-RDO path instead of
	 * ablation targeting when `--nma` + tape are armed (`--semantic-rdo-prob`). Default 0 = off.
	 *
	 * «Μαινάς ᾄδει· ῥυθμὸς ἄγει χορόν.»
	 */
	public static var semanticRdoProb:Float = 0;

	/**
	 * When true, `NmaAttr.boolSiteDeltas` skips ablation evals for well-credited sites (UCB bandit)
	 * and reuses `NmaCreditBank.mean` as the Δ (`--attr-bandit`). Default false = measure all sites.
	 *
	 * «φείδου πόνου· καιρὸς δαπανᾷ.»
	 */
	public static var attrBandit:Bool = false;

	/**
	 * When true, `NmaAttr.boolSiteDeltas` / attributed cut selection use bank credit alone
	 * (zero extra ablation oracle calls) once enough sites are warm (`--credit-cuts`). Spec §6b.
	 * Falls back to measuring ablations when the bank is too cold. Default false.
	 *
	 * «τέμνε κατὰ μοῖραν· τιμὴ ὁδηγεῖ.»
	 */
	public static var creditCuts:Bool = false;

	/**
	 * Under `creditCuts`, cap how many still-cold sites get a live column-swap ablation per
	 * `boolSiteDeltas` call (`--attr-max-cold`). Coldest-by-observations win the budget so the
	 * bank still fills; the rest keep their bank mean (0 if unseen). 0 = uncapped (old behavior).
	 * Default 2 — `step.xo` measured ~82% of step CPU with uncapped cold fills at pop=1000.
	 */
	public static var attrMaxCold:Int = 2;

	/**
	 * Under `creditCuts`, once the bank has at least this many deposits, site ranking skips
	 * further column-swap sessions and uses bank means only (`--attr-bank-fill`). 0 disables
	 * (default) — enabling too early let expensive genomes dominate scoreMs on the smoke tape.
	 */
	public static var attrBankFill:Int = 0;

	/**
	 * Control arm for the column-swap A/B: restore the old shortcut where a nested pool worker
	 * ranks sites and donors from `NmaCreditBank` means alone rather than measuring cold shapes.
	 *
	 * Kept only so the two attribution regimes can be compared in one binary. It is not a
	 * performance option in any honest sense: `means` returns 0.0 for a key it has never seen,
	 * and at ~990 distinct genomes per generation most keys are unseen, so this ranks the
	 * majority of sites by a constant. Off by default.
	 *
	 * «τὸ κενὸν ζυγόν· οὐδὲν ἵστησιν.»
	 */
	public static var attrBankOnly:Bool = false;

	/**
	 * When true (`--nma-dirty-spine`), `Fitness.evaluate` reuses gen-scoped live `NmaGenome`
	 * working copies (`nmaWorking`) after Variation bool splices so sibling memos survive.
	 * Requires `preferNma`. Off = cold `fromEnum` every evaluate (today's strangler).
	 *
	 * «δεσποίνας δὲ ὑπὸ κόλπον ἔδυν χθονίας βασιλείας.»
	 */
	public static var nmaDirtySpine:Bool = false;

	/**
	 * Gen-scoped live NMA trees keyed by `Canonical.structuralKey`. Null when dirty-spine off.
	 * Cleared each generation with pop-memo.
	 */
	public static var nmaWorking:Null<Map<String, musescript.evo.nma.NmaWorkingPack>> = null;
	public static var nmaWorkingHits:Int = 0;
	public static var nmaWorkingPuts:Int = 0;

	/**
	 * Thread contract (JIT guide §21, and the case §27's table does NOT cover): the packs in
	 * `nmaWorking` are live **mutable** NMA trees, and `NmaDirtySpine.spliceAndRegister` shares
	 * sibling node identity — plus the whole `NmaEvalContext` — between a parent pack and its
	 * child. Two packs under two different structural keys can therefore reach the same
	 * `NmaNode.lastSeries`/`evalEpoch` fields. Locking the map protects the map; it does nothing
	 * for that. So the registry is only sound while a single thread evaluates, and `CorpusEvoRun`
	 * disables dirty-spine when its fallback pool has more than one worker.
	 *
	 * The accessors below exist so the map itself stays intact for the single-threaded case and
	 * for the main-thread Variation traffic that runs between generation barriers.
	 */
	public static function workingGet(key:String):Null<musescript.evo.nma.NmaWorkingPack> {
		if (nmaWorking == null) return null;
		workingLock.acquire();
		var w = nmaWorking.get(key);
		workingLock.release();
		return w;
	}

	public static function workingPut(key:String, pack:musescript.evo.nma.NmaWorkingPack):Void {
		if (nmaWorking == null) return;
		workingLock.acquire();
		nmaWorking.set(key, pack);
		nmaWorkingPuts++;
		workingLock.release();
	}

	/** Merge one evaluation's pop-memo hit count into the run-wide telemetry total. */
	public static function addNmaPopMemoHits(hits:Int):Void {
		if (hits == 0) return;
		popMemoStatsLock.acquire();
		nmaPopMemoHits += hits;
		popMemoStatsLock.release();
	}

	/**
	 * When >1 (`--speculative-growth-k N`), `attributedPointMutate` grows N bool replacements at
	 * the chosen site and ranks them in one `NmaAttr` session (sibling memos shared). 1 = off.
	 *
	 * «θύρσος πολλαχῇ· εἷς χορός νικᾷ.»
	 */
	public static var speculativeGrowthK:Int = 1;
	/** Robust blocked scoring for speculative candidates (winner's-curse control). */
	public static var speculativeGrowthWindows:Int = 4;
	public static var speculativeGrowthWindowLambda:Float = 0.5;
	/** Candidate must beat the parent's robust score by at least this much; else keep parent. */
	public static var speculativeGrowthMinDelta:Float = 0.0;
	/** Soft complexity penalty used only while ranking speculative candidates. */
	public static var speculativeGrowthParsimonyLambda:Float = 0.01;

	/** Clears the compiled-program cache -- exposed for tests that care about compile counts,
	 * and for a caller switching to a genuinely different program universe (a fresh corpus-evo
	 * process naturally starts with an empty cache; this is for long-lived processes/tests).
	 * Also clears NMA tape-scoped SInd columns so a long-lived process can drop stale tape state.
	 *
	 * «ἅλαδε μύσται· θάλασσα καθαίρει μιασμόν.»
	 */
	public static function clearFnCache():Void {
		fnCacheLock.acquire();
		fnCache = new Map();
		fnCacheLock.release();
		musescript.evo.nma.NmaFitness.clearColumnCache();
		nmaPopMemo = null;
		nmaPopMemoHits = 0;
		nmaWorking = null;
		nmaWorkingHits = 0;
		nmaWorkingPuts = 0;
		musescript.evo.nma.NmaSignalMemo.clear();
	}

	/** Memory budget for the persistent pop-memo column share: ~32M Float cells ≈ 256 MB of
	 * doubles. Columns are keyed by (tape, shape, referenced param values) so they stay valid
	 * across generations — reset only when the share outgrows the budget. */
	static inline var NMA_POP_MEMO_CELL_BUDGET:Float = 32_000_000;

	/** Gen-boundary hook for the NMA pop memo. Since keys are content-addressed against the tape
	 * (not epoch-scoped), entries never go stale: KEEP the share across generations — elites,
	 * recurring motifs, and attribution ablations re-hit warm columns — and reset only on memory
	 * pressure. */
	/**
	 * Share the pop memo across workers. Off only as a measurement lever: the cache is guarded by
	 * one process-wide lock taken on every column lookup AND store, which makes it the densest
	 * shared-state contention point in the evaluation barrier. Turning it off trades a lot of
	 * recomputation for zero contention, which is how to tell whether that lock is what stops
	 * `--threads` from shrinking the barrier.
	 */
	public static var nmaPopMemoEnabled:Bool = true;

	public static function beginNmaPopMemo():Void {
		if (!nmaPopMemoEnabled) nmaPopMemo = null;
		else if (nmaPopMemo == null || nmaPopMemo.cells() > NMA_POP_MEMO_CELL_BUDGET)
			nmaPopMemo = new musescript.evo.nma.NmaColumnCache();
		nmaPopMemoHits = 0;
		nmaOkCount = 0;
		nmaFallCount = 0;
		nmaErrorCount = 0;
		nmaUnsupportedCount = 0;
		fnCompileCount = 0;
		musescript.evo.nma.NmaSignalMemo.begin();
	}

	/** Start / reset gen-scoped dirty-spine working copies (full wipe — startup / tests). */
	public static function beginNmaWorking():Void {
		nmaWorking = new Map();
		nmaWorkingHits = 0;
		nmaWorkingPuts = 0;
	}

	/**
	 * Soft gen boundary: keep packs whose structural keys are in `keepKeys` (current pop),
	 * drop orphans. Resets hit/put counters for the new gen's telemetry.
	 * Without this, Variation registers children at end of gen N and `beginNmaWorking` wiped
	 * them before gen N+1 evaluated — `workHits` stayed 0 forever.
	 */
	public static function pruneNmaWorking(keepKeys:Array<String>):Void {
		if (nmaWorking == null) {
			beginNmaWorking();
			return;
		}
		var keep:Map<String, Bool> = new Map();
		for (k in keepKeys) keep.set(k, true);
		var next:Map<String, musescript.evo.nma.NmaWorkingPack> = new Map();
		for (k => pack in nmaWorking) {
			if (keep.exists(k)) next.set(k, pack);
		}
		nmaWorking = next;
		nmaWorkingHits = 0;
		nmaWorkingPuts = 0;
	}

	/**
	 * `costBps` (default 0 -- zero behavior change for any existing caller) sets `OrderSim.book.
	 * slippageBps` before running, so a genome's entries AND exits pay a realistic spread instead
	 * of trading for free. Was silently 0 for EVERY genome this whole evo package ever scored,
	 * because `long(qty)`/`short(qty)`/`flat()` (what Expand.hx renders and what every genome
	 * actually calls) go through OrderSim's legacy immediate-fill path, which -- until fixed
	 * alongside this parameter -- never called `slip()` at all (only the spec-object order-book
	 * path did). A free-trading backtest systematically favors high-frequency genomes (every
	 * MAP-Elites "scalper" niche), since real transaction cost is exactly what punishes overtrading
	 * -- see OrderSim.hx's executeLong/executeShort/executeFlat doc comment for the full story.
	 *
	 * «μύσταισι χορεύει Νύσιος ἐν ὄρεσσιν.»
	 */
	public static function evaluate(g:StrategyGenome, bars:Array<Bar>, ?target:String = "js", ?strict:Bool = false, ?costBps:Float = 0, ?initialCash:Float = 100000, ?equityFloor:Float = 0.0):FitnessResult {
		if (preferNma) {
			var nma = evaluateNma(g, bars, costBps, initialCash, equityFloor);
			if (nmaVerify && nma.ok) {
				var compiled = evaluateCompiled(g, bars, target, strict, costBps, initialCash, equityFloor);
				assertNmaParity(nma, compiled, g.name);
			}
			if (nma.ok) {
				popMemoStatsLock.acquire();
				nmaOkCount++;
				popMemoStatsLock.release();
				return nma;
			}
			// `nma-unsupported` (KFeature) / `nma-error` → Expand→compile path below.
			popMemoStatsLock.acquire();
			nmaFallCount++;
			if (nma.backend == "nma-error") {
				nmaErrorCount++;
				lastNmaError = nma.error;
			} else if (nma.backend == "nma-unsupported") {
				nmaUnsupportedCount++;
			}
			popMemoStatsLock.release();
		}
		return evaluateCompiled(g, bars, target, strict, costBps, initialCash, equityFloor);
	}

	/**
	 * Leakage-free aggregate forecast skill of the genome's REFERENCED projections (`ProjectionScore`).
	 * `NaN` if the genome declares none. This is the forecast-quality SIGNAL; it feeds selection as a
	 * MAP-Elites descriptor axis (plan §7), computed off the fitness hot path by callers that want it.
	 */
	public static function projectionScore(
		g:StrategyGenome, bars:Array<Bar>, ?provider:ProjectionProvider
	):Float {
		return ProjectionScore.score(g, bars, provider).agg;
	}

	/** Populate `fr.projScore`/`fr.projScores` from `g`'s projections vs `bars`. No-op when none.
	 * Pass a `ProjectionProvider` (with `EwForecastHost`) when the genome uses `PSHost` samplers. */
	public static function attachProjectionScore(
		fr:FitnessResult, g:StrategyGenome, bars:Array<Bar>, ?provider:ProjectionProvider
	):Void {
		if (g.projections == null || g.projections.length == 0)
			return;
		var s = ProjectionScore.score(g, bars, provider);
		fr.projScore = s.agg;
		fr.projScores = s.per;
	}

	/** Columnar NMA path with optional dirty-spine working-copy hit. */
	static function evaluateNma(g:StrategyGenome, bars:Array<Bar>, costBps:Float, initialCash:Float, equityFloor:Float):FitnessResult {
		// Projections (SProj) have no columnar column yet — route to the Expand→interp fallback so a
		// projection genome still evaluates correctly (just not columnar-fast), and never reaches
		// NmaBijection's defensive SProj throw. PROJECTION_COEVOLUTION_PLAN.md P0.b.
		if (g.projections != null && g.projections.length > 0)
			return new FitnessResult(false, -999, 0, 0, "nma-unsupported",
				"genome declares projections (SProj) -- columnar NMA not yet wired");
		if (nmaDirtySpine && nmaWorking != null) {
			try {
				var key = Canonical.structuralKey(g);
				var hit = workingGet(key);
				var tapeMatches = hit != null && hit.ctx.n == bars.length
					&& (hit.bars == bars
						|| hit.tapeSig == musescript.evo.nma.NmaFitness.tapeSignature(bars));
				if (tapeMatches) {
					// Packs can survive a generation boundary, but pop memo intentionally cannot.
					// Rebind the retained context before evaluating instead of writing into an
					// orphaned previous-generation cache.
					hit.ctx.popMemo = nmaPopMemo;
					nmaWorkingHits++;
					return musescript.evo.nma.NmaFitness.evaluatePrepared(hit.nma, hit.ctx, bars, costBps, initialCash, equityFloor);
				}
				var built = musescript.evo.nma.NmaFitness.prepare(g, bars);
				if (built == null)
					return new FitnessResult(false, -999, 0, 0, "nma-unsupported",
						"genome uses KFeature or nested-source SInd -- columnar NMA fitness "
						+ "handles flat market-data indicators only");
				var fr = musescript.evo.nma.NmaFitness.evaluatePrepared(built.nma, built.ctx, bars, costBps, initialCash, equityFloor);
				if (fr.ok) {
					musescript.evo.nma.NmaDirtySpine.put(g, {
						nma: built.nma,
						ctx: built.ctx,
						tapeSig: built.ctx.epoch.tapeKey,
						bars: bars
					});
				}
				return fr;
			} catch (e:Dynamic) {
				return new FitnessResult(false, -999, 0, 0, "nma-error", Std.string(e));
			}
		}
		return musescript.evo.nma.NmaFitness.evaluate(g, bars, costBps, initialCash, equityFloor);
	}

	/**
	 * `--nma-verify` findings, counted rather than thrown.
	 *
	 * This check runs inside eval-pool workers, and a throw there kills the worker without ever
	 * posting a result — which leaves the main thread's collect-N barrier blocked forever. A
	 * parity net that hangs the run instead of reporting is worse than no net: the failure mode
	 * looks like a slow run, not a broken invariant, and it strands the JVM. So findings are
	 * printed as they occur and summarized at the end of the run.
	 *
	 * A compiled-path failure is tracked separately from a genuine mismatch: it says the
	 * Expand→compile ORACLE is broken on that genome, not that the columnar result disagrees
	 * with it, and conflating the two is what made the flag unusable.
	 */
	public static var verifyMismatches:Int = 0;
	public static var verifyCompiledFailures:Int = 0;
	static final verifyLock = new EvoLock();
	static var verifyShown:Int = 0;
	static inline var VERIFY_SHOW_MAX = 5;

	static function recordVerify(compiledFailure:Bool, msg:String):Void {
		verifyLock.acquire();
		if (compiledFailure) verifyCompiledFailures++;
		else verifyMismatches++;
		var show = verifyShown < VERIFY_SHOW_MAX;
		if (show) verifyShown++;
		verifyLock.release();
		#if sys
		if (show) Sys.println("  " + msg);
		#end
	}

	/** End-of-run `--nma-verify` summary. Empty when the flag was off or nothing was found. */
	public static function verifySummary():Null<String> {
		verifyLock.acquire();
		var m = verifyMismatches;
		var c = verifyCompiledFailures;
		verifyLock.release();
		if (m == 0 && c == 0) return null;
		return 'nma-verify: $m column-vs-compiled mismatch(es), $c compiled-path failure(s)'
			+ (verifyShown >= VERIFY_SHOW_MAX ? ' (first $VERIFY_SHOW_MAX shown above)' : '');
	}

	static function assertNmaParity(nma:FitnessResult, compiled:FitnessResult, name:Null<String>):Void {
		if (!compiled.ok) {
			recordVerify(true, 'nma-verify: compiled path failed while NMA ok (${name}): ${compiled.error}');
			return;
		}
		if (nma.trades != compiled.trades
			|| Math.abs(nma.finalEquity - compiled.finalEquity) > 1e-9
			|| (Math.isNaN(nma.sharpe) != Math.isNaN(compiled.sharpe))
			|| (!Math.isNaN(nma.sharpe) && Math.abs(nma.sharpe - compiled.sharpe) > 1e-9)) {
			var firstDiff = -1;
			var eqA = nma.equity, eqB = compiled.equity;
			if (eqA != null && eqB != null) {
				var m = eqA.length < eqB.length ? eqA.length : eqB.length;
				for (i in 0...m) if (Math.abs(eqA[i] - eqB[i]) > 1e-9) { firstDiff = i; break; }
				if (firstDiff == -1 && eqA.length != eqB.length) firstDiff = m;
			}
			var fillsA:Array<Dynamic> = nma.fills != null ? nma.fills : [];
			var fillsB:Array<Dynamic> = compiled.fills != null ? compiled.fills : [];
			recordVerify(false, 'nma-verify mismatch (${name}): '
				+ 'nma trades=${nma.trades} sharpe=${nma.sharpe} eq=${nma.finalEquity} vs '
				+ 'compiled[${compiled.backend}] trades=${compiled.trades} sharpe=${compiled.sharpe} eq=${compiled.finalEquity}'
				+ ' firstEquityDiffBar=$firstDiff (eqLenNma=${eqA != null ? eqA.length : -1} eqLenCompiled=${eqB != null ? eqB.length : -1})'
				+ '\n  nmaFills[0..2]=${fillsA.slice(0, 3)}\n  compiledFills[0..2]=${fillsB.slice(0, 3)}');
		}
	}

	/** Classic Expand → MuseCompiler → harness path (the pre-NMA evaluate body).
	 *
	 * «Ὀρφεὺς κατέβη· κιθάρα νεκροὺς ἔπεισε.»
	 */
	public static function evaluateCompiled(g:StrategyGenome, bars:Array<Bar>, ?target:String = "js", ?strict:Bool = false, ?costBps:Float = 0, ?initialCash:Float = 100000, ?equityFloor:Float = 0.0):FitnessResult {
		var tCompiled = musescript.evo.nma.NmaSignalProbe.stamp();
		try {
			// NOTE: this used to branch on `#if (java || jvm)` into a checker-only fast path
			// that never touched `bars` at all -- it returned trades=max(1,40-nodeCount),
			// finalEquity=100000+trades*10, sharpe=1-nodeCount*0.001, a value derived PURELY
			// from the genome's node count, completely independent of the actual strategy
			// logic or the data passed in. Found via a corpus-evo walk-forward run reporting
			// byte-identical champion stats (trades=31, equity=100310, sharpe=0.991) across
			// unrelated genomes on unrelated tapes -- traced to two DIFFERENT genomes both
			// having nodeCount=9, which is ALL this branch's output actually depended on.
			// Confirmed by re-evaluating the same genome against a 50-bar slice instead of
			// the real 5161-bar tape and getting the identical result. Every JVM-target
			// caller (EvoProof.hx's `build-evo-jvm.hxml` build, and this session's
			// CorpusEvoRun.hx) wanted REAL fitness, not a parsimony-flavored placeholder, so
			// the branch is removed -- JVM now runs the exact same real execution path as
			// every other target, matching MuseCompiler's own documented "js (default) --
			// JsEmitter hot path + eval on JS; MuseInterp elsewhere" fallback contract.
			var evalBars = bars;
			if (projectionProvider != null && ProjectionProvider.hostProjRefs(g).length > 0)
				evalBars = projectionProvider.decorateBars(bars, g);
			var cacheKey = Canonical.structuralKey(g) + ":" + target + ":" + strict;
			fnCacheLock.acquire();
			var cached = fnCache.get(cacheKey);
			fnCacheLock.release();
			var decls:Array<Decl>;
			var fn:BarStrategyFn;
			var backend:String;
			if (cached != null) {
				decls = cached.decls;
				fn = cached.fn;
				backend = cached.backend;
			} else {
				popMemoStatsLock.acquire();
				fnCompileCount++;
				popMemoStatsLock.release();
				var source = Expand.expand(g);
				var prog = new MuseParser().parse(source, "<evo>");
				var ex = MuseCompiler.compileEx(prog, { target: target, strict: strict });
				decls = prog.decls;
				fn = ex.fn;
				backend = ex.backend;
				fnCacheLock.acquire();
				if (count(fnCache) >= FN_CACHE_MAX) fnCache = new Map(); // simple full-clear, not an LRU -- see clearFnCache
				fnCache.set(cacheKey, { fn: fn, decls: decls, backend: backend });
				fnCacheLock.release();
			}
			var tRun = musescript.evo.nma.NmaSignalProbe.stamp();
			var harness = new HarnessContext();
			if (costBps != 0) harness.orders.book.slippageBps = costBps;
			// `--equity-floor`/bankruptcy crank (see OrderSim.hx's doc comment): both are no-ops at
			// their defaults (100000/0.0), so an existing caller that doesn't pass them sees the
			// exact same OrderSim state a bare `new HarnessContext()` already produced.
			if (initialCash != 100000) harness.orders.reset(initialCash);
			if (equityFloor > 0) harness.orders.equityFloor = equityFloor;
			var seed = new MuseInterp(harness);
			for (d in decls) seed.registerDeclPublic(d);
			harness.feed = new BarFeed(evalBars);
			TradeBuiltins.resetCrossState();
			var result:Dynamic = fn(harness);
			var fr = new FitnessResult(
				true,
				fieldF(result, "sharpe"),
				fieldI(result, "trades"),
				fieldF(result, "finalEquity"),
				backend
			);
			fr.fills = Reflect.field(result, "fills");
			fr.bankrupt = harness.orders.bankrupt;
			if (equityCurveNeeded) fr.equity = harness.orders.equity.toArray();
			var tEnd = musescript.evo.nma.NmaSignalProbe.wall();
			musescript.evo.nma.NmaSignalProbe.observeCompiled(tEnd - tCompiled, tRun - tCompiled, tEnd - tRun);
			return fr;
		} catch (e:Dynamic) {
			musescript.evo.nma.NmaSignalProbe.observeCompiled(musescript.evo.nma.NmaSignalProbe.wall() - tCompiled, 0, 0);
			// Under `--nma-verify` this path is the ORACLE, so a failure here is the thing being
			// diagnosed rather than a genome being rejected -- carry the stack, not just the message.
			var msg = Std.string(e);
			if (nmaVerify) {
				msg += "\n    " + StringTools.replace(haxe.CallStack.toString(haxe.CallStack.exceptionStack()), "\n", "\n    ");
				msg += "\n--- expanded source ---\n" + try Expand.expand(g) catch (_:Dynamic) "<expand failed>";
			}
			return new FitnessResult(false, -999, 0, 0, "error", msg);
		}
	}

	/**
	 * Whether `FitnessResult.equity` has to be materialized. Only `robustScore` / `windowSharpes`
	 * (`--fitness-windows > 1`) and the `--nma-verify` parity check ever read the curve; plain
	 * whole-tape Sharpe needs nothing but the scalar.
	 *
	 * `OrderSim.equity` is an unboxed `GrowableVec<Float>`, but handing it out as `Array<Float>`
	 * boxes a `java.lang.Double` per bar and `returnsFromEquity` then boxes a second array of the
	 * same length (guide §3.1). At P=1000 that was the single largest allocator on the eval
	 * barrier, for two arrays that the default configuration immediately discards. Left `true` so
	 * every caller that does not opt out keeps the curve.
	 */
	public static var equityCurveNeeded:Bool = true;

	/**
	 * When > 0, `robustScore` grades a genome on the mean of its WORST `ceil(alpha * windows)`
	 * window Sharpes instead of `mean - windowLambda*std`.
	 *
	 * `mean - lambda*std` is minimized by being uniformly mediocre, so a genome with no real edge
	 * anywhere can outrank one that is strong in most regimes and merely soft in a few — the std
	 * term punishes the variance that a genuine edge produces. CVaR cannot be gamed that way; it
	 * only ever reads the bad stretches, which makes it a minimax objective against "pick the
	 * worst part of the tape" using windows that are already being computed. 0 keeps the original
	 * combine exactly.
	 */
	public static var cvarAlpha:Float = 0.0;

	public static inline var NEG_INF = -1.0 / 0.0;

	/**
	 * Pipeline-hardening min-trade gate (Bucket A1). A genome below this trade count is
	 * INELIGIBLE — `score` / `scoreFacts` / `robustScore` return NEG_INF. Default 20 closes the
	 * thin-trade false-positive leak (1 lucky trade → huge Sharpe). Callers that intentionally
	 * want the old 1-trade floor pass `minTrades=1` explicitly (tests, attribution ablations).
	 * CorpusEvoRun sets this from `--min-trades`.
	 */
	public static var defaultMinTrades:Int = 20;

	/** Resolve optional minTrades; null → `defaultMinTrades`. */
	public static inline function resolveMinTrades(?minTrades:Null<Int>):Int {
		return minTrades != null ? minTrades : defaultMinTrades;
	}

	/**
	 * Canonical oracle score from a `FitnessResult`: NEG_INF on fail / NaN / too few trades /
	 * bankruptcy. Optionally soft-caps by genome complexity (see below).
	 *
	 * Includes `bankrupt` — callers historically checked it in ad-hoc predicates while this
	 * function did not. Use `score` / `scoreFacts` everywhere a NEG_INF oracle is needed.
	 *
	 * `minTrades` defaults to `defaultMinTrades` (20). Pass `1` only when a low floor is deliberate.
	 */
	public static function score(r:FitnessResult, ?minTrades:Null<Int>,
			?nodeCount:Int, ?parsimonyThreshold:Int = 20, ?parsimonyLambda:Float = 0.01):Float {
		if (!r.ok) return NEG_INF;
		if (r.bankrupt) return NEG_INF;
		return scoreFacts(r.trades, r.sharpe, false, minTrades, nodeCount, parsimonyThreshold, parsimonyLambda);
	}

	/**
	 * Same NEG_INF contract as `score` for pre-aggregated facts (CachedEval / basket aggregates)
	 * without a full `FitnessResult`. Pass `bankrupt=true` to force NEG_INF.
	 */
	public static function scoreFacts(
		trades:Int, sharpe:Float, bankrupt:Bool = false, ?minTrades:Null<Int>,
		?nodeCount:Int, ?parsimonyThreshold:Int = 20, ?parsimonyLambda:Float = 0.01
	):Float {
		if (bankrupt) return NEG_INF;
		if (trades < resolveMinTrades(minTrades)) return NEG_INF;
		if (Math.isNaN(sharpe)) return NEG_INF;
		var s = sharpe;
		if (nodeCount != null && nodeCount > parsimonyThreshold)
			s -= parsimonyLambda * (nodeCount - parsimonyThreshold);
		return s;
	}

	/**
	 * Sample-size-aware ranking score (Bucket A2): when `r.equity` is present, rank by
	 * Probabilistic Sharpe (probit of PSR / DSR); otherwise fall back to `score`.
	 * Thin-trade genomes still hit NEG_INF via the min-trade gate.
	 */
	public static function rankScore(r:FitnessResult, ?minTrades:Null<Int>, ?nTrials:Int = 1,
			?nodeCount:Int, ?parsimonyThreshold:Int = 20, ?parsimonyLambda:Float = 0.01):Float {
		var base = score(r, minTrades, nodeCount, parsimonyThreshold, parsimonyLambda);
		if (base == NEG_INF) return NEG_INF;
		if (r.equity == null || r.equity.length < 4)
			return base;
		var rets = musescript.harness.Metrics.returnsFromEquity(r.equity);
		var rs = musescript.evo.rigor.ProbSharpe.rankScore(rets, nTrials != null ? nTrials : 1);
		if (!Math.isFinite(rs)) return NEG_INF;
		if (nodeCount != null && nodeCount > parsimonyThreshold)
			rs -= parsimonyLambda * (nodeCount - parsimonyThreshold);
		return rs;
	}

	/**
	 * IS-selection rank from cached eval facts (no equity curve required).
	 * Uses `ProbSharpe.rankFromAnnualized` so CorpusEvoRun / EvoCache can DSR-rank without
	 * materializing per-bar equity on every genome. Same NEG_INF gates as `scoreFacts`.
	 */
	public static function rankScoreFacts(
		trades:Int, sharpe:Float, nObs:Int, bankrupt:Bool = false, ?minTrades:Null<Int>,
		?nTrials:Int = 1, ?nodeCount:Int, ?parsimonyThreshold:Int = 20, ?parsimonyLambda:Float = 0.01
	):Float {
		if (bankrupt) return NEG_INF;
		if (trades < resolveMinTrades(minTrades)) return NEG_INF;
		if (Math.isNaN(sharpe)) return NEG_INF;
		var rs = musescript.evo.rigor.ProbSharpe.rankFromAnnualized(
			sharpe, nObs, 0, 0, nTrials != null ? nTrials : 1);
		if (!Math.isFinite(rs)) return NEG_INF;
		if (nodeCount != null && nodeCount > parsimonyThreshold)
			rs -= parsimonyLambda * (nodeCount - parsimonyThreshold);
		return rs;
	}

	/**
	 * Robustness-adjusted variant of `score()`: splits the backtest's OWN equity curve (`r.
	 * equity`, populated by `evaluate` from `harness.orders.equity` -- already computed for free,
	 * no extra simulator runs needed) into `windows` contiguous segments, scores each segment's
	 * OWN Sharpe independently, and combines them as mean-minus-`windowLambda`*std instead of one
	 * whole-tape Sharpe. A genome that's excellent in one stretch of the tape and mediocre or
	 * harmful elsewhere gets exactly the same single-scalar Sharpe as one that's modestly good
	 * throughout -- windowing is what lets the fitness function actually tell them apart, directly
	 * rewarding robustness instead of a single lucky curve-fit.
	 *
	 * Falls back to plain `score()` (today's exact behavior) whenever windowing wouldn't be
	 * meaningful: `windows <= 1`, no equity curve attached, or too few bars to give every window
	 * at least 2 points to compute a return from. Never a crash, never a NEG_INF where `score()`
	 * would have returned a real number.
	 */
	/**
	 * Per-window Sharpes over `r.equity` (same segmentation as `robustScore`). Empty when the
	 * equity curve is missing/too short. Used by `--lexicase` as a case vector; `robustScore` still
	 * collapses these to one scalar for champion/archive reporting.
	 */
	public static function windowSharpes(r:FitnessResult, windows:Int):Array<Float> {
		if (!r.ok || r.bankrupt || Math.isNaN(r.sharpe)) return [];
		if (windows <= 1 || r.equity == null || r.equity.length < windows * 2) {
			return [r.sharpe];
		}
		var segLen = Std.int(r.equity.length / windows);
		var segSharpes:Array<Float> = [];
		for (w in 0...windows) {
			var startI = w * segLen;
			var endI = (w == windows - 1) ? r.equity.length : startI + segLen;
			if (endI - startI < 2) continue;
			var seg = r.equity.slice(startI, endI);
			var rets = musescript.harness.Metrics.returnsFromEquity(seg);
			if (rets.length < 2) continue;
			var sh = musescript.harness.Metrics.sharpe(rets, 0.0);
			if (!Math.isNaN(sh)) segSharpes.push(sh);
		}
		return segSharpes;
	}

	public static function robustScore(r:FitnessResult, windows:Int, windowLambda:Float, ?minTrades:Null<Int>,
			?nodeCount:Int, ?parsimonyThreshold:Int = 20, ?parsimonyLambda:Float = 0.01):Float {
		var mt = resolveMinTrades(minTrades);
		if (!r.ok) return NEG_INF;
		if (r.bankrupt) return NEG_INF;
		if (Math.isNaN(r.sharpe)) return NEG_INF;
		if (r.trades < mt) return NEG_INF;
		if (windows <= 1 || r.equity == null || r.equity.length < windows * 2)
			return score(r, mt, nodeCount, parsimonyThreshold, parsimonyLambda);
		var segSharpes = windowSharpes(r, windows);
		if (segSharpes.length == 0) return score(r, mt, nodeCount, parsimonyThreshold, parsimonyLambda);
		var s = cvarAlpha > 0 ? cvar(segSharpes, cvarAlpha) : meanMinusStd(segSharpes, windowLambda);
		if (nodeCount != null && nodeCount > parsimonyThreshold)
			s -= parsimonyLambda * (nodeCount - parsimonyThreshold);
		return s;
	}

	/** `mean - lambda*std` over the window Sharpes — the original robustness combine. */
	static function meanMinusStd(xs:Array<Float>, lambda:Float):Float {
		var mean = 0.0;
		for (i in 0...xs.length) mean += xs[i];
		mean /= xs.length;
		var variance = 0.0;
		for (i in 0...xs.length) {
			var d = xs[i] - mean;
			variance += d * d;
		}
		variance /= xs.length;
		return mean - lambda * Math.sqrt(variance);
	}

	/**
	 * Mean of the worst `ceil(alpha * n)` entries (at least one) — the conditional value at risk
	 * of the window Sharpes.
	 */
	static function cvar(xs:Array<Float>, alpha:Float):Float {
		var sorted = xs.copy();
		sorted.sort((a, b) -> a < b ? -1 : a > b ? 1 : 0);
		var k = Math.ceil(alpha * sorted.length);
		if (k < 1) k = 1;
		if (k > sorted.length) k = sorted.length;
		var sum = 0.0;
		for (i in 0...k) sum += sorted[i];
		return sum / k;
	}

	static function count<T>(m:Map<String, T>):Int {
		var n = 0;
		for (_ in m.keys()) n++;
		return n;
	}

	static function fieldF(o:Dynamic, n:String):Float {
		if (o == null) return 0;
		var v:Dynamic = Reflect.field(o, n);
		if (v == null) return 0;
		return Std.parseFloat(Std.string(v));
	}

	static function fieldI(o:Dynamic, n:String):Int {
		if (o == null) return 0;
		var v:Dynamic = Reflect.field(o, n);
		if (v == null) return 0;
		var p = Std.parseInt(Std.string(v));
		return p != null ? p : Std.int(Std.parseFloat(Std.string(v)));
	}
}
