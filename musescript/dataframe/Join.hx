package musescript.dataframe;

import musescript.ndarray.NdArrayF64;

/**
 * Equality join on F64 key columns (M1).
 * Duplicate keys: takes **last** right match (pandas-ish). `validate=true` forbids dups.
 * String sidecar columns ride along (missing match → "").
 */
class Join {
	/**
	 * Join `left` and `right` on F64 column `on`.
	 * `how`: "left" (default) | "inner" | "outer" | "right"
	 */
	public static function onColumn(
		left:DataFrame,
		right:DataFrame,
		on:String,
		?how:String = "left",
		?validate:Bool = false,
		?rsuffix:String = "_r"
	):DataFrame {
		if (left == null) left = DataFrame.empty();
		if (right == null) right = DataFrame.empty();
		var mode = how == null ? "left" : how.toLowerCase();
		var suf = rsuffix == null ? "_r" : rsuffix;
		var lKey = left.valuesOf(on);
		var rKey = right.valuesOf(on);
		if (lKey == null || rKey == null)
			throw 'pd.join: missing on="$on" column';
		if (validate) {
			assertUnique(lKey, "left");
			assertUnique(rKey, "right");
		}

		var rLast = lastIndexMap(rKey);
		var lLast = lastIndexMap(lKey);
		var lF64 = left.f64Columns();
		var lStr = left.strColumns();
		var rExtraF64:Array<String> = [for (n in right.f64Columns()) if (n != on) n];
		var rExtraStr:Array<String> = [for (n in right.strColumns()) if (n != on) n];

		return switch (mode) {
			case "inner":
				emit(left, right, on, lKey, rLast, lF64, lStr, rExtraF64, rExtraStr, suf, true);
			case "right":
				emitRight(left, right, on, rKey, lLast, lF64, lStr, rExtraF64, rExtraStr, suf);
			case "outer":
				var leftPart = emit(left, right, on, lKey, rLast, lF64, lStr, rExtraF64, rExtraStr, suf, false);
				appendUnmatchedRight(leftPart, left, right, on, lKey, rKey, rLast, lF64, lStr, rExtraF64, rExtraStr, suf);
			default:
				emit(left, right, on, lKey, rLast, lF64, lStr, rExtraF64, rExtraStr, suf, false);
		};
	}

	static function emit(
		left:DataFrame,
		right:DataFrame,
		on:String,
		lKey:NdArrayF64,
		rLast:Map<String, Int>,
		lF64:Array<String>,
		lStr:Array<String>,
		rExtraF64:Array<String>,
		rExtraStr:Array<String>,
		suf:String,
		innerOnly:Bool
	):DataFrame {
		var pairs:Array<{li:Int, ri:Int}> = [];
		for (i in 0...left.nrows()) {
			var k = keyF64(lKey.getFlat(i));
			var ri = rLast.exists(k) ? rLast.get(k) : -1;
			if (innerOnly && ri < 0) continue;
			pairs.push({li: i, ri: ri});
		}
		return materialize(left, right, on, pairs, lF64, lStr, rExtraF64, rExtraStr, suf, left.index, true);
	}

	static function emitRight(
		left:DataFrame,
		right:DataFrame,
		on:String,
		rKey:NdArrayF64,
		lLast:Map<String, Int>,
		lF64:Array<String>,
		lStr:Array<String>,
		rExtraF64:Array<String>,
		rExtraStr:Array<String>,
		suf:String
	):DataFrame {
		var pairs:Array<{li:Int, ri:Int}> = [];
		for (i in 0...right.nrows()) {
			var k = keyF64(rKey.getFlat(i));
			var li = lLast.exists(k) ? lLast.get(k) : -1;
			pairs.push({li: li, ri: i});
		}
		return materialize(left, right, on, pairs, lF64, lStr, rExtraF64, rExtraStr, suf, right.index, false);
	}

	static function appendUnmatchedRight(
		leftPart:DataFrame,
		left:DataFrame,
		right:DataFrame,
		on:String,
		lKey:NdArrayF64,
		rKey:NdArrayF64,
		rLast:Map<String, Int>,
		lF64:Array<String>,
		lStr:Array<String>,
		rExtraF64:Array<String>,
		rExtraStr:Array<String>,
		suf:String
	):DataFrame {
		var seenL = new Map<String, Bool>();
		for (i in 0...lKey.size) seenL.set(keyF64(lKey.getFlat(i)), true);
		var pairs:Array<{li:Int, ri:Int}> = [];
		for (i in 0...rKey.size) {
			var k = keyF64(rKey.getFlat(i));
			if (!seenL.exists(k) && rLast.get(k) == i)
				pairs.push({li: -1, ri: i});
		}
		if (pairs.length == 0) return leftPart;
		var extra = materialize(left, right, on, pairs, lF64, lStr, rExtraF64, rExtraStr, suf, Index.range(pairs.length), false);
		return Concat.axis0([leftPart, extra]);
	}

	static function materialize(
		left:DataFrame,
		right:DataFrame,
		on:String,
		pairs:Array<{li:Int, ri:Int}>,
		lF64:Array<String>,
		lStr:Array<String>,
		rExtraF64:Array<String>,
		rExtraStr:Array<String>,
		suf:String,
		baseIndex:AnyIndex,
		useLeftIndex:Bool
	):DataFrame {
		var n = pairs.length;
		var order:Array<String> = [];
		var cols:Array<NdArrayF64> = [];
		var sOrder:Array<String> = [];
		var sCols:Array<Array<String>> = [];

		function pushF64(name:String):NdArrayF64 {
			var c = NdArrayF64.empty([n]);
			order.push(name);
			cols.push(c);
			return c;
		}
		function pushStr(name:String):Array<String> {
			var c:Array<String> = [for (_ in 0...n) ""];
			sOrder.push(name);
			sCols.push(c);
			return c;
		}

		var lOutF:Array<NdArrayF64> = [];
		for (nm in lF64) lOutF.push(pushF64(nm));
		var lOutS:Array<Array<String>> = [];
		for (nm in lStr) lOutS.push(pushStr(nm));

		var rOutF:Array<NdArrayF64> = [];
		for (nm in rExtraF64) {
			var outNm = left.hasColumn(nm) ? nm + suf : nm;
			rOutF.push(pushF64(outNm));
		}
		var rOutS:Array<Array<String>> = [];
		for (nm in rExtraStr) {
			var outNm = left.hasColumn(nm) ? nm + suf : nm;
			rOutS.push(pushStr(outNm));
		}

		for (row in 0...n) {
			var p = pairs[row];
			for (c in 0...lF64.length) {
				var src = left.valuesOf(lF64[c]);
				lOutF[c].setFlat(row, (p.li >= 0 && src != null) ? src.getFlat(p.li) : Math.NaN);
			}
			for (c in 0...lStr.length) {
				var src = left.strValuesOf(lStr[c]);
				lOutS[c][row] = (p.li >= 0 && src != null && p.li < src.length) ? src[p.li] : "";
			}
			for (c in 0...rExtraF64.length) {
				var src = right.valuesOf(rExtraF64[c]);
				rOutF[c].setFlat(row, (p.ri >= 0 && src != null) ? src.getFlat(p.ri) : Math.NaN);
			}
			for (c in 0...rExtraStr.length) {
				var src = right.strValuesOf(rExtraStr[c]);
				rOutS[c][row] = (p.ri >= 0 && src != null && p.ri < src.length) ? src[p.ri] : "";
			}
		}

		var idx = if (useLeftIndex) {
			Index.takeOf(baseIndex, [for (p in pairs) p.li >= 0 ? p.li : 0]);
		} else if (baseIndex != null && Index.lengthOf(baseIndex) == n) {
			Index.copyOf(baseIndex);
		} else {
			Index.range(n);
		};
		if (useLeftIndex) {
			var positions:Array<Int> = [for (p in pairs) p.li];
			idx = Index.takeOf(left.index, positions);
		}
		var map = new Map<String, NdArrayF64>();
		for (i in 0...order.length) map.set(order[i], cols[i]);
		var sMap = new Map<String, Array<String>>();
		for (i in 0...sOrder.length) sMap.set(sOrder[i], sCols[i]);
		return DataFrame.fromColumns(map, idx, order, sMap, sOrder);
	}

	static function lastIndexMap(key:NdArrayF64):Map<String, Int> {
		var m = new Map<String, Int>();
		for (i in 0...key.size) m.set(keyF64(key.getFlat(i)), i);
		return m;
	}

	static function assertUnique(key:NdArrayF64, side:String):Void {
		var seen = new Map<String, Bool>();
		for (i in 0...key.size) {
			var k = keyF64(key.getFlat(i));
			if (seen.exists(k)) throw 'pd.join: duplicate key on $side ($k)';
			seen.set(k, true);
		}
	}

	static function keyF64(v:Float):String {
		if (Math.isNaN(v)) return "nan";
		return Std.string(v);
	}
}
