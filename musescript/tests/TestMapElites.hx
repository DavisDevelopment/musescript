package musescript.tests;

import utest.Test;
import utest.Assert;
import musescript.evo.MapElites;
import musescript.evo.MapElites.EliteArchive;
import musescript.evo.Fitness;
import musescript.evo.BoolNode;
import musescript.evo.ScalarNode;
import musescript.evo.StrategyGenome;
import musescript.harness.Fill;

/**
 * Regression coverage for MapElites.hx / EliteArchive -- the diversity-preservation machinery
 * added to fix the corpus-evo runs' real failure mode (raw-fitness selection converging the whole
 * population onto clones of ONE behavioral basin by generation 3, discarding every other kind of
 * strategy even though several coexisted at gen 0). Covers the descriptor math (derived from
 * `fills`, the same state every backend already produces via the shared OrderSim) and the
 * archive's niching/eviction contract in isolation from the full GraalWasm run.
 */
class TestMapElites extends Test {
	static function fill(kind:String, bar:Int):Fill
		return {kind: kind, bar: bar, price: 1.0, qty: 1.0, pnl: 0.0};

	static function dummyGenome(name:String):StrategyGenome {
		return {
			entryLong: BCmp(">", KConst(0.0), KConst(1.0)),
			entryShort: BCmp(">", KConst(0.0), KConst(1.0)),
			exitLong: BCmp(">", KConst(0.0), KConst(1.0)),
			exitShort: BCmp(">", KConst(0.0), KConst(1.0)),
			size: KConst(1.0),
			params: [],
			name: name,
			lineage: [],
			seedOrigin: null
		};
	}

	// ── descriptor math ───────────────────────────────────────────────────────────────────

	public function testDescribeFillsNoTradesIsNeutralDefault() {
		var d = MapElites.describeFills([], 500);
		Assert.floatEquals(0.0, d.avgHold);
		Assert.floatEquals(0.5, d.longFrac);
		var d2 = MapElites.describeFills(null, 500);
		Assert.floatEquals(0.0, d2.avgHold);
		Assert.floatEquals(0.5, d2.longFrac);
	}

	public function testDescribeFillsAllLongRoundTripsComputesHoldAndBias() {
		// long@10, flat@15 (hold 5); long@30, flat@50 (hold 20) -- pure long, avg hold = 12.5.
		var fills = [fill("long", 10), fill("flat", 15), fill("long", 30), fill("flat", 50)];
		var d = MapElites.describeFills(fills, 500);
		Assert.floatEquals(12.5, d.avgHold);
		Assert.floatEquals(1.0, d.longFrac);
	}

	public function testDescribeFillsMixedLongShortBias() {
		var fills = [fill("long", 0), fill("flat", 4), fill("short", 10), fill("flat", 14),
			fill("short", 20), fill("flat", 24)];
		var d = MapElites.describeFills(fills, 500);
		Assert.floatEquals(4.0, d.avgHold); // every round trip held exactly 4 bars
		Assert.floatEquals(1 / 3, d.longFrac); // 1 long entry out of 3 directional entries
	}

	public function testDescribeFillsHandlesSameBarReversalWithoutNegativeHold() {
		// long@5, then (same-bar reversal) flat@5, short@5 -- OrderSim always emits the flat BEFORE
		// the reversing entry (see executeLong/executeShort), so this is the real shape a same-bar
		// flip produces, not a hypothetical.
		var fills = [fill("long", 5), fill("flat", 5), fill("short", 5), fill("flat", 9)];
		var d = MapElites.describeFills(fills, 500);
		Assert.isTrue(d.avgHold >= 0, "hold must never go negative");
	}

	// ── binning ────────────────────────────────────────────────────────────────────────────

	public function testBinTradeFreqMonotonicBuckets() {
		Assert.equals(0, MapElites.binTradeFreq(0.001));
		Assert.equals(1, MapElites.binTradeFreq(0.02));
		Assert.equals(2, MapElites.binTradeFreq(0.10));
		Assert.equals(3, MapElites.binTradeFreq(0.50));
	}

	public function testBinBiasThreeWay() {
		Assert.equals(0, MapElites.binBias(0.1)); // short-dominant
		Assert.equals(1, MapElites.binBias(0.5)); // mixed
		Assert.equals(2, MapElites.binBias(0.9)); // long-dominant
	}

	// ── archive niching contract ───────────────────────────────────────────────────────────

	public function testArchiveKeepsBestPerCellNotBestOverall() {
		var archive = new EliteArchive();
		var scalper = dummyGenome("scalper");
		var swinger = dummyGenome("swinger");
		// Two DIFFERENT cells (trade-freq bin differs) -- a naive best-overall selector would keep
		// only `scalper` (higher fitness); MAP-Elites must keep BOTH, one per niche.
		Assert.isTrue(archive.offer(scalper, 0.9, "3_0_1"));
		Assert.isTrue(archive.offer(swinger, 0.3, "0_2_1"));
		Assert.equals(2, archive.size());
		var names = [for (g in archive.elites()) g.name];
		Assert.isTrue(names.indexOf("scalper") >= 0);
		Assert.isTrue(names.indexOf("swinger") >= 0);
	}

	public function testArchiveOnlyEvictsOnStrictImprovement() {
		var archive = new EliteArchive();
		var incumbent = dummyGenome("incumbent");
		var challenger = dummyGenome("challenger");
		Assert.isTrue(archive.offer(incumbent, 0.5, "1_1_1"));
		// A worse offer to the SAME cell must not evict the incumbent.
		Assert.isFalse(archive.offer(challenger, 0.4, "1_1_1"));
		Assert.equals(1, archive.size());
		Assert.equals("incumbent", archive.elites()[0].name);
		// A strictly better offer DOES evict.
		var better = dummyGenome("better");
		Assert.isTrue(archive.offer(better, 0.6, "1_1_1"));
		Assert.equals(1, archive.size());
		Assert.equals("better", archive.elites()[0].name);
	}

	public function testArchiveRejectsInvalidFitness() {
		var archive = new EliteArchive();
		Assert.isFalse(archive.offer(dummyGenome("bad"), Fitness.NEG_INF, "0_0_0"));
		Assert.isFalse(archive.offer(dummyGenome("nan"), Math.NaN, "0_0_0"));
		Assert.equals(0, archive.size());
	}

	public function testArchiveSummarySortedByKey() {
		var archive = new EliteArchive();
		archive.offer(dummyGenome("b"), 0.1, "2_0_0");
		archive.offer(dummyGenome("a"), 0.1, "0_0_0");
		var s = archive.summary();
		Assert.equals(2, s.length);
		Assert.equals("0_0_0", s[0].key);
		Assert.equals("2_0_0", s[1].key);
	}
}
