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
import musescript.checker.MuseChecker;
import musescript.builtins.TradeBuiltins;

/**
 * Phase 1 (enums) language tests. Enum values are the canonical tagged record
 * `{ __tag, args:[...] }` PatternMatcher reads; this suite pins construction,
 * match payload binding, nullary-vs-payload variants, exhaustiveness
 * diagnostics, and — the hard gate — interp == JS-backend parity.
 */
class TestLangEnums extends Test {
	static function interpWith(source:String):MuseInterp {
		var prog = new MuseParser().parse(source);
		var interp = new MuseInterp(new HarnessContext());
		for (d in prog.decls) interp.registerDeclPublic(d);
		return interp;
	}

	static final ENUM_SRC = 'enum Signal {\n  Bullish;\n  Bearish;\n  Doji(strength);\n}\n';

	// ── Construction ──────────────────────────────────────────────────────

	public function testNullaryVariantIsTaggedSingleton() {
		var interp = interpWith(ENUM_SRC + "strategy S { onBar { } }");
		var v:Dynamic = interp.evalExpr(new MuseParser().parseExpr("Bullish"));
		Assert.notNull(v);
		Assert.equals("Bullish", Reflect.field(v, "__tag"));
		var args:Array<Dynamic> = Reflect.field(v, "args");
		Assert.equals(0, args.length);
	}

	public function testPayloadVariantCarriesArgs() {
		var interp = interpWith(ENUM_SRC + "strategy S { onBar { } }");
		var v:Dynamic = interp.evalExpr(new MuseParser().parseExpr("Doji(0.75)"));
		Assert.equals("Doji", Reflect.field(v, "__tag"));
		var args:Array<Dynamic> = Reflect.field(v, "args");
		Assert.equals(1, args.length);
		Assert.floatEquals(0.75, args[0]);
	}

	// ── Match binding (via the new-surface match expression) ──────────────

	public function testMatchNullaryArm() {
		var interp = interpWith(ENUM_SRC + "strategy S { onBar { } }");
		var r:Dynamic = interp.evalExpr(new MuseParser().parseExpr(
			"@match(Bearish) [ Bullish => 1.0, Bearish => -1.0, Doji(v) => v ]"));
		Assert.floatEquals(-1.0, r);
	}

	public function testMatchPayloadArmBindsValue() {
		var interp = interpWith(ENUM_SRC + "strategy S { onBar { } }");
		var r:Dynamic = interp.evalExpr(new MuseParser().parseExpr(
			"@match(Doji(0.42)) [ Bullish => 1.0, Bearish => -1.0, Doji(v) => v ]"));
		Assert.floatEquals(0.42, r);
	}

	public function testMatchWildcardFallthrough() {
		var interp = interpWith(ENUM_SRC + "strategy S { onBar { } }");
		var r:Dynamic = interp.evalExpr(new MuseParser().parseExpr(
			"@match(Bullish) [ Doji(v) => v, _ => 99.0 ]"));
		Assert.floatEquals(99.0, r);
	}

	// ── Exhaustiveness diagnostics (checker) ──────────────────────────────

	public function testExhaustiveMatchNoWarning() {
		var src = ENUM_SRC
			+ "strategy S { onBar {\n"
			+ "  var s = Doji(0.5);\n"
			+ "  when close > open: { s = Bullish }\n"
			+ "  var score = match(s) [ Bullish => 1.0, Bearish => -1.0, Doji(v) => v ];\n"
			+ "  plot(score, \"score\");\n"
			+ "} }";
		var prog = new MuseParser().parse(src);
		var diags = new MuseChecker().check(prog);
		for (d in diags) Assert.isFalse(StringTools.contains(d, "non-exhaustive"));
		for (d in diags) Assert.isFalse(StringTools.contains(d, "missing variants"));
	}

	public function testMissingVariantWarns() {
		var src = ENUM_SRC
			+ "strategy S { onBar {\n"
			+ "  var s = Doji(0.5);\n"
			+ "  when close > open: { s = Bullish }\n"
			+ "  var score = match(s) [ Bullish => 1.0, Doji(v) => v ];\n"
			+ "  plot(score, \"score\");\n"
			+ "} }";
		var prog = new MuseParser().parse(src);
		var diags = new MuseChecker().check(prog);
		var found = false;
		for (d in diags) if (StringTools.contains(d, "missing variants") && StringTools.contains(d, "Bearish")) found = true;
		Assert.isTrue(found);
	}

	// ── print → reparse round-trip (the genome-expansion contract) ────────
	// MuseGene's Expand.hx (musescript/evo/) generates strategies by templating
	// to MuseScript SOURCE TEXT and reparsing — never by direct AST splicing.
	// Any future enum/match/class-aware genome node depends on MusePrinter's
	// output being re-parseable by MuseParser exactly like hand-written source.
	// This pins that contract for enums specifically: construct → match →
	// pattern-with-payload → nullary tag, printed and read back bit-for-bit.

	public function testEnumProgramRoundTripsThroughPrinter() {
		var src = ENUM_SRC
			+ "strategy S { onBar {\n"
			+ "  var s = Doji(0.5);\n"
			+ "  when close > open: { s = Bullish }\n"
			+ "  when close < open: { s = Bearish }\n"
			+ "  var score = match(s) [ Bullish => 1.0, Bearish => -1.0, Doji(v) => v ];\n"
			+ "  plot(score, \"score\");\n"
			+ "} }";
		var prog1 = new MuseParser().parse(src);
		var printed = new MusePrinter().printProgram(prog1);

		// Must actually re-parse — this is the assertion that matters.
		var prog2 = new MuseParser().parse(printed);
		Assert.equals(2, prog2.decls.length); // EnumDecl + StrategyDecl

		// And the reparsed program must behave identically to the original —
		// same interp result over the same tape, not just "didn't throw".
		var feed = BarFeed.synthetic(200, 5);
		var r1 = new MuseInterp(new HarnessContext()).runBacktest(prog1, feed);
		var r2 = new MuseInterp(new HarnessContext()).runBacktest(prog2, feed);
		Assert.equals(r1.trades, r2.trades);
		Assert.floatEquals(r1.finalEquity, r2.finalEquity);
	}

	// ── interp == JS-backend parity (the hard gate) ───────────────────────

	public function testEnumStrategyInterpJsParity() {
		var source = ENUM_SRC
			+ "strategy EnumDemo { onBar {\n"
			+ "  var s = Doji(0.5);\n"
			+ "  when close > open: { s = Bullish }\n"
			+ "  when close < open: { s = Bearish }\n"
			+ "  var score = match(s) [ Bullish => 1.0, Bearish => -1.0, Doji(v) => v ];\n"
			+ "  plot(score, \"score\");\n"
			+ "  when score > 0.0: { long() }\n"
			+ "  when score < 0.0: { flat() }\n"
			+ "} }";
		var feed = BarFeed.synthetic(300, 17);

		var interpHarness = new HarnessContext();
		var interpProg = new MuseParser().parse(source);
		var interpResult = new MuseInterp(interpHarness).runBacktest(interpProg, feed);
		Assert.isTrue(interpResult.trades >= 0);

		#if js
		var jsHarness = new HarnessContext();
		var jsProg = new MuseParser().parse(source);
		Reflect.setField(jsHarness, "feed", feed);
		var ex = MuseCompiler.compileEx(jsProg, { target: "js", strict: true });
		var jsResult = ex.fn(jsHarness);
		Assert.equals(interpResult.trades, jsResult.trades);
		Assert.floatEquals(interpResult.finalEquity, jsResult.finalEquity);
		#end
	}

	// ── WASM hybrid: a bare enum variant construction must ESCAPE, never
	// silently mis-emit (regression — found while scoping P4, see
	// StrategyWasmEmitter's `enumVariantNames` doc comment). `var s = Bullish`
	// previously fell through EIdent's "unknown identifier -> get_param"
	// fallback and compiled to a garbage host-param read instead of throwing
	// EmitUnsupported, silently diverging from interp (91 trades vs 0 on the
	// exact source below, before the fix).

	public function testEnumVariantConstructionEscapesInsteadOfMisemitting() {
		var source = ENUM_SRC
			+ "strategy EnumProbe { onBar {\n"
			+ "  var s = Bullish;\n"
			+ "  when close > open: { s = Bearish }\n"
			+ "  var score = match(s) [ Bullish => 1.0, Bearish => -1.0, Doji(v) => v ];\n"
			+ "  plot(score, \"score\");\n"
			+ "  when score > 0.0: { long() }\n"
			+ "  when score < 0.0: { flat() }\n"
			+ "} }";
		var feed = BarFeed.synthetic(200, 5);

		TradeBuiltins.resetCrossState();
		var interpResult = new MuseInterp(new HarnessContext())
			.runBacktest(new MuseParser().parse(source), feed);

		#if (js || python)
		if (StrategyWasmBackend.hostReady()) {
			TradeBuiltins.resetCrossState();
			var hybridHarness = new HarnessContext();
			Reflect.setField(hybridHarness, "feed", feed);
			var hybridResult = StrategyWasmBackend.compile(new MuseParser().parse(source))(hybridHarness);
			Assert.equals(interpResult.trades, hybridResult.trades);
			Assert.floatEquals(interpResult.finalEquity, hybridResult.finalEquity);
		}
		#end
	}
}
