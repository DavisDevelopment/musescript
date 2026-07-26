package musescript.evo.nma;

import musescript.evo.StrategyGenome;
import musescript.evo.Fitness;
import musescript.evo.FitnessResult;
import musescript.evo.AttrPool;
import musescript.evo.BoolNode;
import musescript.evo.ScalarNode;
import musescript.evo.GenomeFeatures;
import musescript.evo.CatalogSite;
import musescript.evo.TreeSurgery;
import musescript.evo.nma.NmaBool;
import musescript.evo.nma.NmaScalar;
import musescript.evo.nma.NmaBijection;
import musescript.evo.nma.NmaFitness;
import musescript.evo.nma.NmaGenome;
import musescript.evo.nma.NmaEvalContext;
import musescript.evo.nma.NmaSurgery;
import musescript.evo.TreeSurgery.GPath;
import musescript.evo.Canonical;
import musescript.harness.Bar;

/** Alias for `CatalogSite` — kept so existing `NmaAttr.NmaAttrSite` casts keep compiling.
 *
 * «ὅρκος ἀνήρ· ἐς ἀλήθειαν ἵησι πόδα.»
 */
typedef NmaAttrSite = CatalogSite;

/**
 * P1c+ attribution batching on a live NMA working copy: one `genomeFromEnum` + baseline eval,
 * then each bool ablation is a spine-rebuild (`NmaSurgery`) that preserves sibling memos. Scores
 * match `Fitness.score` / oracle NEG_INF contract for pure market-data genomes.
 *
 * «κύκλου δ᾽ ἐξέπταν βαρυπενθέος ἀργαλέοιο.»
 */
class NmaAttr {

	/** Sessions served from the per-thread slot vs. built fresh. Racy on purpose -- plain int
	 * increments from pool workers, read only by `--phase-profile` telemetry, and a lock here
	 * would cost more than the number is worth. Undercounts, never misleads. */
	public static var sessionHits:Int = 0;
	public static var sessionMisses:Int = 0;

	#if target.threaded
	static final sessionTls = new sys.thread.Tls<AttrSession>();
	static inline function heldSession():Null<AttrSession> return sessionTls.value;
	static inline function holdSession(s:AttrSession):Void sessionTls.value = s;
	#else
	static var sessionSlot:Null<AttrSession> = null;
	static inline function heldSession():Null<AttrSession> return sessionSlot;
	static inline function holdSession(s:AttrSession):Void sessionSlot = s;
	#end

	/**
	 * The prepared column-swap session for `g`, from the calling thread's single slot when it is
	 * already the right one.
	 *
	 * Attributed crossover asks two questions about the same parent back to back -- which site to
	 * cut (`boolSiteDeltas`) and which donor to graft there (`boolDonorScores`) -- and each used
	 * to open its own session, paying a second `genomeFromEnum` plus a second full baseline for
	 * an answer it already had. One slot per thread is enough to collapse that: the pair is
	 * adjacent, so a slot keyed on the parent REFERENCE hits without a hash, and any miss simply
	 * rebuilds rather than returning something stale.
	 *
	 * Slots are per-thread because the session is mutable: `NmaSurgery` writes a root, scores,
	 * and writes it back, so two workers sharing one would interleave surgery on the same tree.
	 *
	 * «δύο ἐρωτήσεις, μία λύρα.»
	 */
	static function sessionFor(g:StrategyGenome, bars:Array<Bar>, costBps:Float,
			initialCash:Float, equityFloor:Float):Null<AttrSession> {
		var held = heldSession();
		if (held != null && held.g == g && held.bars == bars && held.costBps == costBps
				&& held.initialCash == initialCash && held.equityFloor == equityFloor) {
			// `beginNmaPopMemo` swaps the cache out when it outgrows its cell budget; rebind so a
			// retained session writes into the live one instead of an orphaned generation's.
			held.ctx.popMemo = Fitness.nmaPopMemo;
			sessionHits++;
			return held;
		}
		var built = NmaFitness.prepare(g, bars);
		if (built == null) return null;
		var baseline = NmaFitness.scorePrepared(
			built.nma, built.ctx, bars, costBps, initialCash, equityFloor);
		var fresh = new AttrSession(g, bars, costBps, initialCash, equityFloor,
			built.nma, built.ctx, baseline);
		holdSession(fresh);
		sessionMisses++;
		return fresh;
	}

	/** Drop the calling thread's session (tests switching tapes under a live slot). */
	public static function clearSession():Void {
		#if target.threaded
		sessionTls.value = null;
		#else
		sessionSlot = null;
		#end
	}

	/**
	 * Score `g` with `repl` spliced in at `site`, then put the original root back.
	 *
	 * This is the column swap itself, and the reason attribution is affordable: the prepared tree
	 * keeps every sibling column memoized, so replacing one bool root re-derives only the spine
	 * above the cut and re-runs the B-bar OrderSim. Everything else is a memo hit. Compare with
	 * scoring an ablated genome through `evalFn`, which rebuilds the NMA copy, the context and
	 * the epoch, and re-evaluates all five roots from cold.
	 *
	 * «ἓν νῆμα λύεται· ὁ ἱστὸς μένει.»
	 */
	static function swapScore(sess:AttrSession, slot:Int, path:GPath, repl:NmaBool):Float {
		var saved = NmaSurgery.boolRoot(sess.nma, slot);
		NmaSurgery.setBoolRoot(sess.nma, slot, NmaSurgery.replaceBool(saved, path, repl));
		var s = NmaFitness.scorePrepared(sess.nma, sess.ctx, sess.bars,
			sess.costBps, sess.initialCash, sess.equityFloor);
		NmaSurgery.setBoolRoot(sess.nma, slot, saved);
		return s;
	}

	/** Always-true bool used by attributed mutate/crossover ablations (`1 > 0`).
	 *
	 * «εὑρήκαμεν, συγκάθομεν· Βάκχος ἡγεῖται.»
	 */
	public static function alwaysTrueNma():NmaBool {
		return new NmaBCmp(">", new NmaKConst(1.0), new NmaKConst(0.0));
	}

	/**
	 * Baseline oracle score + per-site deltas (`baseline - ablated`) for bool catalog entries.
	 * Falls back to null when columnar NMA cannot host `g` (caller uses enum `evalFn`).
	 *
	 * Every site that the bank cannot already answer for is MEASURED, by column swap, including
	 * under nested pool workers. The previous shape of this function refused to measure anything
	 * on a worker thread and returned bank means instead -- but `NmaCreditBank.means` yields 0.0
	 * for a key it has never seen, and with ~990 distinct genomes per generation most keys are
	 * unseen. Attributed variation was therefore ranking sites by a vector of zeros, i.e. picking
	 * arbitrarily while charging for attribution. The reason that shortcut existed was that the
	 * only nested-safe oracle was `scoreAll`, which degrades to sequential FULL evaluations under
	 * nesting (~7 s CPU/gen, measured); a swap on a prepared session is a different order of
	 * cost, so the refusal is no longer buying anything.
	 *
	 * `Fitness.creditCuts` still short-circuits a genuinely warm bank -- those means are observed
	 * data, not a default -- and `Fitness.attrBandit` still lets UCB skip individual sites.
	 *
	 * «Σίβυλλα μαίνεται· θεὸς ἐν αὐτῇ λαλεῖ.»
	 */
	public static function boolSiteDeltas(
		g:StrategyGenome,
		sites:Array<NmaAttrSite>,
		bars:Array<Bar>,
		?costBps:Float = 0.0,
		?initialCash:Float = 100000,
		?equityFloor:Float = 0.0
	):Null<{baseline:Float, deltas:Array<Float>, keys:Array<String>}> {
		if (!NmaFitness.columnSwappable(g)) return null;

		// Site keys from the ENUM genome — no prepare required. The warm credit-cuts path used
		// to openSession (full columnar baseline) just to read keys off the NMA tree, which meant
		// every attributed mutate on a fresh child paid a serial backtest even when every ablation
		// was about to be skipped. Keys are shape-identical across the bijection.
		var siteKeys = new Array<String>();
		var bestUcb = Math.NEGATIVE_INFINITY;
		for (e in sites) {
			var root = enumBoolRoot(g, e.slot);
			var node = musescript.evo.TreeSurgery.getBool(root, e.path);
			var key = Canonical.boolStructuralKey(node);
			siteKeys.push(key);
			var u = NmaCreditBank.ucb(key);
			if (u > bestUcb) bestUcb = u;
		}
		if (bestUcb == Math.NEGATIVE_INFINITY) bestUcb = 0.0;

		// §6b credit-cuts: a bank warm on EVERY site is observed data and worth the whole
		// session. A bank that is merely non-empty is not, so anything else falls through to
		// measurement below.
		if (Fitness.creditCuts && NmaCreditBank.warmEnough(siteKeys))
			return { baseline: Math.NaN, deltas: NmaCreditBank.means(siteKeys), keys: siteKeys };
		if (Fitness.attrBankOnly && AttrPool.isNested())
			return { baseline: Math.NaN, deltas: NmaCreditBank.means(siteKeys), keys: siteKeys };

		var sess = sessionFor(g, bars, costBps, initialCash, equityFloor);
		if (sess == null) return null;
		var baseline = sess.baseline;
		// Warm keys keep their bank mean; cold keys get measured. With creditCuts off, every
		// site is cold by definition and all of them are measured.
		var deltas = Fitness.creditCuts
			? NmaCreditBank.means(siteKeys)
			: [for (_ in sites) 0.0];
		var measure = Fitness.creditCuts
			? NmaCreditBank.coldIndices(siteKeys)
			: [for (i in 0...sites.length) i];
		var always = alwaysTrueNma();

		for (i in measure) {
			var key = siteKeys[i];
			if (Fitness.attrBandit && !NmaCreditBank.shouldAblate(key, bestUcb)) {
				deltas[i] = NmaCreditBank.mean(key);
				continue;
			}
			var e = sites[i];
			var delta = baseline - swapScore(sess, e.slot, e.path, always);
			deltas[i] = delta;
			creditAt(NmaSurgery.boolRoot(sess.nma, e.slot), e.path, key, delta);
		}
		return { baseline: baseline, deltas: deltas, keys: siteKeys };
	}

	/**
	 * Oracle scores for splicing each `donor` enum bool into `site` on `g` (attribution crossover
	 * donor ranking). Returns null when NMA cannot host `g`.
	 *
	 * With `Fitness.creditCuts` + warm donors: rank by bank mean of donor shape (zero splice evals).
	 *
	 * «Μαινάδες ῥηγνῦσιν ὄρη· εὐοῖ διὰ νύκτα.»
	 */
	public static function boolDonorScores(
		g:StrategyGenome,
		site:NmaAttrSite,
		donors:Array<BoolNode>,
		bars:Array<Bar>,
		?costBps:Float = 0.0,
		?initialCash:Float = 100000,
		?equityFloor:Float = 0.0
	):Null<Array<Float>> {
		if (!NmaFitness.columnSwappable(g)) return null;
		var donorKeys = [for (d in donors) Canonical.boolStructuralKey(d)];

		// A donor's bank mean is the average ABLATION DELTA of that shape wherever it has been
		// cut before -- a prior on the shape, not on the graft. Warm-bank ranking is therefore
		// only ever a stand-in for the splice score, which is why it needs the whole set warm
		// before it is allowed to stand in for measurement.
		if ((Fitness.creditCuts && NmaCreditBank.warmEnough(donorKeys))
				|| (Fitness.attrBankOnly && AttrPool.isNested())) {
			var priors = NmaCreditBank.means(donorKeys);
			for (i in 0...donors.length)
				if (GenomeFeatures.boolIsSimCoupled(donors[i])) priors[i] = Fitness.NEG_INF;
			return priors;
		}

		var sess = sessionFor(g, bars, costBps, initialCash, equityFloor);
		if (sess == null) return null;
		var scores = Fitness.creditCuts
			? NmaCreditBank.means(donorKeys)
			: [for (_ in donors) Fitness.NEG_INF];
		var measure = Fitness.creditCuts
			? NmaCreditBank.coldIndices(donorKeys)
			: [for (i in 0...donors.length) i];
		// A donor carrying a position-state feature can't be spliced onto a columnar parent at
		// all, so it is unrankable rather than merely unmeasured -- NEG_INF regardless of bank.
		for (i in 0...donors.length)
			if (GenomeFeatures.boolIsSimCoupled(donors[i])) scores[i] = Fitness.NEG_INF;

		for (i in measure) {
			if (GenomeFeatures.boolIsSimCoupled(donors[i])) continue;
			scores[i] = swapScore(sess, site.slot, site.path, NmaBijection.boolFromEnum(donors[i]));
		}
		return scores;
	}

	/**
	 * Speculative growth (§6b): oracle scores for K grown bool replacements at one site, one
	 * prepare session — sibling memos survive between candidates (same pattern as `boolDonorScores`).
	 * Null when NMA cannot host `g`. Credit-cuts short-circuit when replacement keys are warm.
	 *
	 * «πολλαὶ χορδαί· μία λύρα κρίνει.»
	 */
	public static function boolReplacementScores(
		g:StrategyGenome,
		site:NmaAttrSite,
		replacements:Array<BoolNode>,
		bars:Array<Bar>,
		?costBps:Float = 0.0,
		?initialCash:Float = 100000,
		?equityFloor:Float = 0.0
	):Null<Array<Float>> {
		if (!NmaFitness.columnSwappable(g)) return null;
		var replKeys = [for (r in replacements) Canonical.boolStructuralKey(r)];
		if (Fitness.creditCuts && NmaCreditBank.warmEnough(replKeys)) {
			return [for (k in replKeys) NmaCreditBank.mean(k)];
		}
		var pack = openSession(g, bars, costBps, initialCash, equityFloor);
		if (pack == null) return null;
		var scores = new Array<Float>();
		var saved = NmaSurgery.boolRoot(pack.nma, site.slot);
		for (r in replacements) {
			if (GenomeFeatures.boolIsSimCoupled(r)) {
				scores.push(Fitness.NEG_INF);
				continue;
			}
			var repl = NmaBijection.boolFromEnum(r);
			NmaSurgery.setBoolRoot(pack.nma, site.slot, NmaSurgery.replaceBool(saved, site.path, repl));
			var fr = NmaFitness.evaluatePrepared(pack.nma, pack.ctx, bars, costBps, initialCash, equityFloor);
			scores.push(Fitness.score(fr, 1));
			NmaSurgery.setBoolRoot(pack.nma, site.slot, saved);
		}
		return scores;
	}

	/**
	 * Speculative-growth v2: blocked robustness score for the parent and every replacement.
	 * Unlike `boolReplacementScores`, this deliberately ignores credit-bank short-circuits:
	 * selecting K random grows from historical IS means amplified winner's curse in measured OOS.
	 */
	public static function boolReplacementRobustScores(
		g:StrategyGenome,
		site:NmaAttrSite,
		replacements:Array<BoolNode>,
		bars:Array<Bar>,
		windows:Int,
		windowLambda:Float,
		parsimonyLambda:Float,
		?costBps:Float = 0.0,
		?initialCash:Float = 100000,
		?equityFloor:Float = 0.0
	):Null<{baseline:Float, scores:Array<Float>}> {
		if (!NmaFitness.columnSwappable(g)) return null;
		var pack = openSession(g, bars, costBps, initialCash, equityFloor);
		if (pack == null) return null;
		var parentNodes = Canonical.nodeCount(g);
		var baseline = Fitness.robustScore(
			pack.fr, windows, windowLambda, 1, parentNodes, 20, parsimonyLambda);
		var scores = new Array<Float>();
		var saved = NmaSurgery.boolRoot(pack.nma, site.slot);
		var oldNode = NmaSurgery.nodeAtBool(saved, site.path);
		var oldCount = Canonical.boolNodeCount(NmaBijection.boolToEnum(oldNode));
		for (r in replacements) {
			if (GenomeFeatures.boolIsSimCoupled(r)) {
				scores.push(Fitness.NEG_INF);
				continue;
			}
			var repl = NmaBijection.boolFromEnum(r);
			NmaSurgery.setBoolRoot(pack.nma, site.slot, NmaSurgery.replaceBool(saved, site.path, repl));
			var fr = NmaFitness.evaluatePrepared(
				pack.nma, pack.ctx, bars, costBps, initialCash, equityFloor);
			var childNodes = parentNodes - oldCount + Canonical.boolNodeCount(r);
			scores.push(Fitness.robustScore(
				fr, windows, windowLambda, 1, childNodes, 20, parsimonyLambda));
			NmaSurgery.setBoolRoot(pack.nma, site.slot, saved);
		}
		return {baseline: baseline, scores: scores};
	}

	static function openSession(g:StrategyGenome, bars:Array<Bar>, costBps:Float, initialCash:Float, equityFloor:Float):Null<{nma:NmaGenome, ctx:NmaEvalContext, fr:FitnessResult}> {
		var built = NmaFitness.prepare(g, bars);
		if (built == null) return null;
		var fr = NmaFitness.evaluatePrepared(built.nma, built.ctx, bars, costBps, initialCash, equityFloor);
		return { nma: built.nma, ctx: built.ctx, fr: fr };
	}

	static function enumBoolRoot(g:StrategyGenome, slot:Int):BoolNode {
		return switch (slot) {
			case 0: g.entryLong;
			case 1: g.entryShort;
			case 2: g.exitLong;
			case 3: g.exitShort;
			default: throw 'NmaAttr.enumBoolRoot: slot $slot is not a bool root';
		};
	}

	/** P2: accumulate ablation Δ onto the site node (`creditSum`/`creditN`) and the bank.
	 *
	 * `key` is passed in rather than re-derived: the caller already hashed this site's shape to
	 * consult the bank, and rebuilding it here meant a `boolToEnum` plus a SHA1 per site purely
	 * to arrive at the same string.
	 *
	 * «χρυσὸν δῶρον· τίμημα ψυχῆς.»
	 */
	static function creditAt(root:NmaBool, path:GPath, key:String, delta:Float):Void {
		if (delta == Fitness.NEG_INF || Math.isNaN(delta)) return;
		var n:NmaBool = NmaSurgery.nodeAtBool(root, path);
		(n : NmaNode).creditSum += delta;
		(n : NmaNode).creditN += 1;
		NmaCreditBank.deposit(key, delta);
	}
}

/**
 * One parent's prepared column-swap session: the NMA working copy, its eval context (which owns
 * the memoized sibling columns that make a swap cheap), and the unablated baseline score.
 *
 * Immutable by field, mutable by tree: `swapScore` writes a root and writes it back, so a session
 * belongs to exactly one thread (see `NmaAttr.sessionFor`).
 *
 * «ἓν ἐργαστήριον, πολλαὶ τομαί.»
 */
private class AttrSession {
	public final g:StrategyGenome;
	public final bars:Array<Bar>;
	public final costBps:Float;
	public final initialCash:Float;
	public final equityFloor:Float;
	public final nma:NmaGenome;
	public final ctx:NmaEvalContext;
	public final baseline:Float;

	public function new(g:StrategyGenome, bars:Array<Bar>, costBps:Float, initialCash:Float,
			equityFloor:Float, nma:NmaGenome, ctx:NmaEvalContext, baseline:Float) {
		this.g = g;
		this.bars = bars;
		this.costBps = costBps;
		this.initialCash = initialCash;
		this.equityFloor = equityFloor;
		this.nma = nma;
		this.ctx = ctx;
		this.baseline = baseline;
	}
}
