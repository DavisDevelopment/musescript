package musescript.evo.nma;

import musescript.evo.TreeSurgery.GPath;
import musescript.evo.TreeSurgery.GStep;
import musescript.evo.TreeSurgery.GStep.StepA;
import musescript.evo.nma.NmaBool;

/**
 * Path-based bool surgery on the NMA working copy. Rebuilds ONLY the spine from root to the
 * edit site (new node objects); sibling subtrees keep their identity — and therefore their
 * `lastSeries` / `evalEpoch` memos — so a re-eval after ablation recomputes the dirty path and
 * memo-hits everything else (spec §6b dirty-flag incremental re-eval).
 *
 * Mirrors `TreeSurgery.replaceBoolWithBool` path semantics (`StepA`/`StepB`) so `CatalogEntry.path`
 * from `Variation.buildCatalog` applies unchanged.
 *
 * «δεσποίνας δὲ ὑπὸ κόλπον ἔδυν χθονίας βασιλείας.»
 */
class NmaSurgery {

	/** Replace the bool at `path` under `n`, returning a new root. `path == []` → `repl`.
	 *
	 * «Βάκχου λύσις· λύρας χορδαὶ θρόον ἵεσαν.»
	 */
	public static function replaceBool(n:NmaBool, path:GPath, repl:NmaBool):NmaBool {
		return replaceBoolAt(n, path, repl, 0);
	}

	static function replaceBoolAt(n:NmaBool, path:GPath, repl:NmaBool, idx:Int):NmaBool {
		if (idx >= path.length) return repl;
		var step = path[idx];
		return switch (n.kind) {
			case BAnd:
				var a = (cast n : NmaBAnd);
				step == StepA
					? new NmaBAnd(replaceBoolAt(a.a, path, repl, idx + 1), a.b)
					: new NmaBAnd(a.a, replaceBoolAt(a.b, path, repl, idx + 1));
			case BOr:
				var o = (cast n : NmaBOr);
				step == StepA
					? new NmaBOr(replaceBoolAt(o.a, path, repl, idx + 1), o.b)
					: new NmaBOr(o.a, replaceBoolAt(o.b, path, repl, idx + 1));
			case BNot:
				var t = (cast n : NmaBNot);
				new NmaBNot(replaceBoolAt(t.a, path, repl, idx + 1));
			case BHole:
				var h = (cast n : NmaBHole);
				new NmaBHole(replaceBoolAt(h.inner, path, repl, idx + 1));
			default:
				throw 'NmaSurgery.replaceBool: kind ${n.kind} has no bool child for path step $idx';
		};
	}

	/** Bool root for genome slot 0..3.
	 *
	 * «νάρθηξ ἀνθεῖ· κισσὸς στέφει κρόταφον.»
	 */
	public static function boolRoot(g:NmaGenome, slot:Int):NmaBool {
		return switch (slot) {
			case 0: g.entryLong;
			case 1: g.entryShort;
			case 2: g.exitLong;
			case 3: g.exitShort;
			default: throw 'NmaSurgery.boolRoot: slot $slot is not a bool slot';
		};
	}

	public static function setBoolRoot(g:NmaGenome, slot:Int, v:NmaBool):Void {
		switch (slot) {
			case 0: g.entryLong = v;
			case 1: g.entryShort = v;
			case 2: g.exitLong = v;
			case 3: g.exitShort = v;
			default: throw 'NmaSurgery.setBoolRoot: slot $slot is not a bool slot';
		}
	}

	/** Walk `path` under `root` (StepA/StepB). Shared by attribution / RDO.
	 *
	 * «Ἀριάδνη νῆμα· λαβύρινθος λύει.»
	 */
	public static function nodeAtBool(root:NmaBool, path:GPath):NmaBool {
		var n:NmaBool = root;
		for (step in path) {
			n = switch (n.kind) {
				case BAnd:
					var a = (cast n : NmaBAnd);
					step == StepA ? a.a : a.b;
				case BOr:
					var o = (cast n : NmaBOr);
					step == StepA ? o.a : o.b;
				case BNot:
					(cast n : NmaBNot).a;
				case BHole:
					(cast n : NmaBHole).inner;
				default:
					return n;
			};
		}
		return n;
	}
}
