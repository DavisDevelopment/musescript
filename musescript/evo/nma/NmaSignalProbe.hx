package musescript.evo.nma;

import musescript.evo.EvoLock;

/**
 * Measurement scaffold for the signal-dedup question, behind `--signal-probe`.
 *
 * Two numbers decide whether pre-sim dedup is worth building and neither was known: what share of
 * an evaluation is the `OrderSim` loop rather than column evaluation, and how many genomes per
 * generation actually share a signal signature. The familiar ~490/gen duplicate figure comes from
 * `FillHash`, which is a COARSER equivalence than a signal signature -- many distinct signal
 * columns collapse onto the same fill sequence -- so it bounds what this can catch rather than
 * estimating it. It is also computed after the sim it would need to skip.
 *
 * Off by default and free when off: `stamp` never reads the clock.
 *
 * «πρὶν ἢ τεμεῖν, μέτρησον.»
 */
class NmaSignalProbe {
	public static var on:Bool = false;

	static final lock = new EvoLock();
	static var seen:Map<String, Bool> = new Map();

	static var evals:Int = 0;
	static var duplicates:Int = 0;
	static var secColumns:Float = 0;
	static var secPack:Float = 0;
	static var secSim:Float = 0;
	static var compiled:Int = 0;
	static var secCompiled:Float = 0;
	/** Split of the fallback: rendering+parsing+compiling the genome, vs actually running it. */
	static var secBuild:Float = 0;
	static var secRun:Float = 0;
	/**
	 * The enum->NMA crossing in `NmaFitness.prepare`, split from the rest of prepare (tape state
	 * lookup, context allocation). This is the price of keeping the population in the enum IR
	 * while evaluating in NMA: a whole fresh tree, allocated per prepare, memos cleared. Counted
	 * separately because it bounds what collapsing to a single representation could return.
	 */
	static var prepares:Int = 0;
	static var secBijection:Float = 0;
	static var secPrepareRest:Float = 0;

	/**
	 * Per-job wall time in the fallback evaluation pool. A barrier that will not shrink with
	 * `--threads` is either throughput-bound (sum/N) or tail-bound (one long job everyone waits
	 * on); `sum` against `max` is what tells those apart, and nothing else measured so far can.
	 */
	static var jobs:Int = 0;
	static var secJobs:Float = 0;
	static var secJobMax:Float = 0;

	/** Wall clock (JS-safe). Prefer this over bare `Sys.time()` so muse-runtime.js builds. */
	public static inline function wall():Float {
		#if sys
		return Sys.time();
		#else
		return Date.now().getTime() / 1000.0;
		#end
	}

	public static inline function stamp():Float {
		return on ? wall() : 0.0;
	}

	public static function observe(sig:String, columns:Float, pack:Float, sim:Float):Void {
		if (!on) return;
		lock.acquire();
		evals++;
		if (seen.exists(sig)) duplicates++;
		else seen.set(sig, true);
		secColumns += columns;
		secPack += pack;
		secSim += sim;
		lock.release();
	}

	/** The Expand->parse->compile fallback, for genomes columnar NMA cannot host. Counted here so
	 * it can be weighed against the columnar path in the same units. */
	public static function observeCompiled(seconds:Float, build:Float, run:Float):Void {
		if (!on) return;
		lock.acquire();
		compiled++;
		secCompiled += seconds;
		secBuild += build;
		secRun += run;
		lock.release();
	}

	public static function observeJob(seconds:Float):Void {
		if (!on) return;
		lock.acquire();
		jobs++;
		secJobs += seconds;
		if (seconds > secJobMax) secJobMax = seconds;
		lock.release();
	}

	public static function observePrepare(bijection:Float, rest:Float):Void {
		if (!on) return;
		lock.acquire();
		prepares++;
		secBijection += bijection;
		secPrepareRest += rest;
		lock.release();
	}

	/** Report the generation just finished and reset. Times are summed across worker threads, so
	 * they are CPU rather than wall -- the ratio between them is the point, not the absolute. */
	public static function drain(gen:Int):String {
		lock.acquire();
		var line = 'signal-probe gen=$gen evals=$evals dup=$duplicates (${pct(duplicates, evals)})'
			+ ' cpu: columns=${ms(secColumns)}ms pack=${ms(secPack)}ms sim=${ms(secSim)}ms'
			+ ' | fallback=$compiled ${ms(secCompiled)}ms'
			+ ' (build=${ms(secBuild)}ms run=${ms(secRun)}ms)'
			+ ' | prepare=$prepares bijection=${ms(secBijection)}ms rest=${ms(secPrepareRest)}ms'
			+ ' | jobs=$jobs sum=${ms(secJobs)}ms max=${ms(secJobMax)}ms mean=${ms(jobs > 0 ? secJobs / jobs : 0)}ms';
		seen = new Map();
		evals = 0;
		duplicates = 0;
		secColumns = 0;
		secPack = 0;
		secSim = 0;
		compiled = 0;
		secCompiled = 0;
		secBuild = 0;
		secRun = 0;
		prepares = 0;
		secBijection = 0;
		secPrepareRest = 0;
		jobs = 0;
		secJobs = 0;
		secJobMax = 0;
		lock.release();
		return line;
	}

	static function pct(part:Int, whole:Int):String {
		if (whole <= 0) return "0%";
		return Std.string(Math.round(1000.0 * part / whole) / 10) + "%";
	}

	static function ms(seconds:Float):String {
		return Std.string(Math.round(seconds * 1000.0 * 10) / 10);
	}
}
