package musescript.vm;

import musescript.ast.Expr;
import musescript.ast.Stmt;
import musescript.ast.Const;
import musescript.ast.OrderKind;
import musescript.types.BuiltinSigs;

/**
 * Thrown when a program (or subtree) falls outside the P0 VM subset. The subset
 * boundary is DETERMINISTIC (SPEC_BYTECODE_VM.md §8): a program either compiles
 * whole or throws, so the oracle/fitness caller can cleanly fall back to the
 * tree-walking `MuseInterp` for the tail without any half-compiled ambiguity.
 */
class VmUnsupported {
	public var reason:String;
	public function new(reason:String) this.reason = reason;
	public function toString():String return "VmUnsupported: " + reason;
}

/**
 * AST → stack-bytecode compiler for the P0 subset: strategy `onBar` bodies made
 * of consts, bar fields, arithmetic/compare/logic (`MuseVmOps` semantics),
 * unary `!`/`-`, local assignment (`Assign`/`var`/`=`), `if`/ternary, `when`,
 * and `long`/`short`/`flat` orders — NO indicators, lookback, calls, match,
 * generators, objects, classes, loops (those throw `VmUnsupported` → interp
 * fallback).
 *
 * Lowers the SAME post-`CallsiteIds` AST the interp executes (§8): P0's parity
 * guarantee is tightest when both tiers consume one AST; the `ConstFold`/CSE
 * optimizer passes are upstream and shared, so lowering here composes with them.
 */
class MuseBytecodeCompiler {
	var code:Array<Int> = [];
	var consts:Array<Dynamic> = [];
	var localSlots:Map<String, Int> = new Map();
	var localNames:Array<String> = [];

	static final BAR_FIELDS:Map<String, Int> = [
		"open" => Op.FIELD_OPEN, "high" => Op.FIELD_HIGH, "low" => Op.FIELD_LOW,
		"close" => Op.FIELD_CLOSE, "volume" => Op.FIELD_VOLUME, "time" => Op.FIELD_TIME,
		"bar_index" => Op.FIELD_BAR_INDEX
	];

	// Lazily-built reference globals (scratch harness) for the compile-time
	// "is this a plain-function builtin?" check. Same install as the VM runtime
	// globals, so a name that compiles to CALL_BUILTIN here resolves to a real
	// function there. Function identity is harness-independent, so a scratch
	// harness is fine for the capability decision.
	static var refGlobals:Null<Map<String, Dynamic>> = null;
	static function isPlainBuiltin(name:String):Bool {
		if (refGlobals == null) refGlobals = MuseVmBuiltins.scratch();
		return refGlobals.exists(name) && Reflect.isFunction(refGlobals.get(name));
	}

	// series-name for `series[n]` lookback — bar field / ident / parenthesized (matches the
	// interp's `evalLookback` EBarField|EIdent case, which reads the series buffer by name).
	static function lookbackSeriesName(series:Expr):Null<String> {
		return switch (series) {
			case EBarField(n) | EIdent(n): n;
			case EParent(inner): lookbackSeriesName(inner);
			default: null;
		}
	}

	static function csCode(name:String):Int {
		return switch (name) {
			case "crossover": Op.CS_CROSSOVER;
			case "crossunder": Op.CS_CROSSUNDER;
			case "rising": Op.CS_RISING;
			case "falling": Op.CS_FALLING;
			default: -1;
		}
	}

	static function scrCode(name:String):Int {
		return switch (name) {
			case "macd": Op.SCR_MACD;
			case "bbands": Op.SCR_BBANDS;
			case "stoch": Op.SCR_STOCH;
			default: -1;
		}
	}

	// TB0 + widen: indicators eligible for static IND dispatch — exactly the
	// `TradeBuiltins` statics `install` registers under these names. NOT `hma`
	// (registered elsewhere) and NOT the __cs/__scr callsite-stateful ones.
	static final IND_CODES:Map<String, Int> = [
		"sma" => Op.IND_SMA, "ema" => Op.IND_EMA, "rsi" => Op.IND_RSI, "atr" => Op.IND_ATR,
		"highest" => Op.IND_HIGHEST, "lowest" => Op.IND_LOWEST, "stdev" => Op.IND_STDEV,
		"wma" => Op.IND_WMA, "rma" => Op.IND_RMA, "roc" => Op.IND_ROC, "mom" => Op.IND_MOM,
		"change" => Op.IND_CHANGE, "pct_change" => Op.IND_PCT_CHANGE,
		"slope" => Op.IND_SLOPE, "zscore_roll" => Op.IND_ZSCORE_ROLL, "percent_rank" => Op.IND_PERCENT_RANK,
		"ewm_var" => Op.IND_EWM_VAR, "ewm_stdev" => Op.IND_EWM_STDEV,
		"hl2" => Op.IND_HL2, "hlc3" => Op.IND_HLC3, "ohlc4" => Op.IND_OHLC4, "vwap" => Op.IND_VWAP
	];
	static final IND_ZERO_ARG:Map<Int, Bool> = [
		Op.IND_HL2 => true, Op.IND_HLC3 => true, Op.IND_OHLC4 => true, Op.IND_VWAP => true
	];

	static function unwrapParent(e:Expr):Expr {
		return switch (e) { case EParent(x): unwrapParent(x); default: e; }
	}

	function new() {}

	/**
	 * Compile the concatenation of a strategy's `onBar` handler bodies into one
	 * chunk. Throws `VmUnsupported` if any statement is outside the subset.
	 */
	public static function compileOnBar(bodies:Array<Array<Stmt>>):MuseChunk {
		var c = new MuseBytecodeCompiler();
		for (body in bodies) c.prescanLocals(body);
		for (body in bodies) for (s in body) c.stmt(s);
		c.emit(Op.HALT);
		return new MuseChunk(c.code, c.consts, c.localNames);
	}

	// ---- local-slot pre-scan (assignment discovery order = slot order) ----

	function slotFor(name:String):Int {
		if (BAR_FIELDS.exists(name))
			throw new VmUnsupported('local shadows bar field "$name"');
		if (localSlots.exists(name)) return localSlots.get(name);
		var slot = localNames.length;
		localSlots.set(name, slot);
		localNames.push(name);
		return slot;
	}

	function prescanLocals(stmts:Array<Stmt>):Void {
		for (s in stmts) switch (s) {
			case Assign(name, e): slotFor(name); prescanLocalsExpr(e);
			case ExprStmt(e): prescanLocalsExpr(e);
			case When(cond, body): prescanLocalsExpr(cond); prescanLocals(body);
			case Block(inner): prescanLocals(inner);
			case Order(_, args): for (a in args) prescanLocalsExpr(a);
			default: // leave for stmt() to reject with a precise reason
		}
	}

	function prescanLocalsExpr(e:Expr):Void {
		if (e == null) return;
		switch (e) {
			case EVar(name, init): slotFor(name); if (init != null) prescanLocalsExpr(init);
			case EBinop("=", EIdent(name), b): slotFor(name); prescanLocalsExpr(b);
			case EBinop(_, a, b): prescanLocalsExpr(a); prescanLocalsExpr(b);
			case EUnop(_, _, x): prescanLocalsExpr(x);
			case EParent(x): prescanLocalsExpr(x);
			case EIf(c, t, el): prescanLocalsExpr(c); prescanLocalsExpr(t); if (el != null) prescanLocalsExpr(el);
			case ETernary(c, t, el): prescanLocalsExpr(c); prescanLocalsExpr(t); prescanLocalsExpr(el);
			case EBlock(es): for (x in es) prescanLocalsExpr(x);
			case ECall(callee, args): prescanLocalsExpr(callee); for (a in args) prescanLocalsExpr(a);
			case EMeta(_, margs, inner): for (a in margs) prescanLocalsExpr(a); prescanLocalsExpr(inner);
			case ELookback(series, nExpr): prescanLocalsExpr(series); prescanLocalsExpr(nExpr);
			case EField(obj, _): prescanLocalsExpr(obj);
			default:
		}
	}

	// ---- emit helpers ----

	inline function emit(op:Int):Void code.push(op);

	function constIndex(v:Dynamic):Int {
		var i = consts.length;
		consts.push(v);
		return i;
	}

	// P1b superinstruction: emit "jump-if-condition-false" for a JUST-compiled `cond`, fusing a
	// trailing comparison into CMP_JZ (`cmp; JZ` ≡ `CMP_JZ cmp` — byte-identical). Decided from the
	// AST, never by peeking the last bytecode Int (an operand could numerically equal a cmp opcode):
	// if `cond` is `EBinop(<cmp>, …)` (mod EParent), its last emitted op is provably that cmp, so
	// popping it is safe. Returns the jump-target operand index to backpatch.
	function emitCondJZ(cond:Expr):Int {
		var cmp = condCmpCode(cond);
		if (cmp >= 0) { code.pop(); emit(Op.CMP_JZ); emit(cmp); }
		else emit(Op.JZ);
		var patch = code.length; emit(0);
		return patch;
	}

	static function condCmpCode(cond:Expr):Int {
		return switch (cond) {
			case EParent(inner): condCmpCode(inner);
			case EBinop(op, _, _): switch (op) {
				case "<": Op.LT; case "<=": Op.LE; case ">": Op.GT; case ">=": Op.GE; case "==": Op.EQ; case "!=": Op.NE;
				default: -1;
			};
			default: -1;
		}
	}

	// ---- TB0: static indicator lowering ----

	// The series NAME an IND callsite would pass, IFF it is exactly what the
	// generic CALL_BUILTIN path passes for this arg: a series-typed bar-field
	// ident resolves via `BuiltinSigs.seriesNameOf` (the same call the generic
	// path makes); a string literal is the same string under either path. A
	// bar-field ident in a NON-series-typed position must NOT lower (the
	// generic path would pass the current-bar float, not the name) ⇒ null.
	static function indSeriesConst(name:String, i:Int, arg:Expr):Null<String> {
		if (BuiltinSigs.wantsSeries(name, i)) {
			var sn = BuiltinSigs.seriesNameOf(arg);
			if (sn != null) return sn;
		}
		return switch (unwrapParent(arg)) {
			case EConst(CString(s)): s;
			default: null;
		}
	}

	// Emit `IND` for a fully-static indicator callsite: series arg resolves to a
	// compile-time name AND the (optional) length/offset param is an Int literal.
	// Anything else — dynamic params, raw-array series, weird arities — returns
	// false and stays on the generic CALL_BUILTIN path, so lowering can never
	// change which values reach the builtin (parity by construction).
	function tryLowerInd(name:String, args:Array<Expr>):Bool {
		var ind = IND_CODES.get(name);
		if (ind == null) return false;
		// 0-arg bar helpers (hl2/hlc3/ohlc4/vwap) — no series/param immediates.
		if (IND_ZERO_ARG.exists(ind)) {
			if (args.length != 0) return false;
			emit(Op.IND); emit(ind); emit(constIndex("")); emit(0);
			return true;
		}
		var optionalParam = (ind == Op.IND_CHANGE || ind == Op.IND_PCT_CHANGE);
		if (optionalParam) {
			if (args.length < 1 || args.length > 2) return false;
		} else if (args.length != 2) {
			return false;
		}
		var sname = indSeriesConst(name, 0, args[0]);
		if (sname == null) return false;
		var p1:Null<Int> = null;
		if (args.length == 2) {
			if (BuiltinSigs.wantsSeries(name, 1)) return false;
			switch (unwrapParent(args[1])) {
				case EConst(CInt(k)): p1 = k;
				default: return false;
			}
		}
		emit(Op.IND); emit(ind); emit(constIndex(sname));
		if (p1 != null) { emit(1); emit(p1); } else emit(0);
		return true;
	}

	function emitBuiltinCall(name:String, args:Array<Expr>):Void {
		// Cliff 4/2/PD — ND create + packed pd_rank1d + Series/Frame H are OBJ-lane;
		// scalar mean/sum/min/max/prod/std/var/size/ndim/dot/get_flat / pd_nrows/ncols
		// are B onto nums. Index / merge_asof / over-cap / open forms → U.
		// No NdArray / DataFrame / Dynamic on the nums lane.
		if (VmPdEligibility.isHeapPd(name)) {
			if (!VmPdEligibility.arityOk(name, args.length))
				throw new VmUnsupported('heap PD "$name" arity ${args.length}');
			assertHeapPdShapeOk(name, args);
			emitHeapPdArgs(name, args);
			emit(Op.CALL_BUILTIN); emit(constIndex(name)); emit(args.length);
			return;
		}
		if (VmPdEligibility.isScalarB(name)) {
			if (!VmPdEligibility.arityOk(name, args.length))
				throw new VmUnsupported('scalar PD "$name" arity ${args.length}');
			switch (name) {
				case "pd_series_length" | "pd_series_name":
					assertSeriesHandleOk(args[0], name);
				default:
					assertFrameHandleOk(args[0], name);
			}
			for (a in args) expr(a);
			emit(Op.CALL_BUILTIN); emit(constIndex(name)); emit(args.length);
			return;
		}
		if (VmPdEligibility.isPdBuiltin(name))
			throw new VmUnsupported('pd builtin "$name" (TIndex / opaque / ungated frame — VM U)');
		if (VmNpEligibility.isHeapNd(name)) {
			if (!VmNpEligibility.arityOk(name, args.length))
				throw new VmUnsupported('heap ND "$name" arity ${args.length}');
			assertHeapNdShapeOk(name, args);
			for (a in args) emitHeapNdArg(a);
			emit(Op.CALL_BUILTIN); emit(constIndex(name)); emit(args.length);
			return;
		}
		if (VmNpEligibility.isNpBuiltin(name)) {
			if (!VmNpEligibility.isScalarB(name) || !VmNpEligibility.arityOk(name, args.length))
				throw new VmUnsupported('np builtin "$name" (NdArray-returning / non-scalar — VM U)');
		} else if (VmNpEligibility.isHeapProducer(name)
				&& !VmNpEligibility.arityOk(name, args.length)) {
			throw new VmUnsupported('heap producer "$name" arity ${args.length}');
		}
		// TB0 fast path: fully-static indicator callsite → single IND op with immediates.
		// Falls through to the generic CALL_BUILTIN when the shape doesn't qualify.
		if (tryLowerInd(name, args)) return;
		for (i in 0...args.length) {
			var sn = BuiltinSigs.wantsSeries(name, i) ? BuiltinSigs.seriesNameOf(args[i]) : null;
			if (sn != null) { emit(Op.CONST); emit(constIndex(sn)); }
			else expr(args[i]);
		}
		emit(Op.CALL_BUILTIN); emit(constIndex(name)); emit(args.length);
	}

	/**
	 * Cliff-PD: packed `pd_rank1d` + Series / Frame lane with len ≤ MAX_WIN.
	 * Constvec / window / ND·Series·Frame handles; Index / open forms **U**.
	 */
	function assertHeapPdShapeOk(name:String, args:Array<Expr>):Void {
		switch (name) {
			case "pd_rank1d":
				assertPdPackedDataOk(args[0], "pd_rank1d");
				if (args.length >= 2) {
					switch (unwrapParent(args[1])) {
						case EConst(CBool(_)) | EIdent("true") | EIdent("false"):
						default:
							throw new VmUnsupported('pd_rank1d pct needs const bool (VM U)');
					}
				}
			case "pd_series":
				assertPdPackedDataOk(args[0], "pd_series");
				assertPdSeriesCtorExtrasOk(args);
			case "pd_shift":
				assertShiftHandleOk(args[0], "pd_shift");
				if (args.length >= 2) {
					switch (unwrapParent(args[1])) {
						case EConst(CInt(k)):
							if (!VmPdEligibility.fitsShiftPeriods(k))
								throw new VmUnsupported('pd_shift periods $k > ${VmPdEligibility.MAX_WIN} (VM U)');
						default:
							throw new VmUnsupported('pd_shift periods needs const int (VM U)');
					}
				}
			case "pd_series_values":
				assertSeriesHandleOk(args[0], "pd_series_values");
			case "pd_from_columns":
				assertFromColumnsOk(args[0]);
			case "pd_get":
				assertFrameHandleOk(args[0], "pd_get");
				assertConstStringOk(args[1], "pd_get col");
			case "pd_xs_rank":
				assertFrameHandleOk(args[0], "pd_xs_rank");
				if (args.length >= 2) {
					switch (unwrapParent(args[1])) {
						case EConst(CBool(_)) | EIdent("true") | EIdent("false"):
						default:
							throw new VmUnsupported('pd_xs_rank pct needs const bool (VM U)');
					}
				}
			case "pd_groupby_mean" | "pd_groupby_sum" | "pd_groupby_std":
				assertFrameHandleOk(args[0], name);
				assertConstStringOk(args[1], '$name by');
			case "pd_groupby_agg":
				assertFrameHandleOk(args[0], "pd_groupby_agg");
				assertConstStringOk(args[1], "pd_groupby_agg by");
				if (args.length >= 3) {
					var fn = constStringValue(args[2]);
					if (fn == null)
						throw new VmUnsupported('pd_groupby_agg fn needs const string (VM U)');
					if (!VmPdEligibility.isGroupbyAggFn(fn))
						throw new VmUnsupported('pd_groupby_agg fn "$fn" (VM U)');
				}
			case "pd_join":
				assertFrameHandleOk(args[0], "pd_join");
				assertFrameHandleOk(args[1], "pd_join");
				assertConstStringOk(args[2], "pd_join on");
				if (args.length >= 4) {
					var how = constStringValue(args[3]);
					if (how == null)
						throw new VmUnsupported('pd_join how needs const string (VM U)');
					if (!VmPdEligibility.isJoinHow(how))
						throw new VmUnsupported('pd_join how "$how" (VM U)');
				}
			default:
				null;
		}
	}

	/** Constvec / window / ND handle data for `pd_rank1d` / `pd_series` (≤ MAX_WIN). */
	function assertPdPackedDataOk(data:Expr, op:String):Void {
		switch (unwrapParent(data)) {
			case EArrayDecl(vs):
				if (!VmPdEligibility.fitsWin(vs.length))
					throw new VmUnsupported('$op len ${vs.length} > ${VmPdEligibility.MAX_WIN} (VM U)');
				if (!isConstScalarArray(vs))
					throw new VmUnsupported('$op needs const 1-D data (VM U)');
			case ECall(EIdent("window"), wargs):
				if (wargs.length != 2)
					throw new VmUnsupported('$op(window) arity (VM U)');
				switch (unwrapParent(wargs[1])) {
					case EConst(CInt(k)):
						if (!VmPdEligibility.fitsWin(k))
							throw new VmUnsupported('$op(window) len $k > ${VmPdEligibility.MAX_WIN} (VM U)');
					default:
						throw new VmUnsupported('$op(window) needs const len (VM U)');
				}
			case EIdent(_):
				// Existing OBJ-lane ND / Array handle — length checked when created.
				null;
			case ECall(EIdent(inner), _) if (
				VmNpEligibility.isHeapNd(inner)
				|| VmNpEligibility.isHeapProducer(inner)
				|| inner == "pd_rank1d"
				|| inner == "pd_series_values"
				|| VmPdEligibility.isHeapSeries(inner)
			):
				null;
			default:
				throw new VmUnsupported('$op operand not a constvec/window/handle (VM U)');
		}
	}

	/** Series OBJ handle: local, `pd_series` / `pd_get`, or Series-shaped `pd_shift`. */
	function assertSeriesHandleOk(data:Expr, op:String):Void {
		switch (unwrapParent(data)) {
			case EIdent(_):
				null;
			case ECall(EIdent(inner), _) if (VmPdEligibility.isHeapSeries(inner)):
				null;
			case ECall(EIdent("pd_shift"), sargs) if (sargs.length >= 1):
				assertSeriesHandleOk(sargs[0], op);
			default:
				throw new VmUnsupported('$op needs Series handle (pd_series/pd_get/Series pd_shift) (VM U)');
		}
	}

	/** Frame OBJ handle: local, frame HEAP_PD, or frame-shaped `pd_shift`. */
	function assertFrameHandleOk(data:Expr, op:String):Void {
		switch (unwrapParent(data)) {
			case EIdent(_):
				null;
			case ECall(EIdent(inner), _) if (VmPdEligibility.isHeapFrame(inner)):
				null;
			case ECall(EIdent("pd_shift"), sargs) if (sargs.length >= 1):
				assertFrameHandleOk(sargs[0], op);
			default:
				throw new VmUnsupported('$op needs Frame handle (pd_from_columns/xs_rank/groupby/join) (VM U)');
		}
	}

	/** Series or Frame handle for dual `pd_shift`. */
	function assertShiftHandleOk(data:Expr, op:String):Void {
		switch (unwrapParent(data)) {
			case EIdent(_):
				null;
			case ECall(EIdent(inner), _) if (
				VmPdEligibility.isHeapSeries(inner) || VmPdEligibility.isHeapFrame(inner)
			):
				null;
			case ECall(EIdent("pd_shift"), sargs) if (sargs.length >= 1):
				assertShiftHandleOk(sargs[0], op);
			default:
				throw new VmUnsupported('$op needs Series or Frame handle (VM U)');
		}
	}

	/** Const `{col: [f64…], …}` for `pd_from_columns` (nrows/ncols ≤ MAX_WIN). */
	function assertFromColumnsOk(data:Expr):Void {
		switch (unwrapParent(data)) {
			case EObject(fields):
				if (fields.length == 0)
					throw new VmUnsupported('pd_from_columns empty object (VM U)');
				if (!VmPdEligibility.fitsWin(fields.length))
					throw new VmUnsupported('pd_from_columns ncols ${fields.length} > ${VmPdEligibility.MAX_WIN} (VM U)');
				var nrows = -1;
				for (f in fields) {
					switch (unwrapParent(f.e)) {
						case EArrayDecl(vs):
							if (!VmPdEligibility.fitsWin(vs.length))
								throw new VmUnsupported('pd_from_columns col "${f.name}" len ${vs.length} > ${VmPdEligibility.MAX_WIN} (VM U)');
							if (!isConstScalarArray(vs))
								throw new VmUnsupported('pd_from_columns col "${f.name}" needs const 1-D data (VM U)');
							if (nrows < 0) nrows = vs.length;
							else if (vs.length != nrows)
								throw new VmUnsupported('pd_from_columns ragged columns (VM U)');
						default:
							throw new VmUnsupported('pd_from_columns col "${f.name}" needs const array (VM U)');
					}
				}
			default:
				throw new VmUnsupported('pd_from_columns needs const column object (VM U)');
		}
	}

	static function assertConstStringOk(e:Expr, label:String):Void {
		if (constStringValue(e) == null)
			throw new VmUnsupported('$label needs const string (VM U)');
	}

	static function constStringValue(e:Expr):Null<String> {
		return switch (unwrapParent(e)) {
			case EConst(CString(s)): s;
			default: null;
		};
	}

	/** Const column object → anonymous Dynamic map for PdBuiltins.fromColumns. */
	static function constColumnObject(fields:Array<{name:String, e:Expr}>):Dynamic {
		var o:Dynamic = {};
		for (f in fields) {
			switch (unwrapParent(f.e)) {
				case EArrayDecl(vs):
					Reflect.setField(o, f.name, constScalarArray(vs));
				default:
					throw new VmUnsupported('pd_from_columns non-const col');
			}
		}
		return o;
	}

	/** Emit PD heap args: const array/object → CONST pool; pct/periods/strings → CONST; else expr. */
	function emitHeapPdArgs(name:String, args:Array<Expr>):Void {
		switch (name) {
			case "pd_rank1d":
				emitHeapNdArg(args[0]);
				if (args.length >= 2) emitConstBoolArg(args[1]);
			case "pd_series":
				emitHeapNdArg(args[0]);
				if (args.length >= 2) emitPdSeriesIndexOrNameArg(args[1]);
				if (args.length >= 3) emitPdSeriesNameArg(args[2]);
			case "pd_shift":
				expr(args[0]);
				if (args.length >= 2) {
					switch (unwrapParent(args[1])) {
						case EConst(CInt(k)):
							emit(Op.CONST); emit(constIndex(k));
						default:
							expr(args[1]);
					}
				}
			case "pd_series_values":
				expr(args[0]);
			case "pd_from_columns":
				switch (unwrapParent(args[0])) {
					case EObject(fields):
						emit(Op.CONST); emit(constIndex(constColumnObject(fields)));
					default:
						expr(args[0]);
				}
			case "pd_get":
				expr(args[0]);
				emitConstStringArg(args[1]);
			case "pd_xs_rank":
				expr(args[0]);
				if (args.length >= 2) emitConstBoolArg(args[1]);
			case "pd_groupby_mean" | "pd_groupby_sum" | "pd_groupby_std":
				expr(args[0]);
				emitConstStringArg(args[1]);
			case "pd_groupby_agg":
				expr(args[0]);
				emitConstStringArg(args[1]);
				if (args.length >= 3) emitConstStringArg(args[2]);
			case "pd_join":
				expr(args[0]);
				expr(args[1]);
				emitConstStringArg(args[2]);
				if (args.length >= 4) emitConstStringArg(args[3]);
			default:
				for (a in args) expr(a);
		}
	}

	function emitConstBoolArg(e:Expr):Void {
		switch (unwrapParent(e)) {
			case EConst(CBool(b)):
				emit(Op.CONST); emit(constIndex(b));
			case EIdent("true"):
				emit(Op.CONST); emit(constIndex(true));
			case EIdent("false"):
				emit(Op.CONST); emit(constIndex(false));
			default:
				expr(e);
		}
	}

	function emitConstStringArg(e:Expr):Void {
		switch (unwrapParent(e)) {
			case EConst(CString(s)):
				emit(Op.CONST); emit(constIndex(s));
			default:
				expr(e);
		}
	}

	/**
	 * Gated Series ctor extras (arity 2–3):
	 *   • index = `null` | const F64/Str array whose len matches known data len ≤64
	 *   • 2-arg bare const string = name-only (host `series` treats String middle as name)
	 *   • name (3rd) = const string
	 * Index-heap (`pd_index_range`, …) / runtime / ragged → **U**.
	 */
	function assertPdSeriesCtorExtrasOk(args:Array<Expr>):Void {
		if (args.length <= 1) return;
		var knownLen = knownPackedDataLen(args[0]);
		if (args.length == 2) {
			switch (unwrapParent(args[1])) {
				case EConst(CNull) | EIdent("null"):
					null;
				case EConst(CString(_)):
					null; // name-only
				case EArrayDecl(vs):
					assertPdSeriesIndexArrayOk(vs, knownLen);
				default:
					throw new VmUnsupported('pd_series index/name needs const array|string|null (VM U)');
			}
			return;
		}
		// arity 3: index + name
		switch (unwrapParent(args[1])) {
			case EConst(CNull) | EIdent("null"):
				null;
			case EArrayDecl(vs):
				assertPdSeriesIndexArrayOk(vs, knownLen);
			default:
				throw new VmUnsupported('pd_series index needs const array|null (VM U)');
		}
		assertConstStringOk(args[2], "pd_series name");
	}

	function assertPdSeriesIndexArrayOk(vs:Array<Expr>, knownLen:Null<Int>):Void {
		if (!VmPdEligibility.fitsWin(vs.length))
			throw new VmUnsupported('pd_series index len ${vs.length} > ${VmPdEligibility.MAX_WIN} (VM U)');
		if (!(isConstScalarArray(vs) || isConstStringArray(vs)))
			throw new VmUnsupported('pd_series index needs const F64/Str array (VM U)');
		if (knownLen == null)
			throw new VmUnsupported('pd_series index needs known data len (constvec/window) (VM U)');
		if (vs.length != knownLen)
			throw new VmUnsupported('pd_series index len ${vs.length} != data len $knownLen (VM U)');
	}

	/** Known 1-D length for constvec / window Series data; null for bare handles. */
	static function knownPackedDataLen(data:Expr):Null<Int> {
		return switch (unwrapParent(data)) {
			case EArrayDecl(vs): vs.length;
			case ECall(EIdent("window"), wargs) if (wargs.length == 2):
				switch (unwrapParent(wargs[1])) {
					case EConst(CInt(k)): k;
					default: null;
				};
			default: null;
		};
	}

	function emitPdSeriesIndexOrNameArg(e:Expr):Void {
		switch (unwrapParent(e)) {
			case EConst(CNull) | EIdent("null"):
				emit(Op.CONST); emit(constIndex(null));
			case EConst(CString(s)):
				emit(Op.CONST); emit(constIndex(s));
			case EArrayDecl(vs) if (isConstScalarArray(vs)):
				emit(Op.CONST); emit(constIndex(constScalarArray(vs)));
			case EArrayDecl(vs) if (isConstStringArray(vs)):
				emit(Op.CONST); emit(constIndex(constStringArray(vs)));
			default:
				expr(e);
		}
	}

	function emitPdSeriesNameArg(e:Expr):Void {
		switch (unwrapParent(e)) {
			case EConst(CString(s)):
				emit(Op.CONST); emit(constIndex(s));
			case EConst(CNull) | EIdent("null"):
				emit(Op.CONST); emit(constIndex(null));
			default:
				expr(e);
		}
	}

	static function isConstStringArray(vs:Array<Expr>):Bool {
		if (vs.length == 0) return true;
		for (v in vs) {
			switch (unwrapParent(v)) {
				case EConst(CString(_)):
				default: return false;
			}
		}
		return true;
	}

	static function constStringArray(vs:Array<Expr>):Array<String> {
		var out:Array<String> = [];
		for (v in vs) {
			out.push(switch (unwrapParent(v)) {
				case EConst(CString(s)): s;
				default: throw new VmUnsupported("non-const string array elem");
			});
		}
		return out;
	}

	/**
	 * Cliff-2: ND-handle create / vec ufuncs / reshape / matmul (len ≤ MAX_WIN,
	 * matmul side ≤ MAX_MATMUL_SIDE). Runtime-element 1-D asarray allowed; multi-dim
	 * create / axis·keepdims / mismatched reshape product stay **U**.
	 */
	function assertHeapNdShapeOk(name:String, args:Array<Expr>):Void {
		switch (name) {
			case "np_zeros" | "np_ones":
				var n = constShape1dLen(args[0]);
				if (n == null)
					throw new VmUnsupported('$name needs const 1-D shape (VM U)');
				if (!VmNpEligibility.fitsWin(n))
					throw new VmUnsupported('$name len $n > ${VmNpEligibility.MAX_WIN} (VM U)');
			case "np_full":
				var fn = constShape1dLen(args[0]);
				if (fn == null)
					throw new VmUnsupported('np_full needs const 1-D shape (VM U)');
				if (!VmNpEligibility.fitsWin(fn))
					throw new VmUnsupported('np_full len $fn > ${VmNpEligibility.MAX_WIN} (VM U)');
				assertHeapNdScalarExpr(args[1], "np_full value");
			case "np_asarray" | "np_array":
				assertAsarray1dOk(args[0], name);
			case "np_add" | "np_subtract" | "np_multiply" | "np_divide"
				| "np_minimum" | "np_maximum":
				assertVec1dOperandOk(args[0], name);
				assertVec1dOperandOk(args[1], name);
			case "np_cumsum" | "np_diff" | "np_exp" | "np_log"
				| "np_negative" | "np_abs" | "np_sqrt" | "np_square" | "np_sign":
				assertVec1dOperandOk(args[0], name);
			case "np_clip":
				assertVec1dOperandOk(args[0], name);
				assertConstNumOk(args[1], "np_clip lo");
				assertConstNumOk(args[2], "np_clip hi");
			case "np_matmul":
				assertMatmulOperandOk(args[0], name);
				assertMatmulOperandOk(args[1], name);
			case "np_reshape":
				assertVec1dOperandOk(args[0], "np_reshape");
				var sh = constShapeDims(args[1]);
				if (sh == null)
					throw new VmUnsupported('np_reshape needs const shape (VM U)');
				var prod = 1;
				for (d in sh) {
					if (d < 0)
						throw new VmUnsupported('np_reshape negative dim (VM U)');
					prod *= d;
				}
				if (!VmNpEligibility.fitsWin(prod))
					throw new VmUnsupported('np_reshape size $prod > ${VmNpEligibility.MAX_WIN} (VM U)');
			default:
				null;
		}
	}

	/** Literal Int/Float for ops that mirror WASM const-bound gates (`np_clip`). */
	function assertConstNumOk(e:Expr, label:String):Void {
		switch (unwrapParent(e)) {
			case EConst(CInt(_)) | EConst(CFloat(_)):
				null;
			default:
				throw new VmUnsupported('$label needs const number (VM U)');
		}
	}

	/** 1-D asarray / array: const or runtime scalar elems / window / handle (len ≤ MAX_WIN). */
	function assertAsarray1dOk(data:Expr, op:String):Void {
		switch (unwrapParent(data)) {
			case EArrayDecl(vs):
				if (!VmNpEligibility.fitsWin(vs.length))
					throw new VmUnsupported('$op len ${vs.length} > ${VmNpEligibility.MAX_WIN} (VM U)');
				for (v in vs) {
					switch (unwrapParent(v)) {
						case EArrayDecl(_):
							throw new VmUnsupported('$op nested array / multi-dim (VM U)');
						default:
							assertHeapNdScalarExpr(v, '$op elem');
					}
				}
			case ECall(EIdent("window"), wargs):
				if (wargs.length != 2)
					throw new VmUnsupported('asarray(window) arity (VM U)');
				switch (unwrapParent(wargs[1])) {
					case EConst(CInt(k)):
						if (!VmNpEligibility.fitsWin(k))
							throw new VmUnsupported('asarray(window) len $k > ${VmNpEligibility.MAX_WIN} (VM U)');
					default:
						throw new VmUnsupported('asarray(window) needs const len (VM U)');
				}
			case EIdent(_):
				null;
			case ECall(EIdent(inner), _) if (VmNpEligibility.isHeapNd(inner) || VmNpEligibility.isHeapProducer(inner)):
				null;
			default:
				throw new VmUnsupported('$op operand not a vec/window/handle (VM U)');
		}
	}

	/** Same-length 1-D vec operand for add/exp/cumsum/reshape src. */
	function assertVec1dOperandOk(data:Expr, op:String):Void {
		switch (unwrapParent(data)) {
			case EArrayDecl(vs):
				if (!VmNpEligibility.fitsWin(vs.length))
					throw new VmUnsupported('$op len ${vs.length} > ${VmNpEligibility.MAX_WIN} (VM U)');
				for (v in vs) {
					switch (unwrapParent(v)) {
						case EArrayDecl(_):
							throw new VmUnsupported('$op nested array (VM U)');
						default:
							assertHeapNdScalarExpr(v, '$op elem');
					}
				}
			case ECall(EIdent("window"), wargs):
				if (wargs.length != 2)
					throw new VmUnsupported('$op(window) arity (VM U)');
				switch (unwrapParent(wargs[1])) {
					case EConst(CInt(k)):
						if (!VmNpEligibility.fitsWin(k))
							throw new VmUnsupported('$op(window) len $k > ${VmNpEligibility.MAX_WIN} (VM U)');
					default:
						throw new VmUnsupported('$op(window) needs const len (VM U)');
				}
			case EIdent(_):
				null;
			case ECall(EIdent(inner), _) if (VmNpEligibility.isHeapNd(inner) || VmNpEligibility.isHeapProducer(inner)):
				null;
			default:
				throw new VmUnsupported('$op operand not a vec/window/handle (VM U)');
		}
	}

	/** Matmul side: nested ≤8×8 row decl (const or runtime scalar cells) or ND handle. */
	function assertMatmulOperandOk(data:Expr, op:String):Void {
		switch (unwrapParent(data)) {
			case EArrayDecl(rows):
				if (rows.length == 0)
					throw new VmUnsupported('$op empty matrix (VM U)');
				if (!VmNpEligibility.fitsMatmulSide(rows.length))
					throw new VmUnsupported('$op rows ${rows.length} > ${VmNpEligibility.MAX_MATMUL_SIDE} (VM U)');
				var ncols = -1;
				for (r in rows) {
					switch (unwrapParent(r)) {
						case EArrayDecl(cells):
							if (!VmNpEligibility.fitsMatmulSide(cells.length))
								throw new VmUnsupported('$op cols ${cells.length} > ${VmNpEligibility.MAX_MATMUL_SIDE} (VM U)');
							if (ncols < 0) ncols = cells.length;
							else if (cells.length != ncols)
								throw new VmUnsupported('$op ragged matrix (VM U)');
							for (c in cells) assertHeapNdScalarExpr(c, '$op cell');
						default:
							throw new VmUnsupported('$op needs row array decls (VM U)');
					}
				}
			case EIdent(_):
				null;
			case ECall(EIdent(inner), _) if (VmNpEligibility.isHeapNd(inner)):
				null;
			default:
				throw new VmUnsupported('$op operand not a matrix/handle (VM U)');
		}
	}

	/** Scalar emitable on the VM expr subset (bar fields / locals / arith / const). */
	function assertHeapNdScalarExpr(e:Expr, label:String):Void {
		switch (unwrapParent(e)) {
			case EConst(CInt(_)) | EConst(CFloat(_)):
				null;
			case EBarField(_):
				null;
			case EIdent(name) if (BAR_FIELDS.exists(name) || localSlots.exists(name)):
				null;
			case EBinop(_, a, b):
				assertHeapNdScalarExpr(a, label);
				assertHeapNdScalarExpr(b, label);
			case EUnop(_, _, x):
				assertHeapNdScalarExpr(x, label);
			case EParent(x):
				assertHeapNdScalarExpr(x, label);
			case ECall(EIdent(n), cargs) if (VmNpEligibility.isScalarB(n)):
				if (!VmNpEligibility.arityOk(n, cargs.length))
					throw new VmUnsupported('$label nested $n arity (VM U)');
			default:
				throw new VmUnsupported('$label needs scalar expr (VM U)');
		}
	}

	/**
	 * HEAP_ND arg: const 1-D / nested matrix → CONST pool; runtime scalars /
	 * nested rows → PACK_ARRAY; else normal expr.
	 */
	function emitHeapNdArg(e:Expr):Void {
		switch (unwrapParent(e)) {
			case EArrayDecl(vs):
				if (isConstScalarArray(vs)) {
					emit(Op.CONST);
					emit(constIndex(constScalarArray(vs)));
				} else if (isConstNestedMatrix(vs)) {
					emit(Op.CONST);
					emit(constIndex(constNestedMatrix(vs)));
				} else {
					for (v in vs) emitHeapNdArg(v);
					emit(Op.PACK_ARRAY);
					emit(vs.length);
				}
			default:
				expr(e);
		}
	}

	static function isConstScalarArray(vs:Array<Expr>):Bool {
		for (v in vs) {
			switch (unwrapParent(v)) {
				case EConst(CInt(_)) | EConst(CFloat(_)):
				default: return false;
			}
		}
		return true;
	}

	static function constScalarArray(vs:Array<Expr>):Array<Float> {
		var out:Array<Float> = [];
		for (v in vs) {
			out.push(switch (unwrapParent(v)) {
				case EConst(CInt(i)): i * 1.0;
				case EConst(CFloat(f)): f;
				default: throw new VmUnsupported("non-const array elem");
			});
		}
		return out;
	}

	static function isConstNestedMatrix(rows:Array<Expr>):Bool {
		if (rows.length == 0) return false;
		for (r in rows) {
			switch (unwrapParent(r)) {
				case EArrayDecl(cells):
					if (!isConstScalarArray(cells)) return false;
				default:
					return false;
			}
		}
		return true;
	}

	static function constNestedMatrix(rows:Array<Expr>):Array<Dynamic> {
		var out:Array<Dynamic> = [];
		for (r in rows) {
			switch (unwrapParent(r)) {
				case EArrayDecl(cells):
					out.push(constScalarArray(cells));
				default:
					throw new VmUnsupported("non-const matrix row");
			}
		}
		return out;
	}

	/** Literal 1-D shape `n` or `[n]` — multi-dim / dynamic → null (**U**). */
	static function constShape1dLen(e:Expr):Null<Int> {
		return switch (unwrapParent(e)) {
			case EConst(CInt(n)): n;
			case EArrayDecl(vs) if (vs.length == 1):
				switch (unwrapParent(vs[0])) {
					case EConst(CInt(n)): n;
					default: null;
				};
			default: null;
		};
	}

	/** Const shape `n` / `[n,…]` — ints only; dynamic → null. */
	static function constShapeDims(e:Expr):Null<Array<Int>> {
		return switch (unwrapParent(e)) {
			case EConst(CInt(n)): [n];
			case EArrayDecl(vs):
				var dims:Array<Int> = [];
				for (v in vs) {
					switch (unwrapParent(v)) {
						case EConst(CInt(d)): dims.push(d);
						default: return null;
					}
				}
				dims;
			default: null;
		};
	}

	// ---- statements ----

	function stmt(s:Stmt):Void {
		switch (s) {
			case ExprStmt(e):
				expr(e);
				emit(Op.POP);
			case Assign(name, e):
				expr(e);
				emit(Op.STORE_LOCAL_S);
				emit(slotFor(name));
			case Order(kind, args):
				if (args.length > 1) throw new VmUnsupported("multi-arg order");
				var hasArg = args.length > 0;
				if (hasArg) expr(args[0]);
				emit(Op.ORDER);
				emit(switch (kind) {
					case Long: Op.VERB_LONG;
					case Short: Op.VERB_SHORT;
					case Flat | Close: Op.VERB_FLAT;
				});
				emit(hasArg ? 1 : 0);
			case When(cond, body):
				expr(cond);
				var patch = emitCondJZ(cond);
				for (st in body) stmt(st);
				code[patch] = code.length;
			case Block(inner):
				for (st in inner) stmt(st);
			default:
				throw new VmUnsupported("statement " + stmtName(s));
		}
	}

	// ---- expressions ----

	function expr(e:Expr):Void {
		if (e == null) { emit(Op.CONST); emit(constIndex(null)); return; }
		switch (e) {
			case EConst(c):
				emit(Op.CONST);
				emit(constIndex(constValue(c)));
			case EBarField(name):
				// StrategyParser lowers 0-arg series helpers to EBarField; bare `hl2` (not `hl2()`)
				// must still invoke TradeBuiltins.hl2 — same as MuseInterp.resolve + nullary auto-call.
				var zind = IND_CODES.get(name);
				if (zind != null && IND_ZERO_ARG.exists(zind)) {
					emitBuiltinCall(name, []);
				} else {
					emit(Op.BAR_FIELD);
					emit(barFieldCode(name));
				}
			case EIdent(name):
				if (BAR_FIELDS.exists(name)) { emit(Op.BAR_FIELD); emit(BAR_FIELDS.get(name)); }
				else if (localSlots.exists(name)) { emit(Op.LOAD_LOCAL); emit(localSlots.get(name)); }
				else throw new VmUnsupported('identifier "$name" (not a bar field or local)');
			case EVar(name, init):
				if (init != null) expr(init) else { emit(Op.CONST); emit(constIndex(null)); }
				var slot = slotFor(name);
				emit(Op.STORE_LOCAL); emit(slot);
				emit(Op.LOAD_LOCAL); emit(slot); // EVar is an expression: leaves its value
			case EParent(x):
				expr(x);
			case EBinop("=", EIdent(name), b):
				expr(b);
				var slot = slotFor(name);
				emit(Op.STORE_LOCAL_S); emit(slot);
				emit(Op.LOAD_LOCAL); emit(slot);
			case EBinop("&&", a, b):
				expr(a); expr(b); emit(Op.AND);
			case EBinop("||", a, b):
				expr(a); expr(b); emit(Op.OR);
			case EBinop(op, a, b):
				expr(a); expr(b); emit(binopCode(op));
			case EUnop("!", _, x):
				expr(x); emit(Op.NOT);
			case EUnop("-", _, x):
				expr(x); emit(Op.NEG);
			case EUnop(op, _, _):
				throw new VmUnsupported('unary "$op"');
			case EIf(cond, eif, eelse):
				expr(cond);
				var toElse = emitCondJZ(cond);
				expr(eif);
				emit(Op.JMP); var toEnd = code.length; emit(0);
				code[toElse] = code.length;
				if (eelse != null) expr(eelse) else { emit(Op.CONST); emit(constIndex(null)); }
				code[toEnd] = code.length;
			case ETernary(cond, eif, eelse):
				expr(cond);
				var toElse = emitCondJZ(cond);
				expr(eif);
				emit(Op.JMP); var toEnd = code.length; emit(0);
				code[toElse] = code.length;
				expr(eelse);
				code[toEnd] = code.length;
			case EBlock(es):
				if (es.length == 0) { emit(Op.CONST); emit(constIndex(null)); return; }
				for (i in 0...es.length) {
					expr(es[i]);
					if (i < es.length - 1) emit(Op.POP);
				}
			// `__cs` stateful-callsite builtins (crossover/crossunder/rising/falling): args via
			// plain `expr()` (matching interp's plain `evalExpr` — NOT series-name resolution), then
			// CROSS with the CallsiteIds id as an immediate. The interp's `__cs` case for a
			// user-@indicator IndicatorInstance (runtime `globals` check) is NOT handled ⇒ fallback.
			case EMeta("__cs", [EConst(CInt(csId))], ECall(EIdent(csName), csArgs)) if (csCode(csName) >= 0):
				if (csName == "crossover" || csName == "crossunder") {
					if (csArgs.length != 2) throw new VmUnsupported('$csName arity ${csArgs.length}');
				} else if (csArgs.length < 2 || csArgs.length > 3) {
					throw new VmUnsupported('$csName arity ${csArgs.length}');
				}
				for (a in csArgs) expr(a);
				emit(Op.CROSS); emit(csId); emit(csCode(csName)); emit(csArgs.length);
			// Plain builtin call (`sma`/`ema`/registry indicators): STATIC series-name arg
			// resolution — a series-typed arg whose AST names a bar series (`BuiltinSigs.seriesNameOf`,
			// a pure function) lowers to `CONST "<name>"`; otherwise the arg's bytecode. Then
			// CALL_BUILTIN resolves the same function the interp's `callValue` plain-fn path does.
			// A local shadowing the name, or a non-plain-function global (IndicatorInstance/closure),
			// is out of subset ⇒ fallback (deterministic).
			// StrategyParser also lowers 0-arg series helpers (`hl2`/`hlc3`/`ohlc4`) to `EBarField`,
			// so `hl2()` arrives as `ECall(EBarField("hl2"), [])` — accept that callee shape too.
			case ECall(EIdent(name), args) if (!localSlots.exists(name) && isPlainBuiltin(name)):
				emitBuiltinCall(name, args);
			case ECall(EBarField(name), args) if (!localSlots.exists(name) && isPlainBuiltin(name)):
				emitBuiltinCall(name, args);
			// `series[n]` — `ELookback`. Interp: `evalLookback(series, Std.int(evalExpr(n)))`.
			// Bar-field/ident → LOOKBACK (series buffer by name). ECall/other → WITH_OFFSET
			// wrapping the series sub-expr (same `harness.withSeriesOffset` re-entrancy as interp).
			case ELookback(series, nExpr):
				var sname = lookbackSeriesName(series);
				if (sname != null) {
					expr(nExpr);
					emit(Op.LOOKBACK); emit(constIndex(sname));
				} else {
					expr(nExpr);
					emit(Op.WITH_OFFSET);
					var endPatch = code.length; emit(0);
					expr(series);
					code[endPatch] = code.length;
				}
			// `__scr` multi-output indicators (macd/bbands/stoch): fill a per-callsite scratch object
			// (`indCols.scratchObj(scrId)`) and return it — the fields are read via EField below.
			// Args via plain `expr()` (interp uses plain evalExpr; SERIES applies Std.int per-indicator
			// at runtime, matching the interp's exact default handling).
			case EMeta("__scr", [EConst(CInt(scrId))], ECall(EIdent(scrName), scrArgs)) if (scrCode(scrName) >= 0):
				if (scrName == "bbands" && scrArgs.length < 2) throw new VmUnsupported("bbands needs a period arg");
				for (a in scrArgs) expr(a);
				emit(Op.SERIES); emit(scrId); emit(scrCode(scrName)); emit(scrArgs.length);
			// `obj.field` — bare field read (multi-output indicator / scratch object). Matches the
			// interp's `EField` case: `evalExpr(obj)` then `Reflect.getProperty`. Method calls
			// (`ECall(EField(...))`) are NOT this case and stay out of subset.
			case EField(obj, f):
				expr(obj);
				emit(Op.GET_FIELD); emit(constIndex(f));
			default:
				throw new VmUnsupported("expression " + exprName(e));
		}
	}

	// ---- small mappers ----

	static function constValue(c:Const):Dynamic {
		return switch (c) {
			case CInt(i): i;
			case CFloat(f): f;
			case CString(s): s;
			case CBool(b): b;
			case CNull: null;
		}
	}

	static function barFieldCode(name:String):Int {
		if (!BAR_FIELDS.exists(name)) throw new VmUnsupported('bar field "$name"');
		return BAR_FIELDS.get(name);
	}

	static function binopCode(op:String):Int {
		return switch (op) {
			case "+": Op.ADD; case "-": Op.SUB; case "*": Op.MUL; case "/": Op.DIV; case "%": Op.MOD;
			case "<": Op.LT; case "<=": Op.LE; case ">": Op.GT; case ">=": Op.GE;
			case "==": Op.EQ; case "!=": Op.NE;
			default: throw new VmUnsupported('binop "$op"');
		}
	}

	static function stmtName(s:Stmt):String {
		return switch (s) {
			case OnBar(_): "OnBar"; case OnPosition(_): "OnPosition"; case OnTick(_): "OnTick";
			case OnEvent(_, _): "OnEvent"; case ForIn(_, _, _): "ForIn"; case MatchFor(_, _, _): "MatchFor";
			case Return(_): "Return"; case Yield(_): "Yield"; case YieldStar(_): "YieldStar";
			case Use(_, _): "Use"; default: "?";
		}
	}

	static function exprName(e:Expr):String {
		return switch (e) {
			case ECall(_, _): "ECall"; case ELookback(_, _): "ELookback"; case EMeta(n, _, _): 'EMeta($n)';
			case EMatch(_, _): "EMatch"; case EField(_, _): "EField"; case EArray(_, _): "EArray";
			case ENew(_, _): "ENew"; case EWhile(_, _): "EWhile"; case EFor(_, _, _): "EFor";
			case EFunction(_, _, _, _): "EFunction"; case EObject(_): "EObject"; case EArrayDecl(_): "EArrayDecl";
			case EYield(_): "EYield"; case EYieldStar(_): "EYieldStar"; case EReturn(_): "EReturn";
			case EThis: "EThis"; case ESuper(_, _): "ESuper"; default: "?";
		}
	}
}
