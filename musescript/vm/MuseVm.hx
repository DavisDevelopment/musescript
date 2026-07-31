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
 * backtest driven by this VM is byte-identical to the interp's for the P0
 * subset — the parity gate (`TestBytecodeVmParity`, §4) enforces it.
 *
 * P0 is the correctness/structure milestone: the operand stack is `Dynamic` and
 * values route through `MuseVmOps` for exact parity. The unboxed-double fast
 * path, superinstructions and inline caches (the actual 3–10× — §7/P1) come
 * next and don't change observable behaviour.
 */
class MuseVm {
	final harness:HarnessContext;
	final chunk:MuseChunk;
	final locals:Array<Dynamic>;
	final stack:Array<Dynamic> = [];

	function new(harness:HarnessContext, chunk:MuseChunk) {
		this.harness = harness;
		this.chunk = chunk;
		this.locals = [for (_ in 0...chunk.localCount()) null];
	}

	/**
	 * Compile `prog`'s `onBar` handlers to bytecode and run a full backtest on
	 * `feed`, driving each bar through the VM instead of the interp's stmt-walk.
	 * Throws `VmUnsupported` (caught by the caller for interp fallback) if the
	 * program uses anything outside the P0 subset — including any non-`onBar`
	 * top-level statement or handler, which the subset does not yet cover.
	 */
	public static function runBacktest(harness:HarnessContext, prog:MuseProgram, feed:BarFeed):BacktestResult {
		// Same first move as MuseInterp.setupRun: assign stateful-callsite ids so
		// the lowered AST matches the interp's exactly (idempotent).
		prog = CallsiteIds.assign(prog);
		// Mirror MuseInterp.registerStrategyBody + execBar ordering: body-level
		// Assigns are a PER-BAR prelude that runs BEFORE the onBar handlers, so the
		// compiled per-bar program is [prelude…, onBarBody1…, onBarBody2…].
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
		collect(prog.stmts); // bare top-level onBar / prelude assigns, if any
		if (onBarBodies.length == 0) throw new VmUnsupported("no onBar handler");
		var bodies:Array<Array<Stmt>> = [prelude];
		for (b in onBarBodies) bodies.push(b);
		var chunk = MuseBytecodeCompiler.compileOnBar(bodies);
		var vm = new MuseVm(harness, chunk);
		return harness.runBacktest(function(bar) vm.execBar(bar), feed);
	}

	/** Per-bar execution — mirror of `MuseInterp.execBar`'s bindBar prelude for
	 * the subset (no prelude/onPosition), then run the compiled chunk. */
	function execBar(bar:Bar):Void {
		TradeBuiltins.beginBar();
		harness.indCols.beginBar();
		run();
	}

	inline function barField(code:Int):Dynamic {
		var b = harness.currentBar;
		return switch (code) {
			case Op.FIELD_OPEN: b.open;
			case Op.FIELD_HIGH: b.high;
			case Op.FIELD_LOW: b.low;
			case Op.FIELD_CLOSE: b.close;
			case Op.FIELD_VOLUME: b.volume;
			case Op.FIELD_TIME: b.time;
			case Op.FIELD_BAR_INDEX: b.index;
			default: null;
		}
	}

	function run():Void {
		var code = chunk.code;
		var consts = chunk.consts;
		var sp = stack;
		sp.splice(0, sp.length); // fresh operand stack per bar (locals persist)
		var pc = 0;
		while (pc < code.length) {
			var op = code[pc++];
			switch (op) {
				case Op.CONST: sp.push(consts[code[pc++]]);
				case Op.LOAD_LOCAL: sp.push(locals[code[pc++]]);
				case Op.STORE_LOCAL: locals[code[pc++]] = sp.pop();
				case Op.STORE_LOCAL_S:
					var slot = code[pc++];
					var v = sp.pop();
					locals[slot] = v;
					// Parity with MuseInterp.Assign: numeric assigns push a series sample.
					if (Std.isOfType(v, Float) || Std.isOfType(v, Int))
						harness.pushSeries(chunk.localNames[slot], MuseVmOps.toNum(v));
				case Op.BAR_FIELD: sp.push(barField(code[pc++]));
				case Op.ADD:
					var b = sp.pop(); var a = sp.pop();
					if (MuseVmOps.isStringy(a) || MuseVmOps.isStringy(b))
						sp.push(Std.string(a) + Std.string(b));
					else sp.push(MuseVmOps.preserveNum(MuseVmOps.toNum(a) + MuseVmOps.toNum(b)));
				case Op.SUB: var b = sp.pop(); var a = sp.pop(); sp.push(MuseVmOps.preserveNum(MuseVmOps.toNum(a) - MuseVmOps.toNum(b)));
				case Op.MUL: var b = sp.pop(); var a = sp.pop(); sp.push(MuseVmOps.preserveNum(MuseVmOps.toNum(a) * MuseVmOps.toNum(b)));
				case Op.DIV: var b = sp.pop(); var a = sp.pop(); sp.push(MuseVmOps.preserveNum(MuseVmOps.toNum(a) / MuseVmOps.toNum(b)));
				case Op.MOD: var b = sp.pop(); var a = sp.pop(); sp.push(MuseVmOps.preserveNum(MuseVmOps.toNum(a) % MuseVmOps.toNum(b)));
				case Op.LT: var b = sp.pop(); var a = sp.pop(); sp.push(MuseVmOps.toNum(a) < MuseVmOps.toNum(b));
				case Op.LE: var b = sp.pop(); var a = sp.pop(); sp.push(MuseVmOps.toNum(a) <= MuseVmOps.toNum(b));
				case Op.GT: var b = sp.pop(); var a = sp.pop(); sp.push(MuseVmOps.toNum(a) > MuseVmOps.toNum(b));
				case Op.GE: var b = sp.pop(); var a = sp.pop(); sp.push(MuseVmOps.toNum(a) >= MuseVmOps.toNum(b));
				case Op.EQ: var b = sp.pop(); var a = sp.pop(); sp.push(a == b);
				case Op.NE: var b = sp.pop(); var a = sp.pop(); sp.push(a != b);
				case Op.AND: var b = sp.pop(); var a = sp.pop(); sp.push(MuseVmOps.truthy(a) && MuseVmOps.truthy(b));
				case Op.OR: var b = sp.pop(); var a = sp.pop(); sp.push(MuseVmOps.truthy(a) || MuseVmOps.truthy(b));
				case Op.NOT: sp.push(!MuseVmOps.truthy(sp.pop()));
				case Op.NEG: sp.push(MuseVmOps.preserveNum(-MuseVmOps.toNum(sp.pop())));
				case Op.JZ: var addr = code[pc++]; if (!MuseVmOps.truthy(sp.pop())) pc = addr;
				case Op.JMP: pc = code[pc++];
				case Op.ORDER:
					var verb = code[pc++];
					var hasArg = code[pc++];
					var arg:Dynamic = hasArg == 1 ? sp.pop() : null;
					var verbStr = switch (verb) {
						case Op.VERB_LONG: "long";
						case Op.VERB_SHORT: "short";
						default: "flat";
					};
					var bar = harness.currentBar;
					harness.orders.submit(verbStr, arg, bar.close, bar.index);
				case Op.POP: sp.pop();
				case Op.HALT: return;
				default: throw "MuseVm: bad opcode " + op + " @ " + (pc - 1);
			}
		}
	}
}
