package musescript.dataframe;

import musescript.ndarray.NdArrayF64;

/**
 * Multi-level Index — F64 and/or Str levels, N ≥ 1 (construct/groupby/as_index).
 *
 * Storage: dense levels and/or codes + unique levels (pandas-like).
 * `fromCodes` keeps codes primary until densify is needed; `codes()` /
 * `uniqueLevels()` factorize dense levels on demand (cached).
 *
 * Compat: `fromArrays` / `fromKeyRows` / `fromFrame` stay 2×F64 defaults.
 * Gaps: DF ops outside copy/iloc/slice/xs/reset/groupby may drop str cols.
 */
class MultiIndex {
	/** Dense per-row labels; null when codes-primary until {@link ensureDense}. */
	var _levels:Null<Array<MultiLevel>>;
	/** Integer codes into `_uniqueLevels` (pandas `.codes`); −1 = missing. */
	var _codes:Null<Array<Array<Int>>>;
	/** Unique values per level (pandas `.levels`). */
	var _uniqueLevels:Null<Array<MultiLevel>>;
	var _names:Array<String>;
	var _len:Int;

	function new(
		levels:Null<Array<MultiLevel>>,
		names:Array<String>,
		?codes:Null<Array<Array<Int>>>,
		?uniques:Null<Array<MultiLevel>>,
		?knownLen:Null<Int>
	) {
		_names = [];
		_levels = null;
		_codes = null;
		_uniqueLevels = null;
		_len = 0;

		if (codes != null && uniques != null && uniques.length > 0) {
			var nLev = uniques.length;
			_names = defaultNames(names, nLev);
			_uniqueLevels = copyLevels(uniques);
			_codes = copyCodes(codes, nLev, knownLen);
			_len = _codes.length > 0 ? _codes[0].length : (knownLen != null ? knownLen : 0);
			return;
		}

		var lv = levels != null && levels.length > 0 ? levels : [MultiLevel.F64(IndexF64.empty()), MultiLevel.F64(IndexF64.empty())];
		var nLev = lv.length;
		_names = defaultNames(names, nLev);
		var n = 0;
		for (l in lv) {
			var len = levelLen(l);
			if (len > n) n = len;
		}
		var padded:Array<MultiLevel> = [];
		for (i in 0...lv.length)
			padded.push(levelLen(lv[i]) == n ? lv[i] : padLevel(lv[i], n));
		_levels = padded;
		_len = n;
	}

	static function defaultNames(names:Null<Array<String>>, n:Int):Array<String> {
		var out:Array<String> = [];
		for (i in 0...n) {
			if (names != null && i < names.length && names[i] != null && names[i] != "")
				out.push(names[i]);
			else
				out.push("level_" + i);
		}
		return out;
	}

	static function levelLen(lv:MultiLevel):Int {
		return switch (lv) {
			case F64(i): i.length;
			case Str(i): i.length;
		};
	}

	static function padLevel(src:MultiLevel, n:Int):MultiLevel {
		return switch (src) {
			case F64(idx):
				var out = NdArrayF64.empty([n]);
				var m = idx.length < n ? idx.length : n;
				for (i in 0...m) out.setFlat(i, idx.get(i));
				for (i in m...n) out.setFlat(i, Math.NaN);
				MultiLevel.F64(IndexF64.fromNdArray(out));
			case Str(idx):
				var labels:Array<String> = [];
				var m = idx.length < n ? idx.length : n;
				for (i in 0...m) {
					var s = idx.get(i);
					labels.push(s != null ? s : "");
				}
				for (i in m...n) labels.push("");
				MultiLevel.Str(IndexStr.fromArray(labels));
		};
	}

	static function copyLevels(src:Array<MultiLevel>):Array<MultiLevel> {
		var out:Array<MultiLevel> = [];
		for (l in src) {
			out.push(switch (l) {
				case F64(i): MultiLevel.F64(i.copy());
				case Str(i): MultiLevel.Str(i.copy());
			});
		}
		return out;
	}

	static function copyCodes(src:Array<Array<Int>>, nLev:Int, ?knownLen:Null<Int>):Array<Array<Int>> {
		var n = knownLen != null ? knownLen : 0;
		if (n == 0) {
			for (c in src) if (c != null && c.length > n) n = c.length;
		}
		var out:Array<Array<Int>> = [];
		for (li in 0...nLev) {
			var row:Array<Int> = [];
			var col = li < src.length ? src[li] : null;
			for (i in 0...n) {
				if (col != null && i < col.length) row.push(col[i]);
				else row.push(Factorize.NA_CODE);
			}
			out.push(row);
		}
		return out;
	}

	function ensureDense():Void {
		if (_levels != null) return;
		if (_codes == null || _uniqueLevels == null) {
			_levels = [MultiLevel.F64(IndexF64.empty())];
			_len = 0;
			return;
		}
		var n = _len;
		var dense:Array<MultiLevel> = [];
		for (li in 0..._uniqueLevels.length) {
			var codes = _codes[li];
			dense.push(switch (_uniqueLevels[li]) {
				case F64(u):
					var vals:Array<Float> = [];
					for (i in 0...n) {
						var c = codes != null && i < codes.length ? codes[i] : Factorize.NA_CODE;
						vals.push(c < 0 || c >= u.length ? Math.NaN : u.get(c));
					}
					MultiLevel.F64(IndexF64.fromArray(vals));
				case Str(u):
					var labels:Array<String> = [];
					for (i in 0...n) {
						var c = codes != null && i < codes.length ? codes[i] : Factorize.NA_CODE;
						if (c < 0 || c >= u.length) labels.push("");
						else {
							var s = u.get(c);
							labels.push(s != null ? s : "");
						}
					}
					MultiLevel.Str(IndexStr.fromArray(labels));
			});
		}
		_levels = dense;
	}

	function ensureCodes(?dropNa:Bool = true):Void {
		if (_codes != null && _uniqueLevels != null) return;
		ensureDense();
		var codes:Array<Array<Int>> = [];
		var uniq:Array<MultiLevel> = [];
		for (lv in _levels) {
			var fr = Factorize.level(lv, dropNa);
			codes.push(fr.codes.copy());
			uniq.push(switch (fr.uniques) {
				case F64(u): MultiLevel.F64(u.copy());
				case Str(u): MultiLevel.Str(u.copy());
			});
		}
		_codes = codes;
		_uniqueLevels = uniq;
	}

	public static function empty(?names:Array<String>):MultiIndex {
		var n = names != null && names.length > 0 ? names.length : 2;
		var levels:Array<MultiLevel> = [for (_ in 0...n) MultiLevel.F64(IndexF64.empty())];
		return new MultiIndex(levels, names);
	}

	/** Two parallel F64 label arrays (pandas-like `from_arrays`). */
	public static function fromArrays(
		level0:Array<Float>,
		level1:Array<Float>,
		?names:Array<String>
	):MultiIndex {
		var a = level0 != null ? level0 : [];
		var b = level1 != null ? level1 : [];
		return fromLevels([
			MultiLevel.F64(IndexF64.fromArray(a)),
			MultiLevel.F64(IndexF64.fromArray(b))
		], names);
	}

	/** Two parallel Str label arrays. */
	public static function fromArraysStr(
		level0:Array<String>,
		level1:Array<String>,
		?names:Array<String>
	):MultiIndex {
		var a = level0 != null ? level0 : [];
		var b = level1 != null ? level1 : [];
		return fromLevels([
			MultiLevel.Str(IndexStr.fromArray(a)),
			MultiLevel.Str(IndexStr.fromArray(b))
		], names);
	}

	/** Mixed / N-level construct from typed dense levels. */
	public static function fromLevels(levels:Array<MultiLevel>, ?names:Array<String>):MultiIndex
		return new MultiIndex(levels != null ? levels : [], names);

	/**
	 * Codes + unique levels (pandas `MultiIndex(levels=…, codes=…)`).
	 * Codes primary — densify deferred until label accessors / xs need it.
	 */
	public static function fromCodes(
		uniques:Array<MultiLevel>,
		codes:Array<Array<Int>>,
		?names:Array<String>
	):MultiIndex {
		if (uniques == null || uniques.length == 0) return empty(names);
		var n = 0;
		if (codes != null) for (c in codes) if (c != null && c.length > n) n = c.length;
		return new MultiIndex(null, names, codes != null ? codes : [], uniques, n);
	}

	/** From `[{l0,l1}, …]` F64 group key rows (groupby / agg). */
	public static function fromKeyRows(
		keyRows:Array<Array<Float>>,
		?names:Array<String>
	):MultiIndex {
		if (keyRows == null || keyRows.length == 0) return empty(names);
		var width = 2;
		for (row in keyRows)
			if (row != null && row.length > width) width = row.length;
		if (names != null && names.length > width) width = names.length;
		if (width < 2) width = 2;
		var cols:Array<Array<Float>> = [for (_ in 0...width) []];
		for (row in keyRows) {
			for (c in 0...width)
				cols[c].push(row != null && c < row.length ? row[c] : Math.NaN);
		}
		var levels:Array<MultiLevel> = [for (c in 0...width) MultiLevel.F64(IndexF64.fromArray(cols[c]))];
		return fromLevels(levels, names);
	}

	/**
	 * Build from typed per-row key cells (F64 and/or Str), groupby as_index path.
	 * Width = max row length (or names.length); missing cells → NaN / "".
	 */
	public static function fromKeyCells(
		keyRows:Array<Array<KeyCell>>,
		?names:Array<String>
	):MultiIndex {
		if (keyRows == null || keyRows.length == 0) return empty(names);
		var width = names != null ? names.length : 0;
		for (row in keyRows)
			if (row != null && row.length > width) width = row.length;
		if (width < 1) return empty(names);
		var kinds:Array<String> = [for (_ in 0...width) "f64"];
		for (row in keyRows) {
			if (row == null) continue;
			for (c in 0...row.length) {
				switch (row[c]) {
					case Str(_): kinds[c] = "str";
					case F64(_): // keep
				}
			}
		}
		var levels:Array<MultiLevel> = [];
		for (c in 0...width) {
			if (kinds[c] == "str") {
				var labels:Array<String> = [];
				for (row in keyRows) {
					if (row != null && c < row.length) {
						switch (row[c]) {
							case Str(s): labels.push(s != null ? s : "");
							case F64(v): labels.push(Math.isNaN(v) ? "" : Std.string(v));
						}
					} else labels.push("");
				}
				levels.push(MultiLevel.Str(IndexStr.fromArray(labels)));
			} else {
				var vals:Array<Float> = [];
				for (row in keyRows) {
					if (row != null && c < row.length) {
						switch (row[c]) {
							case F64(v): vals.push(v);
							case Str(_): vals.push(Math.NaN);
						}
					} else vals.push(Math.NaN);
				}
				levels.push(MultiLevel.F64(IndexF64.fromArray(vals)));
			}
		}
		return fromLevels(levels, names);
	}

	/**
	 * Build from F64 columns of a frame (all `by` names; missing → NaN).
	 * String columns ignored here — use {@link fromFrameLevels}.
	 */
	public static function fromFrame(df:DataFrame, by:Array<String>):MultiIndex {
		if (df == null || by == null || by.length < 2) return empty(by);
		var n = df.nrows();
		var levels:Array<MultiLevel> = [];
		var names:Array<String> = [];
		for (b in by) {
			if (b == null || b == "") continue;
			names.push(b);
			var c = df.valuesOf(b);
			var vals:Array<Float> = [];
			for (i in 0...n) vals.push(c != null ? c.getFlat(i) : Math.NaN);
			levels.push(MultiLevel.F64(IndexF64.fromArray(vals)));
		}
		if (levels.length < 2) return empty(by);
		return fromLevels(levels, names);
	}

	/** Build MultiIndex from F64 and/or Str frame columns (`by` order). */
	public static function fromFrameLevels(df:DataFrame, by:Array<String>):MultiIndex {
		if (df == null || by == null || by.length == 0) return empty(by);
		var n = df.nrows();
		var levels:Array<MultiLevel> = [];
		var names:Array<String> = [];
		for (b in by) {
			if (b == null || b == "") continue;
			names.push(b);
			if (df.hasStrColumn(b)) {
				var s = df.strValuesOf(b);
				var labels:Array<String> = [];
				for (i in 0...n) labels.push(s != null && i < s.length && s[i] != null ? s[i] : "");
				levels.push(MultiLevel.Str(IndexStr.fromArray(labels)));
			} else {
				var c = df.valuesOf(b);
				var vals:Array<Float> = [];
				for (i in 0...n) vals.push(c != null ? c.getFlat(i) : Math.NaN);
				levels.push(MultiLevel.F64(IndexF64.fromArray(vals)));
			}
		}
		if (levels.length == 0) return empty(by);
		return fromLevels(levels, names);
	}

	/**
	 * Frame columns → codes-primary MultiIndex (factorize each `by` col, dropNa).
	 * Prefer when cardinality ≪ nrows (memory) or for categorical handoff.
	 */
	public static function fromFrameCodes(df:DataFrame, by:Array<String>, ?dropNa:Bool = true):MultiIndex {
		if (df == null || by == null || by.length == 0) return empty(by);
		var n = df.nrows();
		var uniques:Array<MultiLevel> = [];
		var codes:Array<Array<Int>> = [];
		var names:Array<String> = [];
		for (b in by) {
			if (b == null || b == "") continue;
			names.push(b);
			var fr:FactorizeResult;
			if (df.hasStrColumn(b)) {
				var s = df.strValuesOf(b);
				var labels:Array<String> = [];
				for (i in 0...n) labels.push(s != null && i < s.length && s[i] != null ? s[i] : "");
				fr = Factorize.str(labels, dropNa);
			} else {
				var c = df.valuesOf(b);
				var vals:Array<Float> = [];
				for (i in 0...n) vals.push(c != null ? c.getFlat(i) : Math.NaN);
				fr = Factorize.f64(vals, dropNa);
			}
			codes.push(fr.codes);
			uniques.push(switch (fr.uniques) {
				case F64(u): MultiLevel.F64(u);
				case Str(u): MultiLevel.Str(u);
			});
		}
		if (uniques.length == 0) return empty(by);
		return fromCodes(uniques, codes, names);
	}

	public var length(get, never):Int;
	function get_length():Int return _len;

	public var nlevels(get, never):Int;
	function get_nlevels():Int {
		if (_uniqueLevels != null) return _uniqueLevels.length;
		if (_levels != null) return _levels.length;
		return 0;
	}

	public function names():Array<String> return _names.copy();

	/** True when codes + uniques are stored without a dense materialization yet. */
	public function isCodesPrimary():Bool
		return _codes != null && _uniqueLevels != null && _levels == null;

	/**
	 * Per-level integer codes (copy). Factorizes dense levels on first call.
	 * Missing F64 → `Factorize.NA_CODE` (−1).
	 */
	public function codes():Array<Array<Int>> {
		ensureCodes(true);
		return [for (c in _codes) c.copy()];
	}

	public function codesAt(level:Int):Array<Int> {
		ensureCodes(true);
		if (level < 0 || _codes == null || level >= _codes.length) return [];
		return _codes[level].copy();
	}

	/** Unique values per level (pandas `.levels`); copy of Index wrappers. */
	public function uniqueLevels():Array<MultiLevel> {
		ensureCodes(true);
		return copyLevels(_uniqueLevels);
	}

	public function uniqueLevelAt(level:Int):Null<MultiLevel> {
		ensureCodes(true);
		if (level < 0 || _uniqueLevels == null || level >= _uniqueLevels.length) return null;
		return switch (_uniqueLevels[level]) {
			case F64(i): MultiLevel.F64(i.copy());
			case Str(i): MultiLevel.Str(i.copy());
		};
	}

	/**
	 * Rebuild as codes-primary (drop dense cache). Same labels; lower memory when
	 * cardinality ≪ length. Idempotent when already codes-primary.
	 */
	public function toCodesForm(?dropNa:Bool = true):MultiIndex {
		ensureCodes(dropNa);
		return fromCodes(copyLevels(_uniqueLevels), [for (c in _codes) c.copy()], _names.copy());
	}

	public function levelAt(level:Int):Null<MultiLevel> {
		ensureDense();
		if (level < 0 || level >= _levels.length) return null;
		return _levels[level];
	}

	public function levelKind(level:Int):String {
		if (_uniqueLevels != null && level >= 0 && level < _uniqueLevels.length) {
			return switch (_uniqueLevels[level]) {
				case F64(_): "f64";
				case Str(_): "str";
			};
		}
		return switch (levelAt(level)) {
			case null: "none";
			case F64(_): "f64";
			case Str(_): "str";
		};
	}

	/** F64 level accessor; Str / OOB → empty IndexF64. */
	public function getLevel(level:Int):IndexF64 {
		return switch (levelAt(level)) {
			case F64(i): i;
			default: IndexF64.empty();
		};
	}

	public function getLevelStr(level:Int):IndexStr {
		return switch (levelAt(level)) {
			case Str(i): i;
			default: IndexStr.empty();
		};
	}

	public function get(row:Int, level:Int):Float {
		if (row < 0 || row >= length) return Math.NaN;
		if (_codes != null && _uniqueLevels != null && level >= 0 && level < _uniqueLevels.length) {
			var c = _codes[level][row];
			return switch (_uniqueLevels[level]) {
				case F64(u): c < 0 || c >= u.length ? Math.NaN : u.get(c);
				case Str(_): Math.NaN;
			};
		}
		return switch (levelAt(level)) {
			case F64(i): i.get(row);
			default: Math.NaN;
		};
	}

	public function getStr(row:Int, level:Int):String {
		if (row < 0 || row >= length) return "";
		if (_codes != null && _uniqueLevels != null && level >= 0 && level < _uniqueLevels.length) {
			var c = _codes[level][row];
			return switch (_uniqueLevels[level]) {
				case Str(u):
					if (c < 0 || c >= u.length) return "";
					var s = u.get(c);
					s != null ? s : "";
				case F64(u):
					if (c < 0 || c >= u.length) return "";
					var v = u.get(c);
					Math.isNaN(v) ? "" : Std.string(v);
			};
		}
		return switch (levelAt(level)) {
			case Str(i):
				var s = i.get(row);
				s != null ? s : "";
			case F64(i):
				var v = i.get(row);
				Math.isNaN(v) ? "" : Std.string(v);
			case null: "";
		};
	}

	public function levelValues(level:Int):Array<Float>
		return getLevel(level).toArray();

	public function levelValuesStr(level:Int):Array<String>
		return getLevelStr(level).labels();

	/** Per-level F64 arrays; Str levels are empty arrays (use {@link levelValuesStr}). */
	public function toArrays():Array<Array<Float>> {
		ensureDense();
		var out:Array<Array<Float>> = [];
		for (i in 0..._levels.length) {
			switch (_levels[i]) {
				case F64(idx): out.push(idx.toArray());
				case Str(_): out.push([]);
			}
		}
		return out;
	}

	/** Row positions where F64 `level` equals `key` (NaN matches NaN). */
	public function xsPositions(key:Float, ?level:Int = 0):Array<Int> {
		var out:Array<Int> = [];
		if (_codes != null && _uniqueLevels != null && level >= 0 && level < _uniqueLevels.length) {
			switch (_uniqueLevels[level]) {
				case F64(u):
					var want = Factorize.NA_CODE;
					var keyNan = Math.isNaN(key);
					if (!keyNan) {
						for (ui in 0...u.length) {
							var v = u.get(ui);
							if (v == key) { want = ui; break; }
						}
						if (want < 0) return out;
					} else {
						// match NA codes
						for (i in 0..._len)
							if (_codes[level][i] < 0) out.push(i);
						return out;
					}
					for (i in 0..._len)
						if (_codes[level][i] == want) out.push(i);
					return out;
				default:
			}
		}
		switch (levelAt(level)) {
			case F64(lv):
				var keyNan = Math.isNaN(key);
				for (i in 0...lv.length) {
					var v = lv.get(i);
					if (keyNan ? Math.isNaN(v) : v == key) out.push(i);
				}
			default:
		}
		return out;
	}

	/** Row positions where Str `level` equals `key`. */
	public function xsPositionsStr(key:String, ?level:Int = 0):Array<Int> {
		var out:Array<Int> = [];
		var wantStr = key != null ? key : "";
		if (_codes != null && _uniqueLevels != null && level >= 0 && level < _uniqueLevels.length) {
			switch (_uniqueLevels[level]) {
				case Str(u):
					var want = Factorize.NA_CODE;
					for (ui in 0...u.length) {
						var v = u.get(ui);
						if (v == null) v = "";
						if (v == wantStr) { want = ui; break; }
					}
					if (want < 0) return out;
					for (i in 0..._len)
						if (_codes[level][i] == want) out.push(i);
					return out;
				default:
			}
		}
		switch (levelAt(level)) {
			case Str(lv):
				for (i in 0...lv.length) {
					var v = lv.get(i);
					if (v == null) v = "";
					if (v == wantStr) out.push(i);
				}
			default:
		}
		return out;
	}

	/**
	 * Drop one level → remaining levels as MultiIndex.
	 * Compat: 2-level F64 → {@link dropLevel} still returns the other F64 Index.
	 */
	public function withoutLevel(level:Int):MultiIndex {
		if (nlevels <= 1) return empty();
		if (_codes != null && _uniqueLevels != null) {
			var uc:Array<MultiLevel> = [];
			var cc:Array<Array<Int>> = [];
			var nm:Array<String> = [];
			for (i in 0..._uniqueLevels.length) {
				if (i == level) continue;
				uc.push(_uniqueLevels[i]);
				cc.push(_codes[i]);
				nm.push(_names[i]);
			}
			var mi = fromCodes(uc, cc, nm);
			if (_levels != null) {
				var lv:Array<MultiLevel> = [];
				for (i in 0..._levels.length) if (i != level) lv.push(_levels[i]);
				mi._levels = lv;
			}
			return mi;
		}
		ensureDense();
		var lv:Array<MultiLevel> = [];
		var nm:Array<String> = [];
		for (i in 0..._levels.length) {
			if (i == level) continue;
			lv.push(_levels[i]);
			nm.push(_names[i]);
		}
		return new MultiIndex(lv, nm);
	}

	/**
	 * Drop one level → single `IndexF64` of the remaining level when it is F64
	 * (2-level F64 xs path). Str / multi-remaining → empty IndexF64; use {@link withoutLevel}.
	 */
	public function dropLevel(level:Int):IndexF64 {
		var rest = withoutLevel(level);
		if (rest.nlevels == 1) {
			return switch (rest.levelAt(0)) {
				case F64(i): i.copy();
				default: IndexF64.empty();
			};
		}
		return IndexF64.empty();
	}

	/** Collapse 1-level MultiIndex to F64/Str AnyIndex; else Multi. */
	public function toAnyIndex():AnyIndex {
		if (nlevels == 1) {
			ensureDense();
			return switch (_levels[0]) {
				case F64(i): AnyIndex.F64(i.copy());
				case Str(i): AnyIndex.Str(i.copy());
			};
		}
		return AnyIndex.Multi(copy());
	}

	public function copy():MultiIndex {
		if (_codes != null && _uniqueLevels != null) {
			var mi = fromCodes(copyLevels(_uniqueLevels), [for (c in _codes) c.copy()], _names.copy());
			if (_levels != null) mi._levels = copyLevels(_levels);
			return mi;
		}
		ensureDense();
		return new MultiIndex(copyLevels(_levels), _names.copy());
	}

	public function slice(start:Int, stop:Int):MultiIndex {
		var s = start < 0 ? 0 : start;
		var e = stop > _len ? _len : (stop < 0 ? 0 : stop);
		if (e <= s) return empty(_names.copy());
		if (_codes != null && _uniqueLevels != null) {
			var cc:Array<Array<Int>> = [];
			for (c in _codes) cc.push(c.slice(s, e));
			var mi = fromCodes(copyLevels(_uniqueLevels), cc, _names.copy());
			if (_levels != null) {
				var lv:Array<MultiLevel> = [];
				for (l in _levels) {
					lv.push(switch (l) {
						case F64(i): MultiLevel.F64(i.slice(s, e));
						case Str(i): MultiLevel.Str(i.slice(s, e));
					});
				}
				mi._levels = lv;
			}
			return mi;
		}
		ensureDense();
		var lv:Array<MultiLevel> = [];
		for (l in _levels) {
			lv.push(switch (l) {
				case F64(i): MultiLevel.F64(i.slice(s, e));
				case Str(i): MultiLevel.Str(i.slice(s, e));
			});
		}
		return new MultiIndex(lv, _names.copy());
	}

	public function take(indices:Array<Int>):MultiIndex {
		if (indices == null || indices.length == 0) return empty(_names.copy());
		if (_codes != null && _uniqueLevels != null) {
			var cc:Array<Array<Int>> = [];
			for (c in _codes) {
				var row:Array<Int> = [];
				for (ix in indices) {
					if (ix >= 0 && ix < _len) row.push(c[ix]);
					else row.push(Factorize.NA_CODE);
				}
				cc.push(row);
			}
			var mi = fromCodes(copyLevels(_uniqueLevels), cc, _names.copy());
			if (_levels != null) {
				var lv:Array<MultiLevel> = [];
				for (l in _levels) {
					lv.push(switch (l) {
						case F64(i): MultiLevel.F64(i.take(indices));
						case Str(i): MultiLevel.Str(i.take(indices));
					});
				}
				mi._levels = lv;
			}
			return mi;
		}
		ensureDense();
		var lv:Array<MultiLevel> = [];
		for (l in _levels) {
			lv.push(switch (l) {
				case F64(i): MultiLevel.F64(i.take(indices));
				case Str(i): MultiLevel.Str(i.take(indices));
			});
		}
		return new MultiIndex(lv, _names.copy());
	}

	public function equals(other:MultiIndex):Bool {
		if (other == null || other.length != length || other.nlevels != nlevels) return false;
		for (i in 0..._names.length)
			if (_names[i] != other._names[i]) return false;
		ensureDense();
		other.ensureDense();
		for (i in 0..._levels.length) {
			switch [_levels[i], other._levels[i]] {
				case [F64(a), F64(b)]: if (!a.equals(b)) return false;
				case [Str(a), Str(b)]: if (!a.equals(b)) return false;
				default: return false;
			}
		}
		return true;
	}

	static function keyF64(v:Float):String {
		if (Math.isNaN(v)) return "nan";
		return Std.string(v);
	}

	/** Compound label tag for align / maps. */
	public function rowTag(i:Int):String {
		var parts:Array<String> = [];
		if (_codes != null && _uniqueLevels != null) {
			for (li in 0..._uniqueLevels.length) {
				var c = _codes[li][i];
				parts.push(switch (_uniqueLevels[li]) {
					case F64(u):
						c < 0 || c >= u.length ? "nan" : keyF64(u.get(c));
					case Str(u):
						if (c < 0 || c >= u.length) "";
						else {
							var s = u.get(c);
							s != null ? s : "";
						}
				});
			}
			return parts.join("\x1f");
		}
		ensureDense();
		for (lv in _levels) {
			parts.push(switch (lv) {
				case F64(idx): keyF64(idx.get(i));
				case Str(idx):
					var s = idx.get(i);
					s != null ? s : "";
			});
		}
		return parts.join("\x1f");
	}
}
