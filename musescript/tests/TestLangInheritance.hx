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
import musescript.ast.Expr;
import musescript.ast.Const;

/**
 * Phase 3 (inheritance) language tests. `extends`/override/`super` on top of
 * P2's class substrate — no new runtime value shape (an instance is still
 * `{__class, fields...}`; `__class` stays the MOST-DERIVED class, subclass
 * fields/methods just come from walking `ClassDecl.parent`). Pins: parent-
 * first field init order, ctor chaining (both implicit — subclass omits its
 * own ctor — and explicit `super(...)`), method override (virtual dispatch:
 * calling through a base-typed reference still runs the subclass's version),
 * `super.method()` bypassing an override, print-reparse round trip, and
 * interp==JS parity (methods stay interp-only per P2, so this is correct by
 * construction, but still pinned as a regression gate).
 */
class TestLangInheritance extends Test {
	static function interpWith(source:String):MuseInterp {
		var prog = new MuseParser().parse(source);
		var interp = new MuseInterp(new HarnessContext());
		for (d in prog.decls) interp.registerDeclPublic(d);
		return interp;
	}

	static function newInst(className:String, args:Array<Expr>):Expr {
		return ENew(className, args);
	}

	static final SRC = 'class Animal {\n'
		+ '  sound = "...";\n'
		+ '  new(s) {\n'
		+ '    sound = s\n'
		+ '  }\n'
		+ '  function speak() {\n'
		+ '    return sound\n'
		+ '  }\n'
		+ '  function describe() {\n'
		+ '    return "an animal that says " + speak()\n'
		+ '  }\n'
		+ '}\n'
		+ 'class Dog extends Animal {\n'
		+ '  breed = "unknown";\n'
		+ '  new(b) {\n'
		+ '    super("Woof")\n'
		+ '    breed = b\n'
		+ '  }\n'
		+ '  function speak() {\n'
		+ '    return super.speak() + "!"\n'
		+ '  }\n'
		+ '}\n'
		+ 'class Puppy extends Dog {\n'
		+ '}\n';

	// ── Field init order (parent-first) + ctor chaining ────────────────────

	public function testParentFieldsPresentBeforeChildCtorRuns() {
		var interp = interpWith(SRC + "strategy S { onBar { } }");
		var v:Dynamic = interp.evalExpr(newInst("Dog", [EConst(CString("Beagle"))]));
		Assert.equals("Dog", Reflect.field(v, "__class"));
		// super("Woof") ran inside Dog's ctor, setting the PARENT's field.
		Assert.equals("Woof", Reflect.field(v, "sound"));
		Assert.equals("Beagle", Reflect.field(v, "breed"));
	}

	public function testImplicitCtorChainWhenSubclassOmitsOwnCtor() {
		var interp = interpWith(SRC + "strategy S { onBar { } }");
		// Puppy declares no ctor at all — should implicitly chain to Dog's,
		// which itself chains to Animal's via explicit super(...).
		var v:Dynamic = interp.evalExpr(newInst("Puppy", [EConst(CString("ignored"))]));
		Assert.equals("Puppy", Reflect.field(v, "__class"));
		Assert.equals("Woof", Reflect.field(v, "sound"));
	}

	// ── Override (virtual dispatch) + super.method() ──────────────────────

	public function testOverrideIsVirtualThroughInheritedMethod() {
		var interp = interpWith(SRC + "strategy S { onBar { } }");
		var v:Dynamic = interp.evalExpr(newInst("Dog", [EConst(CString("Woof"))]));
		// Animal.describe() calls speak() — must resolve to Dog's OVERRIDE,
		// not Animal's own, even though describe() is only defined on Animal.
		var r = interp.callInstanceMethodPublic(v, "describe", []);
		Assert.equals("an animal that says Woof!", r);
	}

	public function testSuperMethodCallReachesParentVersion() {
		var interp = interpWith(SRC + "strategy S { onBar { } }");
		var v:Dynamic = interp.evalExpr(newInst("Dog", [EConst(CString("Woof"))]));
		// Dog.speak() = super.speak() + "!" — super.speak() must be Animal's
		// plain field return, not Dog's own (which would infinite-loop).
		var r = interp.callInstanceMethodPublic(v, "speak", []);
		Assert.equals("Woof!", r);
	}

	public function testGrandchildInheritsOverrideAcrossTwoLevels() {
		var interp = interpWith(SRC + "strategy S { onBar { } }");
		var v:Dynamic = interp.evalExpr(newInst("Puppy", [EConst(CString("x"))]));
		// Puppy has no speak() of its own — must resolve to Dog's override
		// (via the parent chain), which itself correctly reaches Animal via super.
		var r = interp.callInstanceMethodPublic(v, "speak", []);
		Assert.equals("Woof!", r);
	}

	// ── Checker: parent-exists diagnostic ──────────────────────────────────

	public function testUnknownParentWarns() {
		var prog = new MuseParser().parse('class Cub extends NoSuchClass {\n}\nstrategy S { onBar { } }');
		var diags = new MuseChecker().check(prog);
		var found = false;
		for (d in diags) if (StringTools.contains(d, "unknown class") && StringTools.contains(d, "NoSuchClass")) found = true;
		Assert.isTrue(found);
	}

	public function testKnownParentDoesNotWarn() {
		var prog = new MuseParser().parse(SRC + "strategy S { onBar { } }");
		var diags = new MuseChecker().check(prog);
		for (d in diags) Assert.isFalse(StringTools.contains(d, "extends unknown class"));
	}

	// ── print → reparse round-trip (genome-expansion contract) ─────────────

	public function testInheritanceProgramRoundTripsThroughPrinter() {
		var src = SRC
			+ "strategy S { onBar {\n"
			+ "  var d = new Dog(\"Woof\")\n"
			+ "  var v = d.speak()\n"
			+ "  plot(str_len(v), \"len\")\n"
			+ "} }";
		var prog1 = new MuseParser().parse(src);
		var printed = new MusePrinter().printProgram(prog1);

		var prog2 = new MuseParser().parse(printed);
		Assert.equals(4, prog2.decls.length); // Animal + Dog + Puppy + StrategyDecl

		var feed = BarFeed.synthetic(200, 5);
		var r1 = new MuseInterp(new HarnessContext()).runBacktest(prog1, feed);
		var r2 = new MuseInterp(new HarnessContext()).runBacktest(prog2, feed);
		Assert.equals(r1.trades, r2.trades);
		Assert.floatEquals(r1.finalEquity, r2.finalEquity);
	}

	// ── interp == JS-backend parity (the hard gate) ─────────────────────────

	static final STRATEGY_SRC = SRC
		+ "strategy InheritDemo { onBar {\n"
		+ "  var d = new Dog(\"Woof\")\n"
		+ "  var v = str_len(d.speak())\n"
		+ "  plot(v, \"len\")\n"
		+ "  when v > 4.0: { long() }\n"
		+ "  when v <= 4.0: { flat() }\n"
		+ "} }";

	public function testInheritanceStrategyInterpJsParity() {
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

	// ── WASM: no class-WASM lowering yet (P4) — escape regions must still
	// compile the program and stay parity-correct through the interp thunk.

	public function testInheritanceStrategyCompilesViaWasmEscapeRegions() {
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
