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
 *
 * Front end today: vendored hscript lexer/parser + MuseParser's post-pass.
 * Replacing it with a native tokenizer+parser (owned syntax, first-class
 * macro system, better spans/errors, faster parse) is a scoped epic — see
 * ROADMAP.md ("Native front end") for the staged plan and its compatibility
 * gate (golden-parse corpus: old and new front ends must produce identical
 * MuseAST over every strategy in tests + examples before the flip).
 */
class MuseScript {
	/** Bootstrap: parse source and return raw hscript.Expr */
	public static function run(source:String, ?origin:String):HsExpr {
		return new MuseParser().parseRaw(source, origin);
	}

	public static function parse(source:String, ?origin:String):MuseProgram {
		return new MuseParser().parse(source, origin);
	}

	/** Full front-end pipeline: parse → module/template expand → series lower. */
	public static function lower(source:String, ?origin:String):MuseProgram {
		var prog = parse(source, origin);
		prog = musescript.compile.ModuleExpand.expand(prog);
		prog = musescript.compile.TemplateExpand.expand(prog);
		prog = musescript.compile.SeriesLowering.lower(prog);
		return prog;
	}

	public static function plan(source:String, ?origin:String):ExecutionPlan {
		var prog = parse(source, origin);
		prog = musescript.compile.ModuleExpand.expand(prog);
		prog = musescript.compile.TemplateExpand.expand(prog);
		return new MusePlanner().plan(prog);
	}

	public static function execute(source:String, harness:IHarness, ?origin:String):Dynamic {
		var prog = lower(source, origin);
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

	public static function check(source:String, ?origin:String, ?opts:{?strict:Bool}):Array<String> {
		var prog = lower(source, origin);
		return new MuseChecker({ strict: opts != null && opts.strict == true }).check(prog);
	}

	public static function checkEx(source:String, ?origin:String, ?opts:{?strict:Bool}):Array<musescript.checker.Diagnostic> {
		var prog = lower(source, origin);
		return new MuseChecker({ strict: opts != null && opts.strict == true }).checkEx(prog);
	}

	public static function format(source:String, ?origin:String):String {
		var prog = parse(source, origin);
		return new musescript.compile.MusePrinter().printProgram(prog);
	}

	/** Export typed builtin palette JSON for MuseGene / editors. */
	public static function palette():Dynamic {
		return musescript.types.BuiltinSigs.toPaletteJson();
	}

	/** Export Kestrel-specific feature/model/graph palette JSON. */
	public static function kestrelPalette():Dynamic {
		return musescript.kestrel.KestrelPalette.toJson();
	}

	/** Combined palette for editors that want the full MuseScript + Kestrel surface. */
	public static function fullPalette():Dynamic {
		return {
			builtins: palette(),
			kestrel: kestrelPalette()
		};
	}

	/**
	 * Doc + typed signature for one builtin (ROADMAP.md "Docstring
	 * introspection pipeline"), e.g. `MuseScript.docs("bag_set")` from the
	 * in-app IDE. `null` when the name isn't a known builtin at all.
	 */
	public static function docs(name:String):Dynamic {
		return musescript.docs.BuiltinDocs.get(name);
	}

	/** Every known builtin name, sorted — for an IDE's builtin browser/autocomplete. */
	public static function docsList():Array<String> {
		return musescript.docs.BuiltinDocs.names();
	}

	/** Reference-manual Markdown for the whole builtin surface (CI doc generation). */
	public static function docsMarkdown():String {
		return musescript.docs.BuiltinDocs.toMarkdown();
	}
}
