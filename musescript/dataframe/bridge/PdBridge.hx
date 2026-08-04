package musescript.dataframe.bridge;

import musescript.dataframe.AnyIndex;
import musescript.dataframe.DataFrame;
import musescript.dataframe.Index;
import musescript.dataframe.Series;
import musescript.harness.Bar;
import musescript.harness.PanelFeed;
import musescript.ndarray.NdArrayF64;
import musescript.ndarray.NdBridge;

/**
 * Bridges from Bar / PanelFeed / NdBridge into Series / DataFrame (copy for M0).
 */
class PdBridge {
	/** Single aux/field column across bars → Series (copy via NdBridge). */
	public static function fromBarDataColumn(bars:Array<Bar>, key:String, ?name:String):Series {
		var vals = NdBridge.fromBarDataColumn(bars, key);
		var times = timesFromBars(bars);
		var idx:AnyIndex = times != null ? Index.fromFloats(times) : Index.range(vals.size);
		return Series.create(vals, idx, name != null ? name : key);
	}

	/** OHLCV (+ time index) from a bar list. */
	public static function fromBars(bars:Array<Bar>):DataFrame {
		if (bars == null || bars.length == 0) return DataFrame.empty();
		var n = bars.length;
		var o = NdArrayF64.empty([n]);
		var h = NdArrayF64.empty([n]);
		var l = NdArrayF64.empty([n]);
		var c = NdArrayF64.empty([n]);
		var v = NdArrayF64.empty([n]);
		var times:Array<Float> = [];
		for (i in 0...n) {
			var b = bars[i];
			if (b == null) {
				o.setFlat(i, Math.NaN);
				h.setFlat(i, Math.NaN);
				l.setFlat(i, Math.NaN);
				c.setFlat(i, Math.NaN);
				v.setFlat(i, Math.NaN);
				times.push(i * 1.0);
			} else {
				o.setFlat(i, b.open);
				h.setFlat(i, b.high);
				l.setFlat(i, b.low);
				c.setFlat(i, b.close);
				v.setFlat(i, b.volume);
				times.push(b.time);
			}
		}
		var map = new Map<String, NdArrayF64>();
		map.set("open", o);
		map.set("high", h);
		map.set("low", l);
		map.set("close", c);
		map.set("volume", v);
		return DataFrame.fromColumns(map, Index.fromFloats(times), ["open", "high", "low", "close", "volume"]);
	}

	/**
	 * Panel → wide DataFrame (copy). Default fields: OHLCV.
	 * One field → columns = symbols; multiple → `field@SYM`.
	 */
	public static function fromPanelFeed(panel:PanelFeed, ?fields:Array<String>):DataFrame {
		if (panel == null) return DataFrame.empty();
		var n = panel.length();
		if (n == 0) return DataFrame.empty();
		var flds = fields;
		if (flds == null || flds.length == 0)
			flds = ["open", "high", "low", "close", "volume"];
		var syms = panel.symbols != null ? panel.symbols : [];
		var idx = Index.fromFloats(panel.times != null ? panel.times.copy() : [for (i in 0...n) i * 1.0]);
		var map = new Map<String, NdArrayF64>();
		var order:Array<String> = [];
		var multi = flds.length > 1;
		for (field in flds) {
			for (sym in syms) {
				var colName = multi ? (field + "@" + sym) : sym;
				var col = NdArrayF64.empty([n]);
				for (t in 0...n) col.setFlat(t, panelValue(panel, field, sym, t));
				map.set(colName, col);
				order.push(colName);
			}
		}
		return DataFrame.fromColumns(map, idx, order);
	}

	/** NdArray + optional float index / column names. */
	public static function fromNdArray(
		matrix:NdArrayF64,
		?index:AnyIndex,
		?columns:Array<String>
	):DataFrame
		return DataFrame.fromNdArray(matrix, index, columns);

	static function timesFromBars(bars:Array<Bar>):Null<Array<Float>> {
		if (bars == null) return null;
		return [for (i in 0...bars.length) bars[i] != null ? bars[i].time : i * 1.0];
	}

	static function panelValue(panel:PanelFeed, field:String, sym:String, t:Int):Float {
		var row:Map<String, Float> = null;
		switch (field) {
			case "open": row = t < panel.opens.length ? panel.opens[t] : null;
			case "high": row = t < panel.highs.length ? panel.highs[t] : null;
			case "low": row = t < panel.lows.length ? panel.lows[t] : null;
			case "close": row = t < panel.closes.length ? panel.closes[t] : null;
			case "volume": row = t < panel.volumes.length ? panel.volumes[t] : null;
			default:
				if (panel.auxSeries != null && panel.auxSeries.exists(field)) {
					var series = panel.auxSeries.get(field);
					row = (series != null && t < series.length) ? series[t] : null;
				}
		}
		if (row == null || !row.exists(sym)) return Math.NaN;
		return row.get(sym);
	}
}
