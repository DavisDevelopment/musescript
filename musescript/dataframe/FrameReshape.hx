package musescript.dataframe;

import musescript.ndarray.NdArrayF64;

/**
 * Wide↔long reshape (M3) — pivot / melt over F64 values; Str keys OK for pivot
 * index/columns and melt idVars / valueVars.
 *
 * Pivot: unique `index` → row Index (F64 or Str); unique `columns` → col names
 * (`Std.string` for F64, raw label for Str); duplicate (index, columns) cells →
 * **last wins**; missing → NaN. `values` must be F64.
 *
 * Melt: id vars (F64 and/or Str) copied per value block.
 * - F64 valueVars → (`varName`, `valueName`) as F64 (var codes / values).
 * - Str valueVars → (`varName`, `valueName`) as Str sidecar (column names / labels).
 * - Mixed F64+Str valueVars → Str `varName` (column names), F64 `valueName`
 *   (NaN on Str rows), Str `<valueName>_str` (empty on F64 rows).
 *   No Dynamic cells.
 * Defaults: varName=`"variable"`, valueName=`"value"`.
 */
class FrameReshape {
	public static function pivot(
		df:DataFrame,
		index:String,
		columns:String,
		values:String
	):DataFrame {
		if (df == null || df.emptyFrame()) return DataFrame.empty();
		var valCol = df.valuesOf(values);
		if (valCol == null) return DataFrame.empty();

		var idxStr = df.hasStrColumn(index);
		var colStr = df.hasStrColumn(columns);
		var idxF = idxStr ? null : df.valuesOf(index);
		var colF = colStr ? null : df.valuesOf(columns);
		if (!idxStr && idxF == null) return DataFrame.empty();
		if (!colStr && colF == null) return DataFrame.empty();
		var idxS = idxStr ? df.strValuesOf(index) : null;
		var colS = colStr ? df.strValuesOf(columns) : null;

		var rowLabelsF:Array<Float> = [];
		var rowLabelsS:Array<String> = [];
		var rowPos = new Map<String, Int>();
		var colLabelsF:Array<Float> = [];
		var colLabelsS:Array<String> = [];
		var colPos = new Map<String, Int>();
		var n = df.nrows();

		for (r in 0...n) {
			var it = idxStr
				? "s:" + strAt(idxS, r)
				: "f:" + GroupBy.keyTag(idxF.getFlat(r));
			var ct = colStr
				? "s:" + strAt(colS, r)
				: "f:" + GroupBy.keyTag(colF.getFlat(r));
			if (!rowPos.exists(it)) {
				rowPos.set(it, idxStr ? rowLabelsS.length : rowLabelsF.length);
				if (idxStr) rowLabelsS.push(strAt(idxS, r));
				else rowLabelsF.push(idxF.getFlat(r));
			}
			if (!colPos.exists(ct)) {
				colPos.set(ct, colStr ? colLabelsS.length : colLabelsF.length);
				if (colStr) colLabelsS.push(strAt(colS, r));
				else colLabelsF.push(colF.getFlat(r));
			}
		}

		var nr = idxStr ? rowLabelsS.length : rowLabelsF.length;
		var nc = colStr ? colLabelsS.length : colLabelsF.length;
		if (nr == 0 || nc == 0) return DataFrame.empty();

		var names:Array<String> = if (colStr)
			[for (c in 0...nc) colNameFromStr(colLabelsS[c])]
		else
			[for (c in 0...nc) colNameFromKey(colLabelsF[c])];

		var outs:Array<NdArrayF64> = [for (_ in 0...nc) NdArrayF64.empty([nr])];
		for (c in 0...nc)
			for (r in 0...nr)
				outs[c].setFlat(r, Math.NaN);

		for (r in 0...n) {
			var it = idxStr
				? "s:" + strAt(idxS, r)
				: "f:" + GroupBy.keyTag(idxF.getFlat(r));
			var ct = colStr
				? "s:" + strAt(colS, r)
				: "f:" + GroupBy.keyTag(colF.getFlat(r));
			var ri = rowPos.get(it);
			var ci = colPos.get(ct);
			if (ri == null || ci == null) continue;
			outs[ci].setFlat(ri, valCol.getFlat(r));
		}

		var map = new Map<String, NdArrayF64>();
		for (c in 0...nc) map.set(names[c], outs[c]);
		var outIdx = idxStr ? Index.fromStrings(rowLabelsS) : Index.fromFloats(rowLabelsF);
		return DataFrame.fromColumns(map, outIdx, names);
	}

	/**
	 * Wide → long. Null/empty `valueVars` → every non-id **F64** column.
	 * Explicit Str-only `valueVars` → Str `varName`/`valueName` sidecars.
	 * Mixed F64+Str → Str `varName`, F64 `valueName`, Str `<valueName>_str`.
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

		var valsF64:Array<String> = [];
		var valsStr:Array<String> = [];
		if (valueVars != null && valueVars.length > 0) {
			for (n in valueVars) {
				if (idSet.exists(n)) continue;
				if (df.hasStrColumn(n)) valsStr.push(n);
				else if (df.valuesOf(n) != null) valsF64.push(n);
			}
		} else {
			for (n in df.f64Columns()) if (!idSet.exists(n)) valsF64.push(n);
		}
		if (valsF64.length == 0 && valsStr.length == 0) return DataFrame.empty();

		var idCols:Array<{name:String, src:NdArrayF64}> = [];
		var idStrCols:Array<{name:String, src:Array<String>}> = [];
		for (n in ids) {
			if (df.hasStrColumn(n)) {
				var src = df.strValuesOf(n);
				idStrCols.push({name: n, src: src != null ? src : []});
			} else {
				var src = df.valuesOf(n);
				if (src != null) idCols.push({name: n, src: src});
			}
		}

		var nrows = df.nrows();
		if (valsF64.length > 0 && valsStr.length > 0)
			return meltMixed(df, idCols, idStrCols, valsF64, valsStr, vn, valn, nrows);
		if (valsStr.length > 0)
			return meltStr(df, idCols, idStrCols, valsStr, vn, valn, nrows);
		return meltF64(df, idCols, idStrCols, valsF64, vn, valn, nrows);
	}

	static function meltF64(
		df:DataFrame,
		idCols:Array<{name:String, src:NdArrayF64}>,
		idStrCols:Array<{name:String, src:Array<String>}>,
		vals:Array<String>,
		vn:String,
		valn:String,
		nrows:Int
	):DataFrame {
		var varCodes:Array<Float> = [for (i in 0...vals.length) variableCode(vals[i], i)];
		var outLen = nrows * vals.length;
		var idOuts:Array<NdArrayF64> = [for (_ in idCols) NdArrayF64.empty([outLen])];
		var idStrOuts:Array<Array<String>> = [for (_ in idStrCols) [for (_ in 0...outLen) ""]];
		var varOut = NdArrayF64.empty([outLen]);
		var valOut = NdArrayF64.empty([outLen]);

		var o = 0;
		for (vi in 0...vals.length) {
			var vsrc = df.valuesOf(vals[vi]);
			var code = varCodes[vi];
			for (r in 0...nrows) {
				for (ii in 0...idCols.length)
					idOuts[ii].setFlat(o, idCols[ii].src.getFlat(r));
				for (ii in 0...idStrCols.length) {
					var labels = idStrCols[ii].src;
					idStrOuts[ii][o] = (r < labels.length) ? labels[r] : "";
				}
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
		var sMap = new Map<String, Array<String>>();
		var sOrder:Array<String> = [];
		for (ii in 0...idStrCols.length) {
			sOrder.push(idStrCols[ii].name);
			sMap.set(idStrCols[ii].name, idStrOuts[ii]);
		}
		return DataFrame.fromColumns(map, Index.range(outLen), order, sMap, sOrder);
	}

	static function meltStr(
		df:DataFrame,
		idCols:Array<{name:String, src:NdArrayF64}>,
		idStrCols:Array<{name:String, src:Array<String>}>,
		vals:Array<String>,
		vn:String,
		valn:String,
		nrows:Int
	):DataFrame {
		var outLen = nrows * vals.length;
		var idOuts:Array<NdArrayF64> = [for (_ in idCols) NdArrayF64.empty([outLen])];
		var idStrOuts:Array<Array<String>> = [for (_ in idStrCols) [for (_ in 0...outLen) ""]];
		var varOut:Array<String> = [for (_ in 0...outLen) ""];
		var valOut:Array<String> = [for (_ in 0...outLen) ""];

		var o = 0;
		for (vi in 0...vals.length) {
			var vsrc = df.strValuesOf(vals[vi]);
			for (r in 0...nrows) {
				for (ii in 0...idCols.length)
					idOuts[ii].setFlat(o, idCols[ii].src.getFlat(r));
				for (ii in 0...idStrCols.length) {
					var labels = idStrCols[ii].src;
					idStrOuts[ii][o] = (r < labels.length) ? labels[r] : "";
				}
				varOut[o] = vals[vi];
				valOut[o] = vsrc != null && r < vsrc.length && vsrc[r] != null ? vsrc[r] : "";
				o++;
			}
		}

		var map = new Map<String, NdArrayF64>();
		var order:Array<String> = [];
		for (ii in 0...idCols.length) {
			order.push(idCols[ii].name);
			map.set(idCols[ii].name, idOuts[ii]);
		}
		var sMap = new Map<String, Array<String>>();
		var sOrder:Array<String> = [];
		for (ii in 0...idStrCols.length) {
			sOrder.push(idStrCols[ii].name);
			sMap.set(idStrCols[ii].name, idStrOuts[ii]);
		}
		sOrder.push(vn);
		sMap.set(vn, varOut);
		sOrder.push(valn);
		sMap.set(valn, valOut);
		return DataFrame.fromColumns(map, Index.range(outLen), order, sMap, sOrder);
	}

	/**
	 * Mixed F64+Str valueVars without Dynamic cells: Str variable names,
	 * F64 `valueName` (NaN on Str blocks), Str `<valueName>_str` ("" on F64 blocks).
	 * Block order: F64 valueVars first (input order), then Str valueVars.
	 */
	static function meltMixed(
		df:DataFrame,
		idCols:Array<{name:String, src:NdArrayF64}>,
		idStrCols:Array<{name:String, src:Array<String>}>,
		valsF64:Array<String>,
		valsStr:Array<String>,
		vn:String,
		valn:String,
		nrows:Int
	):DataFrame {
		var vals:Array<{name:String, isStr:Bool}> = [];
		for (n in valsF64) vals.push({name: n, isStr: false});
		for (n in valsStr) vals.push({name: n, isStr: true});
		var outLen = nrows * vals.length;
		var idOuts:Array<NdArrayF64> = [for (_ in idCols) NdArrayF64.empty([outLen])];
		var idStrOuts:Array<Array<String>> = [for (_ in idStrCols) [for (_ in 0...outLen) ""]];
		var varOut:Array<String> = [for (_ in 0...outLen) ""];
		var valOut = NdArrayF64.empty([outLen]);
		var valStrOut:Array<String> = [for (_ in 0...outLen) ""];
		var valnStr = valn + "_str";

		var o = 0;
		for (vi in 0...vals.length) {
			var name = vals[vi].name;
			var isStr = vals[vi].isStr;
			var fsrc = isStr ? null : df.valuesOf(name);
			var ssrc = isStr ? df.strValuesOf(name) : null;
			for (r in 0...nrows) {
				for (ii in 0...idCols.length)
					idOuts[ii].setFlat(o, idCols[ii].src.getFlat(r));
				for (ii in 0...idStrCols.length) {
					var labels = idStrCols[ii].src;
					idStrOuts[ii][o] = (r < labels.length) ? labels[r] : "";
				}
				varOut[o] = name;
				if (isStr) {
					valOut.setFlat(o, Math.NaN);
					valStrOut[o] = ssrc != null && r < ssrc.length && ssrc[r] != null ? ssrc[r] : "";
				} else {
					valOut.setFlat(o, fsrc != null ? fsrc.getFlat(r) : Math.NaN);
					valStrOut[o] = "";
				}
				o++;
			}
		}

		var map = new Map<String, NdArrayF64>();
		var order:Array<String> = [];
		for (ii in 0...idCols.length) {
			order.push(idCols[ii].name);
			map.set(idCols[ii].name, idOuts[ii]);
		}
		order.push(valn);
		map.set(valn, valOut);
		var sMap = new Map<String, Array<String>>();
		var sOrder:Array<String> = [];
		for (ii in 0...idStrCols.length) {
			sOrder.push(idStrCols[ii].name);
			sMap.set(idStrCols[ii].name, idStrOuts[ii]);
		}
		sOrder.push(vn);
		sMap.set(vn, varOut);
		sOrder.push(valnStr);
		sMap.set(valnStr, valStrOut);
		return DataFrame.fromColumns(map, Index.range(outLen), order, sMap, sOrder);
	}

	/** Prefer float label from pivot-style names; else ordinal. */
	static function variableCode(name:String, ordinal:Int):Float {
		var parsed = Std.parseFloat(name);
		if (!Math.isNaN(parsed) && StringTools.trim(name).length > 0) {
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

	static function colNameFromStr(k:String):String {
		if (k == null || k.length == 0) return "__empty__";
		return k;
	}

	static inline function strAt(labels:Null<Array<String>>, r:Int):String {
		if (labels == null || r < 0 || r >= labels.length || labels[r] == null) return "";
		return labels[r];
	}
}
