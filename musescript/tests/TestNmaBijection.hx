package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.evo.BoolNode;
import musescript.evo.ScalarNode;
import musescript.evo.SeriesNode;
import musescript.evo.StrategyGenome;
import musescript.evo.Variation;
import musescript.evo.Canonical;
import musescript.evo.Expand;
import musescript.evo.nma.NmaBijection;
import musescript.evo.nma.NmaCanonical;
// NmaKind is NOT imported (even aliased): importing an enum brings its constructors into unqualified
// scope, and NmaKind's names mirror the evo enum constructors (SPrice/KConst/BCross/...) this test
// builds trees from -- collision. The few NmaKind references below are fully qualified instead.
import musescript.evo.nma.NmaNode;
import musescript.evo.nma.NmaBool;
import musescript.evo.nma.NmaScalar;

/**
 * P0 coverage for the Neural Muse AST substrate (spec `muse-lab/muse-nse/muse_nse_spec.md`): the
 * enum <-> NMA bijection must round-trip STRUCTURALLY EXACTLY. The whole dual-representation design
 * rests on this contract, so it's fuzzed hard (random genomes) and pinned on hand-built edge cases
 * (every constructor, nested indicator sources, transparent holes). Nothing here exercises NMA's
 * per-node state (credit/memo/kernel) yet -- P0 changes zero behavior; it only proves the two
 * representations are faithful mirrors.
 */
class TestNmaBijection extends Test {

	static function baseGenome(entryLong:BoolNode, ?size:ScalarNode):StrategyGenome {
		return {
			entryLong: entryLong,
			entryShort: BCmp(">", KConst(0.0), KConst(1.0)),
			exitLong: BCmp("<", KConst(2.0), KConst(1.0)),
			exitShort: BCmp(">", KConst(0.0), KConst(1.0)),
			size: size != null ? size : KConst(1.0),
			params: [],
			name: "rt"
		};
	}

	/** The core invariant: enum -> NMA -> enum leaves the canonical structural key unchanged. */
	static function assertRoundTrip(g:StrategyGenome, ?msg:String):Void {
		var back = NmaBijection.genomeToEnum(NmaBijection.genomeFromEnum(g));
		Assert.equals(Canonical.structuralKey(g), Canonical.structuralKey(back),
			(msg != null ? msg + ": " : "") + "structuralKey preserved");
		Assert.equals(Canonical.nodeCount(g), Canonical.nodeCount(back),
			(msg != null ? msg + ": " : "") + "nodeCount preserved");
		// Expanded source is what every backend actually compiles -- a stronger equality than the key.
		Assert.equals(Expand.expand(g), Expand.expand(back),
			(msg != null ? msg + ": " : "") + "expanded source preserved");
	}

	public function testHandBuiltCoversEveryConstructor() {
		// Series: SPrice + nested SInd(src:SInd(src:SPrice))
		var nestedSeries = SInd("ema", "close", 10,
			SInd("sma", "close", 20, SPrice("close")));
		// Scalar: KArith over KLookback(series) and KFeature, plus KConst/KParam under a hole
		var scalar = KArith("+",
			KLookback(nestedSeries, 3),
			KArith("*", KFeature("rsi"), KHole(KParam(0))));
		// Bool: every constructor incl BCross/BTrend/BNot/BAnd/BOr and a BHole wrapper
		var boolTree = BHole(BAnd(
			BOr(
				BCross("up", SPrice("close"), SInd("sma", "close", 50, null)),
				BTrend("down", SPrice("low"), 14)),
			BNot(BCmp(">=", KSeries(SPrice("high")), scalar))));

		var g:StrategyGenome = {
			entryLong: boolTree,
			entryShort: BNot(BHole(BCmp("<", KConst(-2.5), KParam(1)))),
			exitLong: BTrend("up", SInd("atr", "high", 7, null), 5),
			exitShort: BCross("down", SPrice("open"), SPrice("close")),
			size: KHole(KArith("/", KConst(1.0), KSeries(SPrice("volume")))),
			params: [
				{ name: "p0", defaultValue: 1.0, min: 0.0, max: 2.0, step: 0.1, tune: "grid" },
				{ name: "p1", defaultValue: -1.0, min: -5.0, max: 5.0, step: 0.5, tune: "" }
			],
			name: "kitchen-sink",
			lineage: ["a", "b"],
			seedOrigin: 42
		};
		assertRoundTrip(g, "kitchen-sink");
	}

	public function testHolesArePreservedNotUnwrapped() {
		// Holes are transparent to Canonical, so a key check alone can't prove preservation.
		// Inspect the NMA tree directly: the wrapper node must survive as an musescript.evo.nma.NmaKind.BHole/KHole.
		var g = baseGenome(BHole(BCmp(">", KConst(1.0), KConst(0.0))),
			KHole(KConst(3.0)));
		var nma = NmaBijection.genomeFromEnum(g);
		Assert.equals(musescript.evo.nma.NmaKind.BHole, nma.entryLong.kind, "BHole wrapper preserved on NMA side");
		Assert.equals(musescript.evo.nma.NmaKind.KHole, nma.size.kind, "KHole wrapper preserved on NMA side");
		// And it still round-trips exactly.
		assertRoundTrip(g, "holes");
	}

	public function testFreshNmaHasClearedPerNodeState() {
		var g = baseGenome(BCross("up", SPrice("close"), SInd("sma", "close", 20, null)));
		var nma = NmaBijection.genomeFromEnum(g);
		function checkClear(n:NmaNode):Void {
			Assert.equals(0.0, n.creditSum, "credit starts at 0");
			Assert.equals(0, n.creditN, "credit count starts at 0");
			Assert.equals(-1, n.evalEpoch, "eval epoch starts dirty");
			Assert.isNull(n.lastSeries, "no memo yet");
			Assert.isNull(n.structuralKey, "no memoized key yet");
			Assert.isNull(n.kernel, "no kernel yet");
			for (c in n.childNodes()) checkClear(c);
		}
		for (r in nma.roots()) checkClear(r);
	}

	public function testChildNodesMatchArity() {
		var g = baseGenome(BAnd(
			BCmp(">", KConst(1.0), KConst(0.0)),
			BNot(BTrend("up", SPrice("close"), 3))));
		var nma = NmaBijection.genomeFromEnum(g);
		Assert.equals(5, nma.roots().length, "genome exposes 5 roots");
		var and = nma.entryLong;
		Assert.equals(musescript.evo.nma.NmaKind.BAnd, and.kind);
		Assert.equals(2, and.childNodes().length, "BAnd has 2 children");
		Assert.equals(1, and.childNodes()[1].childNodes().length, "BNot has 1 child");
	}

	public function testRandomGenomeFuzzRoundTrips() {
		// Many independent random shapes across a range of depths -- the property test proper.
		for (seed in 0...120) {
			var v = new Variation(seed);
			var depth = 1 + (seed % 5);
			var g = v.randomGenome(depth);
			assertRoundTrip(g, 'random seed=$seed depth=$depth');
		}
	}

	public function testNmaCanonicalMatchesEnumCanonical() {
		// NMA-native keying/counting must be byte-identical to the enum Canonical, so the NMA
		// working-copy can drive EvoCache/Fitness directly. The bijection is the oracle.
		for (seed in 0...120) {
			var v = new Variation(seed);
			var g = v.randomGenome(1 + (seed % 5));
			var nma = NmaBijection.genomeFromEnum(g);
			Assert.equals(Canonical.structuralKey(g), NmaCanonical.structuralKey(nma),
				'structuralKey parity seed=$seed');
			Assert.equals(Canonical.nodeCount(g), NmaCanonical.nodeCount(nma),
				'nodeCount parity seed=$seed');
		}
	}

	public function testNmaCanonicalParityOnHolesAndNesting() {
		// The transparent cases (BHole/KHole contribute 0 to nodeCount; both are unwrapped in the
		// key) are exactly where a hand-rolled second implementation drifts -- pin them explicitly.
		var g:StrategyGenome = {
			entryLong: BHole(BAnd(
				BCross("up", SPrice("close"), SInd("ema", "close", 12, SInd("sma", "close", 26, null))),
				BNot(BCmp(">", KHole(KArith("+", KConst(1.0), KParam(0))), KSeries(SPrice("high")))))),
			entryShort: BCmp(">", KConst(0.0), KConst(1.0)),
			exitLong: BTrend("down", SPrice("low"), 9),
			exitShort: BCross("down", SPrice("open"), SPrice("close")),
			size: KHole(KLookback(SInd("rsi", "close", 14, null), 2)),
			params: [{ name: "p0", defaultValue: 1.0, min: 0.0, max: 2.0, step: 0.1, tune: "grid" }],
			name: "holes-and-nesting"
		};
		var nma = NmaBijection.genomeFromEnum(g);
		Assert.equals(Canonical.structuralKey(g), NmaCanonical.structuralKey(nma), "key parity");
		Assert.equals(Canonical.nodeCount(g), NmaCanonical.nodeCount(nma), "count parity");
	}

	public function testDoubleRoundTripIsIdempotent() {
		var v = new Variation(7);
		for (i in 0...20) {
			var g = v.randomGenome(3 + (i % 3));
			var once = NmaBijection.genomeToEnum(NmaBijection.genomeFromEnum(g));
			var twice = NmaBijection.genomeToEnum(NmaBijection.genomeFromEnum(once));
			Assert.equals(Canonical.structuralKey(once), Canonical.structuralKey(twice),
				'idempotent round-trip i=$i');
		}
	}

	public function testKNpRoundTripAndCanonicalParity() {
		var g = baseGenome(
			BCmp(">", KNp("mean", SPrice("close"), 5, null),
				KNp("dot", SPrice("close"), 3, SPrice("high"))),
			KNp("sum", SInd("sma", "close", 8, null), 4, null));
		var nma = NmaBijection.genomeFromEnum(g);
		var back = NmaBijection.genomeToEnum(nma);
		Assert.equals(Canonical.structuralKey(g), Canonical.structuralKey(back), "KNp structural round-trip");
		Assert.equals(Expand.expand(g), Expand.expand(back), "KNp Expand round-trip");
		Assert.equals(Canonical.structuralKey(g), NmaCanonical.structuralKey(nma), "KNp NmaCanonical key");
		Assert.equals(Canonical.nodeCount(g), NmaCanonical.nodeCount(nma), "KNp NmaCanonical count");
	}

	public function testKPdShiftRoundTripAndCanonicalParity() {
		var g = baseGenome(
			BCmp(">", KPd("shift", "close", 3, "", []), KConst(0.0)),
			KPd("shift", "high", 5, "", []));
		var nma = NmaBijection.genomeFromEnum(g);
		var back = NmaBijection.genomeToEnum(nma);
		Assert.equals(Canonical.structuralKey(g), Canonical.structuralKey(back), "KPd shift structural round-trip");
		Assert.equals(Expand.expand(g), Expand.expand(back), "KPd shift Expand round-trip");
		Assert.equals(Canonical.structuralKey(g), NmaCanonical.structuralKey(nma), "KPd shift NmaCanonical key");
		Assert.equals(Canonical.nodeCount(g), NmaCanonical.nodeCount(nma), "KPd shift NmaCanonical count");
	}

	public function testKPdXsRankRoundTripAndCanonicalParity() {
		var g = baseGenome(
			BCmp(">", KPd("xs_rank", "mom", 5, "AAA", ["AAA", "BBB"]), KConst(0.5)),
			KPd("xs_rank", "close", 0, "BBB", ["AAA", "BBB"]));
		var nma = NmaBijection.genomeFromEnum(g);
		var back = NmaBijection.genomeToEnum(nma);
		Assert.equals(Canonical.structuralKey(g), Canonical.structuralKey(back), "KPd xs_rank structural round-trip");
		Assert.equals(Expand.expand(g), Expand.expand(back), "KPd xs_rank Expand round-trip");
		Assert.equals(Canonical.structuralKey(g), NmaCanonical.structuralKey(nma), "KPd xs_rank NmaCanonical key");
		Assert.equals(Canonical.nodeCount(g), NmaCanonical.nodeCount(nma), "KPd xs_rank NmaCanonical count");
	}

	public function testKPdXsRankWideBijectionThrows() {
		var wide = [for (i in 0...65) 'S$i'];
		var g = baseGenome(
			BCmp(">", KPd("xs_rank", "mom", 5, "S0", wide), KConst(0.5)),
			KConst(1.0));
		var threw = false;
		try {
			NmaBijection.genomeFromEnum(g);
		} catch (e:Dynamic) {
			threw = Std.string(e).indexOf("nma-unsupported") >= 0;
		}
		Assert.isTrue(threw, "wide xs_rank must stay nma-unsupported at bijection");
	}
}
