package musescript.evo.nma;

import musescript.evo.BoolNode;
import musescript.evo.ScalarNode;
import musescript.evo.SeriesNode;
import musescript.evo.StrategyGenome;
// Explicit module imports pull in each family's SECONDARY types (NmaSPrice, NmaKArith, NmaBHole,
// ...) -- same-package auto-import only brings each module's PRIMARY type into scope.
import musescript.evo.nma.NmaSeries;
import musescript.evo.nma.NmaScalar;
import musescript.evo.nma.NmaBool;

/**
 * The exact enum <-> NMA bijection -- the load-bearing contract of the dual-representation design
 * (spec `muse-lab/muse-nse/muse_nse_spec.md` §3.2). The enum forms stay canonical; NMA is the
 * stateful working copy; these functions are the ONLY sanctioned crossing between them.
 *
 * Contract: `toEnum(fromEnum(x))` is STRUCTURALLY IDENTICAL to `x` for every node and genome --
 * including transparent `BHole`/`KHole` wrappers (preserved, not unwrapped) -- so a round-trip
 * changes nothing `Canonical.structuralKey`/`nodeCount`/`Expand` can observe. `TestNmaBijection`
 * property-tests this against `Variation.randomGenome` fuzzing plus hand-built edge cases.
 *
 * `fromEnum` mints fresh NMA nodes with memo/kernel cleared; local credit is seeded from
 * `NmaCreditBank` when the shape has history (spec §6b priors). `toEnum` drops working state.
 * Round-tripping is therefore lossy for memo/kernel by design and lossless for logical structure.
 *
 * «Σίβυλλα μαίνεται· θεὸς ἐν αὐτῇ λαλεῖ.»
 */
class NmaBijection {

	// ---------- enum -> NMA ----------

	public static function seriesFromEnum(n:SeriesNode):NmaSeries {
		return switch (n) {
			case SPrice(field): new NmaSPrice(field);
			case SInd(name, field, window, src):
				new NmaSInd(name, field, window, src != null ? seriesFromEnum(src) : null);
		};
	}

	public static function scalarFromEnum(n:ScalarNode):NmaScalar {
		return switch (n) {
			case KConst(v): new NmaKConst(v);
			case KParam(idx): new NmaKParam(idx);
			case KArith(op, a, b): new NmaKArith(op, scalarFromEnum(a), scalarFromEnum(b));
			case KSeries(s): new NmaKSeries(seriesFromEnum(s));
			case KLookback(s, k): new NmaKLookback(seriesFromEnum(s), k);
			case KFeature(name): new NmaKFeature(name);
			case KHole(inner): new NmaKHole(scalarFromEnum(inner));
		};
	}

	public static function boolFromEnum(n:BoolNode):NmaBool {
		var out:NmaBool = switch (n) {
			case BCross(dir, a, b): new NmaBCross(dir, seriesFromEnum(a), seriesFromEnum(b));
			case BCmp(op, a, b): new NmaBCmp(op, scalarFromEnum(a), scalarFromEnum(b));
			case BTrend(dir, s, w): new NmaBTrend(dir, seriesFromEnum(s), w);
			case BAnd(a, b): new NmaBAnd(boolFromEnum(a), boolFromEnum(b));
			case BOr(a, b): new NmaBOr(boolFromEnum(a), boolFromEnum(b));
			case BNot(a): new NmaBNot(boolFromEnum(a));
			case BHole(inner): new NmaBHole(boolFromEnum(inner));
		};
		// §6b shape prior: seed local credit from durable bank so working copies aren't cold-start.
		NmaCreditBank.seedNodeFromBank(out, musescript.evo.Canonical.boolStructuralKey(n));
		return out;
	}

	public static function genomeFromEnum(g:StrategyGenome):NmaGenome {
		return {
			entryLong: boolFromEnum(g.entryLong),
			entryShort: boolFromEnum(g.entryShort),
			exitLong: boolFromEnum(g.exitLong),
			exitShort: boolFromEnum(g.exitShort),
			size: scalarFromEnum(g.size),
			// params are immutable value objects on the enum side -- share the same array; the enum
			// genome is not mutated in place anywhere the NMA copy is live.
			params: g.params,
			name: g.name,
			lineage: g.lineage,
			seedOrigin: g.seedOrigin
		};
	}

	// ---------- NMA -> enum ----------

	public static function seriesToEnum(n:NmaSeries):SeriesNode {
		return switch (n.kind) {
			case SPrice: SPrice((cast n : NmaSPrice).field);
			case SInd:
				var s = (cast n : NmaSInd);
				SInd(s.name, s.field, s.window, s.src != null ? seriesToEnum(s.src) : null);
			default: throw 'NmaBijection.seriesToEnum: non-series kind ${n.kind}';
		};
	}

	public static function scalarToEnum(n:NmaScalar):ScalarNode {
		return switch (n.kind) {
			case KConst: KConst((cast n : NmaKConst).v);
			case KParam: KParam((cast n : NmaKParam).idx);
			case KArith:
				var a = (cast n : NmaKArith);
				KArith(a.op, scalarToEnum(a.a), scalarToEnum(a.b));
			case KSeries: KSeries(seriesToEnum((cast n : NmaKSeries).s));
			case KLookback:
				var l = (cast n : NmaKLookback);
				KLookback(seriesToEnum(l.s), l.n);
			case KFeature: KFeature((cast n : NmaKFeature).name);
			case KHole: KHole(scalarToEnum((cast n : NmaKHole).inner));
			default: throw 'NmaBijection.scalarToEnum: non-scalar kind ${n.kind}';
		};
	}

	public static function boolToEnum(n:NmaBool):BoolNode {
		return switch (n.kind) {
			case BCross:
				var c = (cast n : NmaBCross);
				BCross(c.dir, seriesToEnum(c.a), seriesToEnum(c.b));
			case BCmp:
				var c = (cast n : NmaBCmp);
				BCmp(c.op, scalarToEnum(c.a), scalarToEnum(c.b));
			case BTrend:
				var t = (cast n : NmaBTrend);
				BTrend(t.dir, seriesToEnum(t.s), t.window);
			case BAnd:
				var a = (cast n : NmaBAnd);
				BAnd(boolToEnum(a.a), boolToEnum(a.b));
			case BOr:
				var o = (cast n : NmaBOr);
				BOr(boolToEnum(o.a), boolToEnum(o.b));
			case BNot: BNot(boolToEnum((cast n : NmaBNot).a));
			case BHole: BHole(boolToEnum((cast n : NmaBHole).inner));
			default: throw 'NmaBijection.boolToEnum: non-bool kind ${n.kind}';
		};
	}

	public static function genomeToEnum(g:NmaGenome):StrategyGenome {
		return {
			entryLong: boolToEnum(g.entryLong),
			entryShort: boolToEnum(g.entryShort),
			exitLong: boolToEnum(g.exitLong),
			exitShort: boolToEnum(g.exitShort),
			size: scalarToEnum(g.size),
			params: g.params,
			name: g.name,
			lineage: g.lineage,
			seedOrigin: g.seedOrigin
		};
	}
}
