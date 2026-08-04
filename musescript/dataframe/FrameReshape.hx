package musescript.dataframe;

import musescript.ndarray.NdArrayF64;

/**
 * Wide↔long reshape (M3) — pivot / melt over F64 columns.
 *
 * Pivot: unique `index` → row Index; unique `columns` → col names (`Std.string`);
 * duplicate (index, columns) cells → **last wins**; missing → NaN.
 * Melt: id vars copied; value vars → (`varName`, `valueName`). Variable codes are
 * parsed floats when the column name looks numeric (pivot round-trip), else ordinal 0..m-1.
 */
class FrameReshape {
	public static function pivot(
		df:DataFrame,
		index:String,
		columns:String,
		values:String
	):DataFrame {
		if (df == null || df.emptyFrame()) return DataFrame.empty();
		var idxCol = df.valuesOf(index);
		var colCol = df.valuesOf(columns);
		var valCol = df.valuesOf(values);
		if (idxCol == null || colCol == null || valCol == null) return DataFrame.empty();

		var rowLabels:Array<Float> = [];
		var rowPos = new Map<String, Int>();
		var colLabels:Array<Float> = [];
		var colPos = new Map<String, Int>();
		var n = df.nrows();
		for (r in 0...n) {
			var ik = idxCol.getFlat(r);
			var ck = colCol.getFlat(r);
			var it = GroupBy.keyTag(ik);
			var ct = GroupBy.keyTag(ck);
			if (!rowPos.exists(it)) {
				rowPos.set(it, rowLabels.length);
				rowLabels.push(ik);
			}
			if (!colPos.exists(ct)) {
				colPos.set(ct, colLabels.length);
				colLabels.push(ck);
			}
		}
		var nr = rowLabels.length;
		var nc = colLabels.length;
		if (nr == 0 || nc == 0) return DataFrame.empty();

		var names:Array<String> = [for (c in 0...nc) colNameFromKey(colLabels[c])];
		var outs:Array<NdArrayF64> = [for (_ in 0...nc) NdArrayF64.empty([nr])];
		for (c in 0...nc)
			for (r in 0...nr)
				outs[c].setFlat(r, Math.NaN);

		for (r in 0...n) {
			var ri = rowPos.get(GroupBy.keyTag(idxCol.getFlat(r)));
			var ci = colPos.get(GroupBy.keyTag(colCol.getFlat(r)));
			if (ri == null || ci == null) continue;
			outs[ci].setFlat(ri, valCol.getFlat(r));
		}

		var map = new Map<String, NdArrayF64>();
		for (c in 0...nc) map.set(names[c], outs[c]);
		return DataFrame.fromColumns(map, Index.fromFloats(rowLabels), names);
	}

	/**
	 * Wide → long. Null/empty `valueVars` → every non-id column.
	 * Defaults: varName=`"variable"`, valueName=`"value"`.
	 */
	public static function melt(
		df:DataFrame,
		?idVars:Array<String>,
		?valueVars:Array<String>,
		?varName:String,
		?valueName:String
	):DataFrame {
		if (df == null || df.emptyFrame()) return DataFrame.empty();
		var ids = idVars != null ? idVars : [];
		var vn = (varName != null && varName != "") ? varName : "variable";
		var valn = (valueName != null && valueName != "") ? valueName : "value";

		var idSet = new Map<String, Bool>();
		for (n in ids) idSet.set(n, true);

		var vals:Array<String> = [];
		if (valueVars != null && valueVars.length > 0) {
			for (n in valueVars) if (df.hasColumn(n) && !idSet.exists(n)) vals.push(n);
		} else {
			for (n in df.columns()) if (!idSet.exists(n)) vals.push(n);
		}
		if (vals.length == 0) return DataFrame.empty();

		var idCols:Array<{name:String, src:NdArrayF64}> = [];
		for (n in ids) {
			var src = df.valuesOf(n);
			if (src != null) idCols.push({name: n, src: src});
		}

		var varCodes:Array<Float> = [for (i in 0...vals.length) variableCode(vals[i], i)];
		var nrows = df.nrows();
		var outLen = nrows * vals.length;
		var idOuts:Array<NdArrayF64> = [for (_ in idCols) NdArrayF64.empty([outLen])];
		var varOut = NdArrayF64.empty([outLen]);
		var valOut = NdArrayF64.empty([outLen]);

		var o = 0;
		for (vi in 0...vals.length) {
			var vsrc = df.valuesOf(vals[vi]);
			var code = varCodes[vi];
			for (r in 0...nrows) {
				for (ii in 0...idCols.length)
					idOuts[ii].setFlat(o, idCols[ii].src.getFlat(r));
				varOut.setFlat(o, code);
				valOut.setFlat(o, vsrc != null ? vsrc.getFlat(r) : Math.NaN);
				o++;
			}
		}

		var map = new Map<String, NdArrayF64>();
		var order:Array<String> = [];
		for (ii in 0...idCols.length) {
			order.push(idCols[ii].name);
			map.set(idCols[ii].name, idOuts[ii]);
		}
		order.push(vn);
		map.set(vn, varOut);
		order.push(valn);
		map.set(valn, valOut);
		return DataFrame.fromColumns(map, Index.range(outLen), order);
	}

	/** Prefer float label from pivot-style names; else ordinal. */
	static function variableCode(name:String, ordinal:Int):Float {
		var parsed = Std.parseFloat(name);
		if (!Math.isNaN(parsed) && StringTools.trim(name).length > 0) {
			// Reject pure non-numeric names that parseFloat somehow accepts.
			var t = StringTools.trim(name);
			var onlyNum = true;
			for (i in 0...t.length) {
				var c = t.charCodeAt(i);
				var ok = (c >= 48 && c <= 57) || c == 46 || c == 45 || c == 43 || c == 101 || c == 69;
				if (!ok) {
					onlyNum = false;
					break;
				}
			}
			if (onlyNum) return parsed;
		}
		return ordinal * 1.0;
	}

	static function colNameFromKey(k:Float):String {
		if (Math.isNaN(k)) return "__nan__";
		return Std.string(k);
	}
}
