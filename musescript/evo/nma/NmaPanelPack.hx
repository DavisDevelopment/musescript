package musescript.evo.nma;

import musescript.compile.StrategyWasmBackend;
import musescript.harness.PanelFeed;

/**
 * Materialize calendar-aligned `field@SYM` columns from a `PanelFeed` for columnar NMA —
 * same values as WASM feature-tape pack / `PortfolioBuiltins.observePanel`.
 *
 * No bags: callers only request closed OHLCV / fund / indicator-source keys that
 * `PanelInline` mapped from `SPanel` / packed `KPd("xs_rank")`, plus
 * `seriesKeysForPanelAction` for closed `PABagScanTop` / `PABagRankWeights`
 * score universes.
 *
 * «στήλη μία καθ' ἡμέραν· σύμπαν τὸ πάνελ.»
 */
class NmaPanelPack {
	/** Dense per-key columns (`close@AAA` → Array of length `panel.length()`). */
	public static function columns(panel:PanelFeed, keys:Array<String>):Map<String, Array<Float>> {
		var out = new Map<String, Array<Float>>();
		if (panel == null || keys == null) return out;
		for (k in keys) {
			if (k == null || k.length == 0 || out.exists(k)) continue;
			out.set(k, StrategyWasmBackend.panelColumnFromFeed(panel, k));
		}
		return out;
	}

	/** Merge packed panel columns into a tape field map (mutates `fields`). */
	public static function mergeInto(fields:Map<String, Array<Float>>, pack:Map<String, Array<Float>>):Void {
		if (fields == null || pack == null) return;
		for (k => col in pack) fields.set(k, col);
	}

	/** Content digest lanes over packed panel keys (sorted) for epoch / tape identity. */
	public static function digest(pack:Map<String, Array<Float>>):{a:Int, b:Int, hex:String} {
		var d = new musescript.evo.StructuralDigest();
		d.tag("P".code);
		if (pack == null) {
			d.finishWords();
			return { a: d.outA, b: d.outB, hex: musescript.evo.StructuralDigest.hexWords(d.outA, d.outB) };
		}
		var names = [for (k in pack.keys()) k];
		names.sort(Reflect.compare);
		d.int(names.length);
		for (name in names) {
			d.str(name);
			var col = pack.get(name);
			if (col == null) continue;
			var j = 0;
			while (j < col.length) {
				d.float(col[j]);
				j++;
			}
		}
		d.finishWords();
		return { a: d.outA, b: d.outB, hex: musescript.evo.StructuralDigest.hexWords(d.outA, d.outB) };
	}
}
