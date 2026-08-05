package musescript.dataframe;

import musescript.ndarray.NdArrayF64;

/**
 * `merge_asof` — last known right row with `right[on] ≤ left[on]` (backward).
 *
 * Matches `fund_panel_loader._forward_fill_onto_bars` / pandas merge_asof
 * `direction="backward"`: filing_date ≤ bar_date.
 *
 * PIT: `allowLookahead=false` (default) refuses forward/nearest. Duplicate right
 * keys at the same `on` take the **last** row (stable stream order).
 *
 * Optional `by`: F64 group codes (e.g. symbol id); asof runs independently per group.
 */
class MergeAsof {
	public static function merge(
		left:DataFrame,
		right:DataFrame,
		on:String,
		?by:String,
		?direction:String = "backward",
		?allowLookahead:Bool = false,
		?tolerance:Null<Float>
	):DataFrame {
		if (left == null) left = DataFrame.empty();
		if (right == null) right = DataFrame.empty();
		var dir = direction == null ? "backward" : direction.toLowerCase();
		if (!allowLookahead && dir != "backward")
			throw 'pd.merge_asof: direction="$dir" refused (allow_lookahead=false; PIT default)';
		if (dir != "backward" && dir != "forward" && dir != "nearest")
			throw 'pd.merge_asof: unknown direction "$dir"';

		var lOn = left.valuesOf(on);
		var rOn = right.valuesOf(on);
		if (lOn == null || rOn == null)
			throw 'pd.merge_asof: missing on="$on" column';

		if (by != null && by.length > 0) {
			var lBy = left.valuesOf(by);
			var rBy = right.valuesOf(by);
			if (lBy == null || rBy == null)
				throw 'pd.merge_asof: missing by="$by" column';
			return mergeGrouped(left, right, on, by, lOn, rOn, lBy, rBy, dir, tolerance);
		}
		return mergeFlat(left, right, on, lOn, rOn, dir, tolerance);
	}

	static function mergeFlat(
		left:DataFrame,
		right:DataFrame,
		on:String,
		lOn:NdArrayF64,
		rOn:NdArrayF64,
		dir:String,
		tolerance:Null<Float>
	):DataFrame {
		var lOrder = sortPerm(lOn);
		var rOrder = sortPerm(rOn);
		var matches = matchSorted(
			[for (i in lOrder) lOn.getFlat(i)],
			[for (i in rOrder) rOn.getFlat(i)],
			dir,
			tolerance
		);
		// Map sorted-left row → right original index (−1 miss).
		var rightForLeftSorted:Array<Int> = [];
		for (i in 0...matches.length) {
			var rj = matches[i];
			rightForLeftSorted.push(rj < 0 ? -1 : rOrder[rj]);
		}
		// Restore left row order.
		var rightForLeft:Array<Int> = [for (_ in 0...left.nrows()) -1];
		for (si in 0...lOrder.length)
			rightForLeft[lOrder[si]] = rightForLeftSorted[si];
		return stitch(left, right, on, rightForLeft);
	}

	static function mergeGrouped(
		left:DataFrame,
		right:DataFrame,
		on:String,
		by:String,
		lOn:NdArrayF64,
		rOn:NdArrayF64,
		lBy:NdArrayF64,
		rBy:NdArrayF64,
		dir:String,
		tolerance:Null<Float>
	):DataFrame {
		var groupsL = groupIndices(lBy);
		var groupsR = groupIndices(rBy);
		var rightForLeft:Array<Int> = [for (_ in 0...left.nrows()) -1];
		for (gk in groupsL.keys()) {
			var lIdx = groupsL.get(gk);
			var rIdx = groupsR.exists(gk) ? groupsR.get(gk) : [];
			var lTimes = [for (i in lIdx) lOn.getFlat(i)];
			var rTimes = [for (i in rIdx) rOn.getFlat(i)];
			var lPerm = sortPermArray(lTimes);
			var rPerm = sortPermArray(rTimes);
			var lSorted = [for (p in lPerm) lTimes[p]];
			var rSorted = [for (p in rPerm) rTimes[p]];
			var matches = matchSorted(lSorted, rSorted, dir, tolerance);
			for (si in 0...lPerm.length) {
				var leftOrig = lIdx[lPerm[si]];
				var rj = matches[si];
				rightForLeft[leftOrig] = rj < 0 ? -1 : rIdx[rPerm[rj]];
			}
		}
		return stitch(left, right, on, rightForLeft);
	}

	/**
	 * Core scan — both time arrays must be ascending.
	 * Backward: last right with r[j] <= l[i] (and |Δ|<=tol if set).
	 */
	public static function matchSorted(
		leftTimes:Array<Float>,
		rightTimes:Array<Float>,
		dir:String,
		tolerance:Null<Float>
	):Array<Int> {
		var nL = leftTimes.length;
		var nR = rightTimes.length;
		var out:Array<Int> = [for (_ in 0...nL) -1];
		if (nL == 0) return out;

		if (dir == "backward") {
			var j = 0;
			var cur = -1;
			for (i in 0...nL) {
				var t = leftTimes[i];
				while (j < nR && rightTimes[j] <= t) {
					cur = j;
					j++;
				}
				if (cur >= 0 && withinTol(t, rightTimes[cur], tolerance))
					out[i] = cur;
				else
					out[i] = -1;
			}
		} else if (dir == "forward") {
			var j = 0;
			for (i in 0...nL) {
				var t = leftTimes[i];
				while (j < nR && rightTimes[j] < t) j++;
				if (j < nR && withinTol(t, rightTimes[j], tolerance))
					out[i] = j;
			}
		} else { // nearest
			var j = 0;
			for (i in 0...nL) {
				var t = leftTimes[i];
				while (j + 1 < nR && rightTimes[j + 1] <= t) j++;
				var best = -1;
				var bestDist = Math.POSITIVE_INFINITY;
				for (cand in [j, j + 1]) {
					if (cand < 0 || cand >= nR) continue;
					var d = Math.abs(rightTimes[cand] - t);
					if (d < bestDist) {
						bestDist = d;
						best = cand;
					}
				}
				if (best >= 0 && withinTol(t, rightTimes[best], tolerance))
					out[i] = best;
			}
		}
		return out;
	}

	/** Stitch left columns + right extras (suffix `_r` on name clash except `on`/`by`). */
	static function stitch(
		left:DataFrame,
		right:DataFrame,
		on:String,
		rightForLeft:Array<Int>
	):DataFrame {
		var n = left.nrows();
		var order:Array<String> = left.f64Columns().copy();
		var cols:Array<NdArrayF64> = [];
		for (nm in order) {
			var src = left.valuesOf(nm);
			cols.push(src != null ? src.copy() : NdArrayF64.empty([n]));
		}
		var sOrder:Array<String> = left.strColumns().copy();
		var sCols:Array<Array<String>> = [];
		for (nm in sOrder) {
			var src = left.strValuesOf(nm);
			sCols.push(src != null ? src.copy() : [for (_ in 0...n) ""]);
		}
		for (nm in right.f64Columns()) {
			if (nm == on) continue;
			var outNm = left.hasColumn(nm) ? nm + "_r" : nm;
			order.push(outNm);
			var src = right.valuesOf(nm);
			var col = NdArrayF64.empty([n]);
			for (i in 0...n) {
				var rj = rightForLeft[i];
				col.setFlat(i, (rj >= 0 && src != null) ? src.getFlat(rj) : Math.NaN);
			}
			cols.push(col);
		}
		for (nm in right.strColumns()) {
			if (nm == on) continue;
			var outNm = left.hasColumn(nm) ? nm + "_r" : nm;
			sOrder.push(outNm);
			var src = right.strValuesOf(nm);
			var labels:Array<String> = [];
			for (i in 0...n) {
				var rj = rightForLeft[i];
				labels.push((rj >= 0 && src != null && rj < src.length) ? src[rj] : "");
			}
			sCols.push(labels);
		}
		var map = new Map<String, NdArrayF64>();
		for (i in 0...order.length) map.set(order[i], cols[i]);
		var sMap = new Map<String, Array<String>>();
		for (i in 0...sOrder.length) sMap.set(sOrder[i], sCols[i]);
		return DataFrame.fromColumns(map, Index.copyOf(left.index), order, sMap, sOrder);
	}

	static function withinTol(leftT:Float, rightT:Float, tol:Null<Float>):Bool {
		if (tol == null) return true;
		return Math.abs(leftT - rightT) <= tol;
	}

	static function sortPerm(a:NdArrayF64):Array<Int> {
		var idx:Array<Int> = [for (i in 0...a.size) i];
		idx.sort(function(i, j) {
			var x = a.getFlat(i);
			var y = a.getFlat(j);
			return x < y ? -1 : (x > y ? 1 : (i < j ? -1 : (i > j ? 1 : 0)));
		});
		return idx;
	}

	static function sortPermArray(a:Array<Float>):Array<Int> {
		var idx:Array<Int> = [for (i in 0...a.length) i];
		idx.sort(function(i, j) {
			var x = a[i];
			var y = a[j];
			return x < y ? -1 : (x > y ? 1 : (i < j ? -1 : (i > j ? 1 : 0)));
		});
		return idx;
	}

	static function groupIndices(by:NdArrayF64):Map<String, Array<Int>> {
		var m = new Map<String, Array<Int>>();
		for (i in 0...by.size) {
			var k = keyF64(by.getFlat(i));
			if (!m.exists(k)) m.set(k, []);
			m.get(k).push(i);
		}
		return m;
	}

	static function keyF64(v:Float):String {
		if (Math.isNaN(v)) return "nan";
		return Std.string(v);
	}
}
