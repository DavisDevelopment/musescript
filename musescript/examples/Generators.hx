package musescript.examples;

import musescript.ast.Expr;
import musescript.ast.Const;
import musescript.ast.FnKind;
import musescript.harness.HarnessContext;
import musescript.interp.MuseInterp;
import musescript.runtime.FnClosure;
import musescript.runtime.Generator;
import musescript.runtime.IterDriver;
import musescript.runtime.MuseIters;
import musescript.runtime.CallFrame;
import musescript.compile.TailCallPass;
import musescript.ast.MuseProgram;
import musescript.ast.Decl;

/**
 * Example 05 — generators (yield) + tail-call rewrite demo.
 *
 * Interpreter: first next() eagerly runs the body (collect mode); yields queue up.
 * Compiler: GeneratorLower rewrites simple generators to {next} state machines.
 */
class Generators {
	static function main() {
		Sys.println("=== MuseScript 05-generators ===");

		var harness = new HarnessContext();
		var interp = new MuseInterp(harness);

		// function* range(from, to) { var i = from; while (i < to) { yield i; i = i + 1; } }
		// Built as MuseAST directly (hscript has no function* keyword).
		var rangeBody = EBlock([
			EVar("i", EIdent("from")),
			EWhile(
				EBinop("<", EIdent("i"), EIdent("to")),
				EBlock([
					EYield(EIdent("i")),
					EBinop("=", EIdent("i"), EBinop("+", EIdent("i"), EConst(CInt(1))))
				])
			)
		]);
		var rangeFn = new FnClosure(["from", "to"], rangeBody, null, "range", Generator);
		interp.globals.set("range", rangeFn);

		var gen:Dynamic = interp.callValue(rangeFn, [3, 7]);
		Assert.isGenerator(gen);
		var vals = MuseIters.toArray(cast gen);
		Sys.println("range(3,7) => " + vals);

		// Tail-call fact via TailCallPass
		var factBody = EIf(
			EBinop("<=", EIdent("n"), EConst(CInt(1))),
			EIdent("acc"),
			EReturn(ECall(EIdent("fact"), [
				EBinop("-", EIdent("n"), EConst(CInt(1))),
				EBinop("*", EIdent("acc"), EIdent("n"))
			]))
		);
		var prog:MuseProgram = {
			decls: [FnDecl("fact", ["n", "acc"], factBody, Normal)],
			stmts: []
		};
		prog = TailCallPass.transform(prog);
		var rewritten = switch (prog.decls[0]) {
			case FnDecl(_, _, body, _): body;
			default: factBody;
		};
		Sys.println("TailCallPass rewrote fact: " + (!Type.enumEq(rewritten, factBody)));
		var fact = new FnClosure(["n", "acc"], rewritten, null, "fact", Normal);
		interp.globals.set("fact", fact);
		var r = interp.callClosure(fact, [10, 1]);
		Sys.println("fact(10) => " + r + " (expected 3628800)");
	}
}

class Assert {
	public static function isGenerator(v:Dynamic):Void {
		if (!Std.isOfType(v, Generator))
			throw "expected Generator, got " + Type.typeof(v);
	}
}
