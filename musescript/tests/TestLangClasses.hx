package musescript.tests;

import utest.Test;
import utest.Assert;
import musescript.parse.MuseParser;
import musescript.interp.MuseInterp;
import musescript.harness.HarnessContext;
import musescript.harness.BarFeed;
import musescript.compile.MuseCompiler;
import musescript.compile.MusePrinter;
import musescript.compile.StrategyWasmBackend;
import musescript.ast.Expr;
import musescript.ast.Const;

/**
 * Phase 2 (classes) language tests. Instances are the canonical tagged record
 * `{ __class, field... }`; methods dispatch off `__class` via the class's own
 * registry (never copied per-instance). `this` is optional inside methods —
 * bare `field` resolves/assigns like `this.field` (Haxe-flavored). Pins
 * construction, ctor `this` binding, optional-this read/write, explicit
 * `this.field`, print-reparse round trip (genome-expansion contract, same as
 * TestLangEnums), interp==JS parity (the hard gate), and a WASM escape-region
 * sanity check (P2 has no class-WASM lowering yet — F1 must still compile the
 * surrounding program via host_eval, not crash or bail the whole module).
 */
class TestLangClasses extends Test {
	static function interpWith(source:String):MuseInterp {
		var prog = new MuseParser().parse(source);
		var interp = new MuseInterp(new HarnessContext());
		for (d in prog.decls) interp.registerDeclPublic(d);
		return interp;
	}

	static final AVERAGER_SRC = 'class Averager {\n'
		+ '  sum = 0.0;\n'
		+ '  count = 0.0;\n'
		+ '  new(seed) {\n'
		+ '    sum = seed\n'
		+ '    count = 1.0\n'
		+ '  }\n'
		+ '  function add(x) {\n'
		+ '    sum = sum + x\n'
		+ '    count = count + 1.0\n'
		+ '  }\n'
		+ '  function avg() {\n'
		+ '    return sum / count\n'
		+ '  }\n'
		+ '  function avgExplicit() {\n'
		+ '    return this.sum / this.count\n'
		+ '  }\n'
		+ '}\n';

	// ── Construction ──────────────────────────────────────────────────────

	// `new`/`this` are new-surface-only syntax (StrategyParser), not part of the
	// legacy hscript grammar `MuseParser().parseExpr()` parses standalone
	// expressions with — so these tests build the `ENew` node directly rather
	// than parsing a string through the wrong parser.
	static function newAverager(seed:Float):Expr {
		return ENew("Averager", [EConst(CFloat(seed))]);
	}

	public function testFieldDefaultsInitializeInstance() {
		var interp = interpWith(AVERAGER_SRC + "strategy S { onBar { } }");
		var v:Dynamic = interp.evalExpr(newAverager(0.0));
		Assert.notNull(v);
		Assert.equals("Averager", Reflect.field(v, "__class"));
	}

	public function testCtorRunsWithThisBound() {
		var interp = interpWith(AVERAGER_SRC + "strategy S { onBar { } }");
		var v:Dynamic = interp.evalExpr(newAverager(5.0));
		Assert.floatEquals(5.0, Reflect.field(v, "sum"));
		Assert.floatEquals(1.0, Reflect.field(v, "count"));
	}

	// ── Optional `this` (read + write) and explicit `this.field` ──────────

	public function testMethodCallMutatesInstanceViaOptionalThis() {
		var interp = interpWith(AVERAGER_SRC + "strategy S { onBar { } }");
		var v:Dynamic = interp.evalExpr(newAverager(0.0));
		interp.callInstanceMethodPublic(v, "add", [4.0]);
		interp.callInstanceMethodPublic(v, "add", [6.0]);
		Assert.floatEquals(10.0, Reflect.field(v, "sum"));
		Assert.floatEquals(3.0, Reflect.field(v, "count"));
	}

	public function testMethodReturnValueViaOptionalThis() {
		var interp = interpWith(AVERAGER_SRC + "strategy S { onBar { } }");
		var v:Dynamic = interp.evalExpr(newAverager(2.0));
		interp.callInstanceMethodPublic(v, "add", [8.0]);
		var avg = interp.callInstanceMethodPublic(v, "avg", []);
		Assert.floatEquals(5.0, avg); // (2 + 8) / 2
	}

	public function testExplicitThisMatchesOptionalThis() {
		var interp = interpWith(AVERAGER_SRC + "strategy S { onBar { } }");
		var v:Dynamic = interp.evalExpr(newAverager(2.0));
		interp.callInstanceMethodPublic(v, "add", [8.0]);
		var a = interp.callInstanceMethodPublic(v, "avg", []);
		var b = interp.callInstanceMethodPublic(v, "avgExplicit", []);
		Assert.floatEquals(a, b);
	}

	// ── print → reparse round-trip (the genome-expansion contract) ────────
	// Same discipline as TestLangEnums.testEnumProgramRoundTripsThroughPrinter
	// — MuseGene's Expand.hx generates SOURCE TEXT and reparses it, never
	// splices AST directly, so MusePrinter output for classes must be readable
	// by the same parser bit-for-bit.

	public function testClassProgramRoundTripsThroughPrinter() {
		var src = AVERAGER_SRC
			+ "strategy S { onBar {\n"
			+ "  var a = new Averager(close)\n"
			+ "  var v = a.avg()\n"
			+ "  plot(v, \"avg\")\n"
			+ "} }";
		var prog1 = new MuseParser().parse(src);
		var printed = new MusePrinter().printProgram(prog1);

		var prog2 = new MuseParser().parse(printed);
		Assert.equals(2, prog2.decls.length); // ClassDecl + StrategyDecl

		var feed = BarFeed.synthetic(200, 5);
		var r1 = new MuseInterp(new HarnessContext()).runBacktest(prog1, feed);
		var r2 = new MuseInterp(new HarnessContext()).runBacktest(prog2, feed);
		Assert.equals(r1.trades, r2.trades);
		Assert.floatEquals(r1.finalEquity, r2.finalEquity);
	}

	// ── interp == JS-backend parity (the hard gate) ───────────────────────

	static final STRATEGY_SRC = AVERAGER_SRC
		+ "strategy ClassDemo { onBar {\n"
		+ "  var a = new Averager(close)\n"
		+ "  a.add(open)\n"
		+ "  var v = a.avg()\n"
		+ "  plot(v, \"avg\")\n"
		+ "  when v > close: { long() }\n"
		+ "  when v < close: { flat() }\n"
		+ "} }";

	public function testClassStrategyInterpJsParity() {
		var feed = BarFeed.synthetic(300, 17);

		var interpProg = new MuseParser().parse(STRATEGY_SRC);
		var interpResult = new MuseInterp(new HarnessContext()).runBacktest(interpProg, feed);
		Assert.isTrue(interpResult.trades >= 0);

		#if js
		var jsHarness = new HarnessContext();
		var jsProg = new MuseParser().parse(STRATEGY_SRC);
		Reflect.setField(jsHarness, "feed", feed);
		var ex = MuseCompiler.compileEx(jsProg, { target: "js", strict: true });
		var jsResult = ex.fn(jsHarness);
		Assert.equals(interpResult.trades, jsResult.trades);
		Assert.floatEquals(interpResult.finalEquity, jsResult.finalEquity);
		#end
	}

	// ── WASM: no class-WASM lowering yet (P4) — must still compile via
	// escape regions, not crash or bail the whole module, and stay parity-
	// correct end to end through the interp thunk.

	public function testClassStrategyCompilesViaWasmEscapeRegions() {
		var prog = new MuseParser().parse(STRATEGY_SRC);
		var wat = StrategyWasmBackend.emitWat(prog);
		Assert.notNull(wat);
		Assert.isTrue(StringTools.contains(wat, "host_eval"));

		#if (js || python)
		if (StrategyWasmBackend.hostReady()) {
			var feed = BarFeed.synthetic(150, 9);
			var interpResult = new MuseInterp(new HarnessContext())
				.runBacktest(new MuseParser().parse(STRATEGY_SRC), feed);
			var hybridHarness = new HarnessContext();
			Reflect.setField(hybridHarness, "feed", feed);
			var hybridResult = StrategyWasmBackend.compile(new MuseParser().parse(STRATEGY_SRC))(hybridHarness);
			Assert.equals(interpResult.trades, hybridResult.trades);
			Assert.floatEquals(interpResult.finalEquity, hybridResult.finalEquity);
		}
		#end
	}
}
