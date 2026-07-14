package musescript;

import hscript.Expr as HsExpr;
import musescript.parse.MuseParser;
import musescript.ast.MuseProgram;
import musescript.interp.MuseInterp;
import musescript.harness.IHarness;
import musescript.plan.MusePlanner;
import musescript.plan.ExecutionPlan;
import musescript.compile.MuseCompiler;
import musescript.checker.MuseChecker;
import musescript.BarStrategyFn;

/**
 * Public entry API for MuseScript.
 */
class MuseScript {
	/** Bootstrap: parse source and return raw hscript.Expr */
	public static function run(source:String, ?origin:String):HsExpr {
		return new MuseParser().parseRaw(source, origin);
	}

	public static function parse(source:String, ?origin:String):MuseProgram {
		return new MuseParser().parse(source, origin);
	}

	public static function plan(source:String, ?origin:String):ExecutionPlan {
		var prog = parse(source, origin);
		return new MusePlanner().plan(prog);
	}

	public static function execute(source:String, harness:IHarness, ?origin:String):Dynamic {
		var prog = parse(source, origin);
		var interp = new MuseInterp(harness);
		return interp.executeProgram(prog);
	}

	public static function compile(source:String, ?opts:{?target:String, ?strict:Bool}):BarStrategyFn {
		var prog = parse(source);
		return MuseCompiler.compile(prog, opts);
	}

	public static function compileEx(source:String, ?opts:{?target:String, ?strict:Bool}):musescript.compile.CompileEx {
		var prog = parse(source);
		return MuseCompiler.compileEx(prog, opts);
	}

	/** Compile a named math-only function (`js` | `python` | `numba` | `wasm`). */
	public static function compileMath(source:String, name:String, ?opts:{?target:String}):Null<Dynamic> {
		var prog = parse(source);
		return musescript.compile.MathCompiler.compile(prog, name, opts);
	}

	public static function check(source:String, ?origin:String):Array<String> {
		var prog = parse(source, origin);
		return new MuseChecker().check(prog);
	}
}
