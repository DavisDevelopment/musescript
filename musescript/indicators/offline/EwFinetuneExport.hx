package musescript.indicators.offline;

import musescript.harness.Bar;
import musescript.indicators.ew.EwGuidelines;
import musescript.indicators.ew.EwLattice;
import musescript.indicators.ew.EwPhiParams;
import musescript.indicators.geom.PivotPoint;
import musescript.indicators.geom.SwingGraph;

/**
 * Batch export of EW soft features for offline EwPhiParams finetune.
 * NEVER call from MuseIndicator.update().
 */
typedef EwFinetuneRow = {
	var bar:Int;
	var close:Float;
	var pivotBar:Int;
	var pivotPrice:Float;
	var pivotDir:Float;
	var hypLabel:String;
	var hypScore:Float;
	var w2OverW1:Float;
	var w4OverW3:Float;
	var w3OverW1:Float;
	var w2Hit:Float;
	var w4Hit:Float;
	var w3Hit:Float;
	var guidelineAlt:Float;
	var guidelineDepth:Float;
	var forwardReturn:Float;
}

typedef EwFinetuneExportOpts = {
	/** SwingGraph percent threshold (default 0.02). */
	var ?swingThreshold:Float;
	/** Forward-return horizon in bars (default 10). */
	var ?horizon:Int;
	/** Top-K lattice hypotheses (default 3). */
	var ?latticeK:Int;
	/** Params snapshot used for scoring (default EwPhiParams.current()). */
	var ?params:EwPhiParams;
}

class EwFinetuneExport {
	public var meta:Dynamic;
	public var rows:Array<EwFinetuneRow>;

	public function new() {
		rows = [];
		meta = {};
	}

	/**
	 * Walk historical bars, rebuild lattice on each confirmed pivot, emit one row per event.
	 */
	public function exportFromBars(bars:Array<Bar>, ?opts:EwFinetuneExportOpts):Int {
		rows = [];
		var o = opts != null ? opts : {};
		var thresh = o.swingThreshold != null ? o.swingThreshold : 0.02;
		var horizon = o.horizon != null ? o.horizon : 10;
		var k = o.latticeK != null ? o.latticeK : 3;
		var params = o.params != null ? o.params : EwPhiParams.current();
		var g = new SwingGraph(thresh, 32);
		var lat = new EwLattice(params, true);
		var n = bars.length;
		for (i in 0...n) {
			var b = bars[i];
			if (g.update(b) && g.pivotCount() >= 4) {
				lat.rebuild(g, k);
				if (lat.hypothesisCount() <= 0) continue;
				var top = lat.at(0);
				var scratch = lat.scratch();
				var take = lat.scratchLen();
				if (take < 4) continue;
				var off = top.offset;
				if (off + 3 >= take) off = take - 4;
				if (off < 0) continue;
				var row = buildRow(b, top, scratch, off, take, params, horizon, n);
				if (row != null) rows.push(row);
			}
		}
		meta = {
			horizon: horizon,
			swingThreshold: thresh,
			latticeK: k,
			barCount: n,
			rowCount: rows.length,
			paramsSnapshot: PhiParamsDump.toObject(params)
		};
		return rows.length;
	}

	function buildRow(
		bar:Bar,
		top:Dynamic,
		scratch:haxe.ds.Vector<PivotPoint>,
		off:Int,
		take:Int,
		params:EwPhiParams,
		horizon:Int,
		nBars:Int
	):EwFinetuneRow {
		var w2o = Math.NaN;
		var w4o = Math.NaN;
		var w3o = Math.NaN;
		var w2h = 0.0;
		var w4h = 0.0;
		var w3h = 0.0;
		var gAlt = 0.5;
		var gDepth = 0.5;
		if (top.waveCount >= 5 && off + 5 < take) {
			var p0 = scratch[off];
			var p1 = scratch[off + 1];
			var p2 = scratch[off + 2];
			var p3 = scratch[off + 3];
			var p4 = scratch[off + 4];
			var w1 = Math.abs(p1.price - p0.price);
			var w2 = Math.abs(p2.price - p1.price);
			var w3 = Math.abs(p3.price - p2.price);
			var w4 = Math.abs(p4.price - p3.price);
			if (w1 > 0) {
				w2o = w2 / w1;
				w2h = params.bestHit(w2o, params.w2RetraceTargets, params.w2RetraceN);
				w3o = w3 / w1;
				w3h = params.bestHit(w3o, params.w3ExtTargets, params.w3ExtN);
			}
			if (w3 > 0) {
				w4o = w4 / w3;
				w4h = params.bestHit(w4o, params.w4RetraceTargets, params.w4RetraceN);
			}
			gAlt = EwGuidelines.alternationImpulse(scratch, off, params);
			gDepth = EwGuidelines.depthSoft(w2o, params);
		} else if (off + 3 < take) {
			var a = scratch[off];
			var b = scratch[off + 1];
			var c = scratch[off + 2];
			var legA = Math.abs(b.price - a.price);
			if (legA > 0) {
				w2o = Math.abs(c.price - b.price) / legA;
				w2h = params.bestHit(w2o, params.zigBTargets, params.zigBTargetsN);
				gDepth = EwGuidelines.depthSoft(w2o, params);
			}
		}
		var pivot = scratch[take - 1];
		return {
			bar: bar.index,
			close: bar.close,
			pivotBar: pivot.bar,
			pivotPrice: pivot.price,
			pivotDir: pivot.direction,
			hypLabel: top.label,
			hypScore: top.score,
			w2OverW1: w2o,
			w4OverW3: w4o,
			w3OverW1: w3o,
			w2Hit: w2h,
			w4Hit: w4h,
			w3Hit: w3h,
			guidelineAlt: gAlt,
			guidelineDepth: gDepth,
			forwardReturn: Math.NaN
		};
	}

	/** Recompute forward returns from the full close series (call after exportFromBars). */
	public function fillForwardReturns(closes:Array<Float>, ?horizon:Int):Void {
		var h = horizon != null ? horizon : (meta.horizon != null ? meta.horizon : 10);
		for (i in 0...rows.length) {
			var r = rows[i];
			var j = r.bar + h;
			if (j < closes.length && r.bar >= 0 && Math.isFinite(closes[r.bar]) && Math.isFinite(closes[j])) {
				var c0 = closes[r.bar];
				if (Math.abs(c0) > 1e-12)
					rows[i].forwardReturn = (closes[j] - c0) / c0;
			}
		}
		meta.horizon = h;
	}

	public function toObject():Dynamic {
		return { meta: meta, rows: rows };
	}

	public function toJson(?pretty:Bool):String {
		return haxe.Json.stringify(toObject(), pretty ? "  " : null);
	}

	#if (sys || node)
	public function saveJson(path:String, ?pretty:Bool = true):Void {
		sys.io.File.saveContent(path, toJson(pretty) + "\n");
	}

	public static function loadJson(path:String):EwFinetuneExport {
		var raw:haxe.DynamicAccess<Dynamic> = haxe.Json.parse(sys.io.File.getContent(path));
		var ex = new EwFinetuneExport();
		ex.meta = raw.get("meta");
		ex.rows = [];
		var rs:Array<Dynamic> = cast raw.get("rows");
		if (rs != null) {
			for (row in rs) {
				ex.rows.push({
					bar: row.bar,
					close: row.close,
					pivotBar: row.pivotBar,
					pivotPrice: row.pivotPrice,
					pivotDir: row.pivotDir,
					hypLabel: row.hypLabel,
					hypScore: row.hypScore,
					w2OverW1: row.w2OverW1,
					w4OverW3: row.w4OverW3,
					w3OverW1: row.w3OverW1,
					w2Hit: row.w2Hit,
					w4Hit: row.w4Hit,
					w3Hit: row.w3Hit,
					guidelineAlt: row.guidelineAlt,
					guidelineDepth: row.guidelineDepth,
					forwardReturn: row.forwardReturn
				});
			}
		}
		return ex;
	}
	#end

	/** Synthetic bull-impulse fixture for smoke tests. */
	public static function syntheticBars():Array<Bar> {
		var out:Array<Bar> = [];
		var barI = 0;
		inline function push(px:Float) {
			out.push({
				open: px, high: px, low: px, close: px, volume: 1.0,
				time: barI * 1.0, index: barI
			});
			barI++;
		}
		push(100);
		for (i in 0...5) push(100 + i);
		push(110);
		for (i in 0...3) push(110 - i);
		push(105);
		for (i in 0...5) push(105 + i * 3);
		push(120);
		for (i in 0...3) push(120 - i * 2);
		push(112);
		for (i in 0...5) push(112 + i * 3);
		push(125);
		for (i in 0...15) push(125 + i * 0.5);
		return out;
	}

	public static function exportSynthetic(?outPath:String):EwFinetuneExport {
		var bars = syntheticBars();
		var ex = new EwFinetuneExport();
		ex.exportFromBars(bars, { swingThreshold: 0.02, horizon: 5 });
		var closes = [for (b in bars) b.close];
		ex.fillForwardReturns(closes, 5);
		#if (sys || node)
		if (outPath != null && outPath != "") ex.saveJson(outPath);
		#end
		return ex;
	}
}
