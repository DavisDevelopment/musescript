package musescript.dataframe;

import musescript.ndarray.NdArrayF64;

/**
 * Equality join on F64 key columns (M1).
 * Duplicate keys: takes **last** right match (pandas-ish). `validate=true` forbids dups.
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
		var lNames = left.columns();
		var rExtra:Array<String> = [for (n in right.columns()) if (n != on) n];

		return switch (mode) {
			case "inner":
				emit(left, right, on, lKey, rLast, lNames, rExtra, suf, true, false);
			case "right":
				emitRight(left, right, on, rKey, lLast, lNames, rExtra, suf);
			case "outer":
				var leftPart = emit(left, right, on, lKey, rLast, lNames, rExtra, suf, false, false);
				appendUnmatchedRight(leftPart, left, right, on, lKey, rKey, rLast, lNames, rExtra, suf);
			default:
				emit(left, right, on, lKey, rLast, lNames, rExtra, suf, false, false);
		};
	}

	static function emit(
		left:DataFrame,
		right:DataFrame,
		on:String,
		lKey:NdArrayF64,
		rLast:Map<String, Int>,
		lNames:Array<String>,
		rExtra:Array<String>,
		suf:String,
		innerOnly:Bool,
		_:Bool
	):DataFrame {
		var pairs:Array<{li:Int, ri:Int}> = [];
		for (i in 0...left.nrows()) {
			var k = keyF64(lKey.getFlat(i));
			var ri = rLast.exists(k) ? rLast.get(k) : -1;
			if (innerOnly && ri < 0) continue;
			pairs.push({li: i, ri: ri});
		}
		return materialize(left, right, on, pairs, lNames, rExtra, suf, left.index, true);
	}

	static function emitRight(
		left:DataFrame,
		right:DataFrame,
		on:String,
		rKey:NdArrayF64,
		lLast:Map<String, Int>,
		lNames:Array<String>,
		rExtra:Array<String>,
		suf:String
	):DataFrame {
		var pairs:Array<{li:Int, ri:Int}> = [];
		for (i in 0...right.nrows()) {
			var k = keyF64(rKey.getFlat(i));
			var li = lLast.exists(k) ? lLast.get(k) : -1;
			pairs.push({li: li, ri: i});
		}
		return materialize(left, right, on, pairs, lNames, rExtra, suf, right.index, false);
	}

	static function appendUnmatchedRight(
		leftPart:DataFrame,
		left:DataFrame,
		right:DataFrame,
		on:String,
		lKey:NdArrayF64,
		rKey:NdArrayF64,
		rLast:Map<String, Int>,
		lNames:Array<String>,
		rExtra:Array<String>,
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
		var extra = materialize(left, right, on, pairs, lNames, rExtra, suf, Index.range(pairs.length), false);
		return Concat.axis0([leftPart, extra]);
	}

	static function materialize(
		left:DataFrame,
		right:DataFrame,
		on:String,
		pairs:Array<{li:Int, ri:Int}>,
		lNames:Array<String>,
		rExtra:Array<String>,
		suf:String,
		baseIndex:AnyIndex,
		useLeftIndex:Bool
	):DataFrame {
		var n = pairs.length;
		var order:Array<String> = [];
		var cols:Array<NdArrayF64> = [];

		function pushCol(name:String):NdArrayF64 {
			var c = NdArrayF64.empty([n]);
			order.push(name);
			cols.push(c);
			return c;
		}

		var lOut:Array<NdArrayF64> = [];
		for (nm in lNames) {
			var outNm = (nm != on && right.hasColumn(nm)) ? nm + (useLeftIndex ? "" : suf) : nm;
			// Left names keep original; conflicting right extras get suffix.
			if (nm != on && right.hasColumn(nm) && !useLeftIndex) outNm = nm + suf;
			lOut.push(pushCol(nm)); // keep left names as-is
		}
		var rOut:Array<NdArrayF64> = [];
		for (nm in rExtra) {
			var outNm = left.hasColumn(nm) ? nm + suf : nm;
			rOut.push(pushCol(outNm));
		}

		for (row in 0...n) {
			var p = pairs[row];
			for (c in 0...lNames.length) {
				var src = left.valuesOf(lNames[c]);
				lOut[c].setFlat(row, (p.li >= 0 && src != null) ? src.getFlat(p.li) : Math.NaN);
			}
			for (c in 0...rExtra.length) {
				var src = right.valuesOf(rExtra[c]);
				rOut[c].setFlat(row, (p.ri >= 0 && src != null) ? src.getFlat(p.ri) : Math.NaN);
			}
		}

		var idx = if (useLeftIndex) {
			Index.takeOf(baseIndex, [for (p in pairs) p.li >= 0 ? p.li : 0]);
		} else if (baseIndex != null && Index.lengthOf(baseIndex) == n) {
			Index.copyOf(baseIndex);
		} else {
			Index.range(n);
		};
		// Fix index for left-join with all rows
		if (useLeftIndex) {
			var positions:Array<Int> = [for (p in pairs) p.li];
			idx = Index.takeOf(left.index, positions);
		}
		return DataFrame.fromColumnLists(order, cols, idx);
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
