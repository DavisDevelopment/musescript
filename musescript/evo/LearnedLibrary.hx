package musescript.evo;

import musescript.evo.TreeSurgery.GPath;
import musescript.evo.MapElites.EliteArchive;

/**
 * Process-wide learned bool motifs promoted from the MAP-Elites archive (Stitch-style library
 * learning, strangler-gated by `--learn-library`). Tags are `Canonical.boolStructuralKey`s;
 * `Variation.growBool` may emit `BHole(motif)` when the `boolLibrary` GrowthWeights category
 * fires — same hole contract as `CorpusSeed`'s `evolve(...)`.
 *
 * «νόμος καινός· ἀρχαῖον μέλος καινοτομεῖ.»
 */
class LearnedLibrary {
	static var motifs:Map<String, BoolNode> = new Map();

	public static function size():Int {
		var n = 0;
		for (_ in motifs.keys()) n++;
		return n;
	}

	public static function get(key:String):Null<BoolNode> return motifs.get(key);

	public static function clear():Void motifs = new Map();

	public static function keys():Array<String> return [for (k in motifs.keys()) k];

	/** Register / refresh a motif and ensure a tuner tag exists. */
	public static function promote(key:String, motif:BoolNode, ?tuner:GrowthWeights, ?weight:Float = 0.12):Void {
		if (key == null || key.length == 0 || motif == null) return;
		motifs.set(key, cloneBool(motif));
		if (tuner != null) tuner.ensureTag("boolLibrary", key, weight);
	}

	/**
	 * Mine frequent bool subtrees from archive elites. Scores candidates by support ×
	 * (1+|credit mean|). Returns number newly promoted this call.
	 *
	 * «Στίχοι παλαιοί· καινὴ φωνὴ ᾄδει.»
	 */
	public static function mineFromArchives(
		archives:Array<EliteArchive>,
		?tuner:GrowthWeights,
		?minSupport:Int = 2,
		?minNodes:Int = 2,
		?maxNodes:Int = 12,
		?maxPromote:Int = 8
	):Int {
		if (archives == null || archives.length == 0) return 0;
		var counts = new Map<String, Int>();
		var exemplars = new Map<String, BoolNode>();
		var cellsSeen = new Map<String, Map<String, Bool>>(); // motif -> set of archive cell keys
		for (arch in archives) {
			if (arch == null) continue;
			for (e in arch.entries()) {
				function consider(root:BoolNode):Void {
					var bag:Array<{path:GPath, node:BoolNode}> = [];
					TreeSurgery.collectBool(root, [], bag, true);
					for (item in bag) {
						var n = item.node;
						var c = Canonical.boolNodeCount(n);
						if (c < minNodes || c > maxNodes) continue;
						var k = Canonical.boolStructuralKey(n);
						counts.set(k, (counts.exists(k) ? counts.get(k) : 0) + 1);
						if (!exemplars.exists(k)) exemplars.set(k, n);
						var cells = cellsSeen.get(k);
						if (cells == null) { cells = new Map(); cellsSeen.set(k, cells); }
						cells.set(e.key, true);
					}
				}
				consider(e.cell.genome.entryLong);
				consider(e.cell.genome.entryShort);
				consider(e.cell.genome.exitLong);
				consider(e.cell.genome.exitShort);
			}
		}
		var scored:Array<{key:String, score:Float}> = [];
		for (k => cnt in counts) {
			var cellN = 0;
			var cm = cellsSeen.get(k);
			if (cm != null) for (_ in cm.keys()) cellN++;
			if (cnt < minSupport || cellN < 1) continue;
			// Prefer motifs that appear in ≥2 behaviorally distinct cells when possible.
			var credit = Math.abs(musescript.evo.nma.NmaCreditBank.mean(k));
			var score = cnt * (1.0 + credit) * (cellN >= 2 ? 1.5 : 1.0);
			scored.push({key: k, score: score});
		}
		scored.sort((a, b) -> a.score < b.score ? 1 : a.score > b.score ? -1 : 0);
		var added = 0;
		for (i in 0...Std.int(Math.min(maxPromote, scored.length))) {
			var k = scored[i].key;
			if (motifs.exists(k)) continue;
			promote(k, exemplars.get(k), tuner);
			added++;
		}
		return added;
	}

	/** Deep clone — genomes are immutable values; library must not alias elite trees. */
	public static function cloneBool(n:BoolNode):BoolNode {
		return switch (n) {
			case BCross(dir, a, b): BCross(dir, cloneSeries(a), cloneSeries(b));
			case BCmp(op, a, b): BCmp(op, cloneScalar(a), cloneScalar(b));
			case BTrend(dir, s, w): BTrend(dir, cloneSeries(s), w);
			case BAnd(a, b): BAnd(cloneBool(a), cloneBool(b));
			case BOr(a, b): BOr(cloneBool(a), cloneBool(b));
			case BNot(a): BNot(cloneBool(a));
			case BHole(inner): BHole(cloneBool(inner));
			case BFeature(src): BFeature(src); // opaque leaf: immutable string, safe to share
		};
	}

	static function cloneScalar(n:ScalarNode):ScalarNode {
		return switch (n) {
			case KConst(v): KConst(v);
			case KParam(i): KParam(i);
			case KFeature(name): KFeature(name);
			case KSeries(s): KSeries(cloneSeries(s));
			case KLookback(s, k): KLookback(cloneSeries(s), k);
			case KNp(op, a, w, b):
				KNp(op, cloneSeries(a), w, b != null ? cloneSeries(b) : null);
			case KPd(op, kind, w, sym, syms):
				KPd(op, kind, w, sym, syms.copy());
			case KArith(op, a, b): KArith(op, cloneScalar(a), cloneScalar(b));
			case KHole(inner): KHole(cloneScalar(inner));
		};
	}

	static function cloneSeries(n:SeriesNode):SeriesNode {
		return switch (n) {
			case SPrice(f): SPrice(f);
			case SProj(n, f): SProj(n, f);
			case SPanel(kind, sym, field, window): SPanel(kind, sym, field, window);
			case SInd(name, field, window, src):
				SInd(name, field, window, src != null ? cloneSeries(src) : null);
		};
	}
}
