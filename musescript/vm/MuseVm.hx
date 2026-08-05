package musescript.vm;

import musescript.ast.MuseProgram;
import musescript.ast.Stmt;
import musescript.harness.HarnessContext;
import musescript.harness.Bar;
import musescript.harness.BarFeed;
import musescript.harness.BacktestResult;
import musescript.builtins.TradeBuiltins;
import musescript.compile.CallsiteIds;
import musescript.vm.MuseBytecodeCompiler.VmUnsupported;

/**
 * Tier-A portable stack VM (SPEC_BYTECODE_VM.md §1, Tier A) — the compile-once
 * replacement for the tree-walking `MuseInterp` on the evo hot path. Runs a
 * `MuseChunk` (from `MuseBytecodeCompiler`) against a real `HarnessContext`,
 * submitting orders through the SAME `OrderSim` the interp uses, so a full
 * backtest driven by this VM is byte-identical to the interp's for the covered
 * subset — the parity gate (`TestBytecodeVmParity`, §4) enforces it.
 *
 * P1.1: tagged unboxed numeric operand stack (`nums`/`tags`/`objs`) — arithmetic,
 * compares, bar fields, IND/LOOKBACK hit `Float` storage without per-op
 * `Dynamic` boxing/`MuseVmOps.toNum` classification. Bools/strings/objects stay
 * on the object lane. Observable values still match `MuseVmOps` / interp.
 * Dispatch stays a single `runLoop` (no per-opcode call) — WITH_OFFSET re-enters
 * the same loop for `withSeriesOffset` lookbacks.
 */
class MuseVm {
	static inline var TAG_NUM = 0;
	static inline var TAG_BOOL = 1;
	static inline var TAG_OBJ = 2;
	static inline var STACK_CAP = 256;

	final harness:HarnessContext;
	final chunk:MuseChunk;
	final locals:Array<Dynamic>;
	// P1.1 tagged stack — fixed-capacity vectors; `sp` is the live top.
	final tags:haxe.ds.Vector<Int>;
	final nums:haxe.ds.Vector<Float>;
	final objs:haxe.ds.Vector<Dynamic>;
	var sp:Int = 0;
	final globals:Map<String, Dynamic>;
	final builtinIC:haxe.ds.Vector<Dynamic>;

	function new(harness:HarnessContext, chunk:MuseChunk) {
		this.harness = harness;
		this.chunk = chunk;
		this.locals = [for (_ in 0...chunk.localCount()) null];
		this.globals = new Map();
		MuseVmBuiltins.install(this.globals, harness);
		this.builtinIC = new haxe.ds.Vector(chunk.consts.length);
		this.tags = new haxe.ds.Vector(STACK_CAP);
		this.nums = new haxe.ds.Vector(STACK_CAP);
		this.objs = new haxe.ds.Vector(STACK_CAP);
	}

	public static function runBacktest(harness:HarnessContext, prog:MuseProgram, feed:BarFeed):BacktestResult {
		return runChunk(harness, compileProgram(prog), feed);
	}

	/**
	 * Lower a whole program to a `MuseChunk` (or throw `VmUnsupported`). Split out from
	 * `runBacktest` so callers (e.g. `Fitness`) can cache the compiled chunk by structural key and
	 * skip re-parse+compile across evaluations — the "bytecode is the cacheable artifact" payoff
	 * (SPEC §6). Assigns callsite ids and mirrors `MuseInterp.registerStrategyBody` + `execBar`
	 * ordering: body-level `Assign`s are a PER-BAR prelude run BEFORE the onBar handlers, so the
	 * per-bar program is `[prelude…, onBarBody1…, onBarBody2…]`.
	 */
	public static function compileProgram(prog:MuseProgram):MuseChunk {
		prog = CallsiteIds.assign(prog);
		var prelude:Array<Stmt> = [];
		var onBarBodies:Array<Array<Stmt>> = [];
		function collect(body:Array<Stmt>):Void {
			for (s in body) switch (s) {
				case OnBar(b): onBarBodies.push(b);
				case Assign(_, _): prelude.push(s);
				case Block(inner): collect(inner);
				default: throw new VmUnsupported("strategy-body statement " + Std.string(s).substr(0, 24));
			}
		}
		for (d in prog.decls) switch (d) {
			case StrategyDecl(_, body): collect(body);
			default: throw new VmUnsupported("declaration " + Std.string(d).substr(0, 24));
		}
		collect(prog.stmts);
		if (onBarBodies.length == 0) throw new VmUnsupported("no onBar handler");
		var bodies:Array<Array<Stmt>> = [prelude];
		for (b in onBarBodies) bodies.push(b);
		return MuseBytecodeCompiler.compileOnBar(bodies);
	}

	public static function runChunk(harness:HarnessContext, chunk:MuseChunk, feed:BarFeed):BacktestResult {
		var vm = new MuseVm(harness, chunk);
		return harness.runBacktest(function(bar) vm.execBar(bar), feed);
	}

	function execBar(bar:Bar):Void {
		TradeBuiltins.beginBar();
		harness.indCols.beginBar();
		sp = 0;
		runLoop(0, chunk.code.length);
	}

	inline function barField(code:Int):Float {
		var b = harness.currentBar;
		return switch (code) {
			case Op.FIELD_OPEN: b.open;
			case Op.FIELD_HIGH: b.high;
			case Op.FIELD_LOW: b.low;
			case Op.FIELD_CLOSE: b.close;
			case Op.FIELD_VOLUME: b.volume;
			case Op.FIELD_TIME: b.time;
			case Op.FIELD_BAR_INDEX: b.index;
			default: Math.NaN;
		}
	}

	inline function pushNum(f:Float):Void {
		tags[sp] = TAG_NUM;
		nums[sp] = f;
		sp++;
	}

	inline function pushBool(b:Bool):Void {
		tags[sp] = TAG_BOOL;
		objs[sp] = b;
		sp++;
	}

	inline function pushObj(o:Dynamic):Void {
		tags[sp] = TAG_OBJ;
		objs[sp] = o;
		sp++;
	}

	function slotToDyn(i:Int):Dynamic {
		return switch (tags[i]) {
			case TAG_NUM: MuseVmOps.preserveNum(nums[i]);
			case TAG_BOOL: objs[i];
			default: objs[i];
		};
	}

	function pushDyn(v:Dynamic):Void {
		if (v == null) { pushObj(null); return; }
		if (Std.isOfType(v, Bool)) { pushBool((v : Bool)); return; }
		if (Std.isOfType(v, Float) || Std.isOfType(v, Int)) { pushNum(MuseVmOps.toNum(v)); return; }
		pushObj(v);
	}

	function popDyn():Dynamic {
		sp--;
		return slotToDyn(sp);
	}

	inline function popNum():Float {
		sp--;
		return switch (tags[sp]) {
			case TAG_NUM: nums[sp];
			case TAG_BOOL: (objs[sp] : Bool) ? 1.0 : 0.0;
			default: MuseVmOps.toNum(objs[sp]);
		};
	}

	inline function popTruth():Bool {
		sp--;
		return switch (tags[sp]) {
			case TAG_NUM: nums[sp] != 0;
			case TAG_BOOL: (objs[sp] : Bool);
			default: MuseVmOps.truthy(objs[sp]);
		};
	}

	/**
	 * Execute bytecode in `[from, until)`. One shared switch — WITH_OFFSET re-enters for the
	 * lookback body under `harness.withSeriesOffset` (mirrors MuseInterp.evalLookback).
	 */
	function runLoop(from:Int, until:Int):Void {
		var code = chunk.code;
		var consts = chunk.consts;
		var pc = from;
		while (pc < until) {
			var op = code[pc++];
			switch (op) {
				case Op.CONST:
					pushDyn(consts[code[pc++]]);
				case Op.LOAD_LOCAL:
					pushDyn(locals[code[pc++]]);
				case Op.STORE_LOCAL:
					locals[code[pc++]] = popDyn();
				case Op.STORE_LOCAL_S:
					var slot = code[pc++];
					var v = popDyn();
					locals[slot] = v;
					if (Std.isOfType(v, Float) || Std.isOfType(v, Int))
						harness.pushSeries(chunk.localNames[slot], MuseVmOps.toNum(v));
				case Op.BAR_FIELD:
					pushNum(barField(code[pc++]));
				case Op.ADD:
					var bi = sp - 1; var ai = sp - 2;
					if (tags[ai] == TAG_OBJ && MuseVmOps.isStringy(objs[ai])
						|| tags[bi] == TAG_OBJ && MuseVmOps.isStringy(objs[bi])) {
						var b = popDyn(); var a = popDyn();
						pushObj(Std.string(a) + Std.string(b));
					} else {
						var bn = popNum(); var an = popNum();
						pushNum(an + bn);
					}
				case Op.SUB: var bn = popNum(); var an = popNum(); pushNum(an - bn);
				case Op.MUL: var bn = popNum(); var an = popNum(); pushNum(an * bn);
				case Op.DIV: var bn = popNum(); var an = popNum(); pushNum(an / bn);
				case Op.MOD: var bn = popNum(); var an = popNum(); pushNum(an % bn);
				case Op.LT: var bn = popNum(); var an = popNum(); pushBool(an < bn);
				case Op.LE: var bn = popNum(); var an = popNum(); pushBool(an <= bn);
				case Op.GT: var bn = popNum(); var an = popNum(); pushBool(an > bn);
				case Op.GE: var bn = popNum(); var an = popNum(); pushBool(an >= bn);
				case Op.EQ:
					var b = popDyn(); var a = popDyn();
					pushBool(a == b);
				case Op.NE:
					var b = popDyn(); var a = popDyn();
					pushBool(a != b);
				case Op.AND: var bt = popTruth(); var at = popTruth(); pushBool(at && bt);
				case Op.OR: var bt = popTruth(); var at = popTruth(); pushBool(at || bt);
				case Op.NOT: pushBool(!popTruth());
				case Op.NEG: pushNum(-popNum());
				case Op.JZ:
					var addr = code[pc++];
					if (!popTruth()) pc = addr;
				case Op.JMP:
					pc = code[pc++];
				case Op.CMP_JZ:
					var cmpOp = code[pc++];
					var addr = code[pc++];
					var r = false;
					if (cmpOp == Op.EQ || cmpOp == Op.NE) {
						var b = popDyn(); var a = popDyn();
						r = (cmpOp == Op.EQ) ? (a == b) : (a != b);
					} else {
						var bn = popNum(); var an = popNum();
						r = switch (cmpOp) {
							case Op.LT: an < bn;
							case Op.LE: an <= bn;
							case Op.GT: an > bn;
							default: an >= bn;
						};
					}
					if (!r) pc = addr;
				case Op.ORDER:
					var verb = code[pc++];
					var hasArg = code[pc++];
					var arg:Dynamic = hasArg == 1 ? popDyn() : null;
					var verbStr = switch (verb) {
						case Op.VERB_LONG: "long";
						case Op.VERB_SHORT: "short";
						default: "flat";
					};
					var bar = harness.currentBar;
					harness.orders.submit(verbStr, arg, bar.close, bar.index);
				case Op.CALL_BUILTIN:
					var nameIdx = code[pc++];
					var argc = code[pc++];
					var argv:Array<Dynamic> = [for (_ in 0...argc) null];
					var i = argc - 1;
					while (i >= 0) { argv[i] = popDyn(); i--; }
					var fn = builtinIC[nameIdx];
					if (fn == null) { fn = globals.get(consts[nameIdx]); builtinIC[nameIdx] = fn; }
					pushDyn(MuseVmOps.preserveNum(Reflect.callMethod(null, fn, argv)));
				case Op.IND:
					var ind = code[pc++];
					var nameIdx = code[pc++];
					var np = code[pc++];
					var p1 = 0;
					if (np > 0) p1 = code[pc++];
					var sname:String = consts[nameIdx];
					var r:Float = switch (ind) {
						case Op.IND_SMA: TradeBuiltins.sma(harness, sname, p1);
						case Op.IND_EMA: TradeBuiltins.ema(harness, sname, p1);
						case Op.IND_RSI: TradeBuiltins.rsi(harness, sname, p1);
						case Op.IND_ATR: TradeBuiltins.atr(harness, sname, p1);
						case Op.IND_HIGHEST: TradeBuiltins.highest(harness, sname, p1);
						case Op.IND_LOWEST: TradeBuiltins.lowest(harness, sname, p1);
						case Op.IND_STDEV: TradeBuiltins.stdev(harness, sname, p1);
						case Op.IND_WMA: TradeBuiltins.wma(harness, sname, p1);
						case Op.IND_RMA: TradeBuiltins.rma(harness, sname, p1);
						case Op.IND_ROC: TradeBuiltins.roc(harness, sname, p1);
						case Op.IND_MOM: TradeBuiltins.mom(harness, sname, p1);
						case Op.IND_CHANGE:
							np > 0 ? TradeBuiltins.change(harness, sname, p1) : TradeBuiltins.change(harness, sname);
						case Op.IND_PCT_CHANGE:
							np > 0 ? TradeBuiltins.pctChange(harness, sname, p1) : TradeBuiltins.pctChange(harness, sname);
						case Op.IND_SLOPE: TradeBuiltins.slopeN(harness, sname, p1);
						case Op.IND_ZSCORE_ROLL: TradeBuiltins.zscoreN(harness, sname, p1);
						case Op.IND_PERCENT_RANK: TradeBuiltins.percentRank(harness, sname, p1);
						case Op.IND_EWM_VAR: TradeBuiltins.ewmVar(harness, sname, p1);
						case Op.IND_EWM_STDEV: TradeBuiltins.ewmStdev(harness, sname, p1);
						case Op.IND_HL2: TradeBuiltins.hl2(harness);
						case Op.IND_HLC3: TradeBuiltins.hlc3(harness);
						case Op.IND_OHLC4: TradeBuiltins.ohlc4(harness);
						default: TradeBuiltins.vwap(harness);
					};
					pushNum(r);
				case Op.CROSS:
					var csId = code[pc++];
					var fnCode = code[pc++];
					var argc = code[pc++];
					var a0:Array<Dynamic> = [for (_ in 0...argc) null];
					var j = argc - 1;
					while (j >= 0) { a0[j] = popDyn(); j--; }
					var res:Bool = switch (fnCode) {
						case Op.CS_CROSSOVER: TradeBuiltins.crossoverCS(harness, csId, a0[0], a0[1]);
						case Op.CS_CROSSUNDER: TradeBuiltins.crossunderCS(harness, csId, a0[0], a0[1]);
						case Op.CS_RISING: TradeBuiltins.risingCS(harness, csId, a0[0], Std.int(a0[1]), argc > 2 ? Std.int(a0[2]) : 0);
						default: TradeBuiltins.fallingCS(harness, csId, a0[0], Std.int(a0[1]), argc > 2 ? Std.int(a0[2]) : 0);
					};
					pushBool(res);
				case Op.LOOKBACK:
					var sname:String = consts[code[pc++]];
					var n = Std.int(popNum());
					pushNum(harness.seriesLookback(sname, n));
				case Op.WITH_OFFSET:
					var end = code[pc++];
					var n = Std.int(popNum());
					var start = pc;
					var self = this;
					var savedSp = sp;
					harness.withSeriesOffset(n, function() {
						self.sp = savedSp;
						self.runLoop(start, end);
						return null;
					});
					pc = end;
				case Op.GET_FIELD:
					var f:String = consts[code[pc++]];
					var o = popDyn();
					pushDyn(o == null ? null : Reflect.getProperty(o, f));
				case Op.PACK_ARRAY:
					var n = code[pc++];
					var arr:Array<Dynamic> = [for (_ in 0...n) null];
					var i = n - 1;
					while (i >= 0) {
						arr[i] = popDyn();
						i--;
					}
					pushObj(arr);
				case Op.SERIES:
					var scrId = code[pc++];
					var fnCode = code[pc++];
					var argc = code[pc++];
					var s0:Array<Dynamic> = [for (_ in 0...argc) null];
					var k = argc - 1;
					while (k >= 0) { s0[k] = popDyn(); k--; }
					var scrOut = harness.indCols.scratchObj(scrId);
					switch (fnCode) {
						case Op.SCR_MACD:
							TradeBuiltins.macd(harness, s0[0], argc > 1 ? Std.int(s0[1]) : 12,
								argc > 2 ? Std.int(s0[2]) : 26, argc > 3 ? Std.int(s0[3]) : 9, scrOut);
						case Op.SCR_BBANDS:
							TradeBuiltins.bbands(harness, s0[0], Std.int(s0[1]),
								argc > 2 ? (s0[2] : Float) : 2.0, scrOut);
						default:
							TradeBuiltins.stoch(harness, argc > 0 ? Std.int(s0[0]) : 14,
								argc > 1 ? Std.int(s0[1]) : 3, argc > 2 ? Std.int(s0[2]) : 3, scrOut);
					}
					pushObj(scrOut);
				case Op.POP:
					if (sp > 0) sp--;
				case Op.HALT:
					return;
				default:
					throw "MuseVm: bad opcode " + op + " @ " + (pc - 1);
			}
		}
	}
}
