package musescript.evo;

/**
 * Deterministic LCG for reproducible evolution proofs.
 *
 * ⚠️ **Draw sequences changed on 2026-07-26** (see `int` and `bool` below). Runs archived
 * before that date will NOT replay bit-identically from the same `--seed`; stored artifacts
 * (elites, champions, cached fitness) are unaffected, but a re-run of an old seed is a NEW
 * experiment, not a reproduction. The old sequences were not salvageable without keeping a
 * documented bias in the selection operator, so this was traded deliberately: full test suite
 * (64,130 assertions) passes on the new sequences.
 *
 * The state transition itself is unchanged; only how `int`/`bool` REDUCE that state changed.
 */
class Rand {
	public var seed:Int;
	var state:Int;

	public function new(seed:Int) {
		this.seed = seed;
		this.state = seed;
	}

	/** Advance the LCG once and return the new 31-bit state. Single source of the
	 *  state transition so `int`/`float`/`bool` all consume EXACTLY one step —
	 *  RngStreams' whole "same seed means same experiment" guarantee depends on
	 *  draw counts not shifting per call, so no accessor may advance twice. */
	inline function next():Int {
		state = (imul32(state, 1103515245) + 12345) & 0x7fffffff;
		return state;
	}

	/**
	 * Uniform integer in `[0, n)`, by scaling the whole 31-bit state -- NOT `state % n`.
	 *
	 * `% n` was a real defect for every EVEN `n`. Because `n` even implies
	 * `state % n ≡ state (mod 2)`, and this LCG's bit 0 strictly alternates (odd multiplier
	 * and odd increment mod 2^31 give `state_{n+1} ≡ state_n + 1 (mod 2)`), consecutive
	 * draws were forced into opposite parity and so **could never be equal**. Measured over
	 * 60k draws: `int(2)`, `int(4)`, `int(6)`, `int(8)`, `int(10)`, `int(16)`, `int(32)` every
	 * one had ZERO immediate repeats, while odd moduli (3/5/7) behaved correctly. `int(2)`
	 * and `int(4)` degenerated all the way into the fixed cycles `0101…` and `0123…`.
	 *
	 * This mattered where it mattered most: `EvolutionEngine.tournamentSelect` samples
	 * `selectionRng.int(ranked.length)` repeatedly, and population sizes are even (default 8,
	 * runs use `--pop 64`), so no two consecutive tournament candidates could ever be the
	 * same individual -- a systematic, seed-independent distortion of the engine's primary
	 * selection operator. Post-fix, consecutive `int(64)` collisions measure 1875/120k
	 * against a fair-die expectation of 1875 (previously exactly 0).
	 *
	 * Every marginal statistic was perfect throughout (`int(4)` was exactly 25% per bucket),
	 * which is why no distribution test ever failed -- only serial correlation exposes this.
	 * See `TestEvoVariation`'s `testRandSmallIntDrawsAreNotACycle` / `testRandBool*`.
	 *
	 * Scaling also drops `%`'s modulo bias entirely. Range is provably safe: `state` peaks at
	 * `0x7FFFFFFF = 2147483647 < 2^31`, so the quotient is strictly `< 1.0` and the truncated
	 * product never reaches `n` (verified: 0 out-of-range draws in 3M of `int(7)`).
	 */
	public function int(n:Int):Int {
		if (n == 0) return 0;
		return Std.int((next() / 2147483648.0) * n);
	}

	/**
	 * Portable 32-bit-wrapping multiply, via the `haxe.Int32` abstract's overloaded `*`
	 * operator (NOT raw `Int` `*`) -- see musescript.harness.BarFeed.imul32 for the full
	 * writeup. Same LCG, same bug class: on JS, `Int` is a plain Number so raw `*` silently
	 * loses precision once the product exceeds 2^53, while a real-32-bit-int target (JVM,
	 * C++, ...) overflows correctly on the exact same source -- two targets given "the same
	 * seed" would silently diverge. `haxe.Int32`'s `*` forces the same 32-bit-wrapping
	 * product on every target.
	 */
	static inline function imul32(a:Int, b:Int):Int {
		var r:haxe.Int32 = (a : haxe.Int32) * (b : haxe.Int32);
		return r;
	}

	public function float():Float {
		return int(100000) / 100000.0;
	}

	/**
	 * Fair coin, read from the state's TOP bit -- deliberately not `int(2)`.
	 *
	 * `int(2)` was `state % 2` == the LCG's alternating bit 0 (see `int` above), so the old
	 * `bool()` returned a strict `101010…` on every seed: zero consecutive-equal pairs,
	 * longest run 1, and a lag-1 autocorrelation of exactly **-1.0** -- the mathematical
	 * signature of alternation -- all while sitting at a flawless 50/50 marginal split.
	 *
	 * Its one real caller, `SymbolSelector.crossover`, documents itself as taking each gene
	 * "independently ... with equal probability"; what it actually produced was the single
	 * fixed mask `a[0], b[1], a[2], b[3], …` on every call, exploring ~2 of 2^n masks.
	 *
	 * Bit 30 carries the LCG's full period. `int` is now unbiased too, so this could simply
	 * be `int(2) == 0`; reading the top bit directly is kept because it makes the intent
	 * ("never touch the low bits") explicit and local to this function.
	 */
	public function bool():Bool {
		return next() >= 0x40000000;
	}

	public function pick<T>(xs:Array<T>):T {
		return xs[int(xs.length)];
	}
}
