package musescript.compile;

import musescript.ast.MuseProgram;
import musescript.BarStrategyFn;
import musescript.harness.HarnessContext;
import musescript.harness.BarFeed;
import musescript.interp.MuseInterp;

/**
 * Compile MuseAST → callable strategy.
 *
 * Strategy compile targets (MuseCompiler.compile):
 * - "js" (default) — JsEmitter hot path + eval on JS; MuseInterp elsewhere
 * - "haxe"         — HaxeEmitter source; MuseInterp execution (AOT pending)
 * - "wasm"         — StrategyWasmBackend on-bar WAT (subset) on JS/Python(wasmtime); MuseInterp fallback
 * - "native"       — not implemented; MuseInterp fallback with trace
 *
 * Math-only wasm lives in MathCompiler / WasmBackend (unrelated to strategy targets).
 */
class MuseCompiler {
	/** Backend used by the last compile() / compileEx() call. */
	public static var lastBackend:String = "interp";

	public static function compile(prog:MuseProgram, ?opts:{?target:String, ?strict:Bool}):BarStrategyFn {
		return compileEx(prog, opts).fn;
	}

	public static function compileEx(prog:MuseProgram, ?opts:{?target:String, ?strict:Bool}):CompileEx {
		var target = opts != null && opts.target != null ? opts.target : "js";
		var strict = opts != null && opts.strict == true;
		// TemplateExpand before ModuleExpand (2026-07-19 hardening pass —
		// was the other way round): TemplateExpand already knows how to
		// expand template calls found INSIDE a ModuleDecl's body (its own
		// decl switch has a ModuleDecl case), and correctly substitutes
		// template params referenced inside a `use Module(arg = param)`
		// call's arguments (TemplateExpand.substituteStmt's Use case).
		// ModuleExpand does NOT have the reverse capability — it never
		// scans TemplateDecl/StmtTemplateDecl bodies at all, so a `use`
		// call written INSIDE a template would never be seen by
		// ModuleExpand if it ran first (by the time TemplateExpand later
		// inlines that template at its call site, ModuleExpand has
		// already finished and the ModuleDecl info it needs is gone —
		// ModuleExpand strips ModuleDecl from `decls` as it collects them,
		// so a second ModuleExpand pass afterward wouldn't help either).
		// First of all: a class rooted at `muse.Strat`/`muse.Indicator` is a declaration written
		// in class syntax, so flatten it into the declaration it means before any pass that
		// reasons about declarations. Everything downstream then sees an ordinary
		// StrategyDecl/IndicatorDecl and needs no knowledge of classes.
		prog = ClassStrategyLower.expand(prog);
		prog = TemplateExpand.expand(prog);
		prog = ModuleExpand.expand(prog);
		prog = SeriesLowering.lower(prog);
		prog = GeneratorLower.lower(prog);
		prog = TailCallPass.transform(prog);
		// Inline simple (single-expression) static class methods at their call sites — see
		// StaticInlinePass's doc comment. After TailCallPass (different target), before
		// CallsiteIds (inlining creates new call sites; stateful-builtin identity is assigned
		// per POST-inline syntactic site, matching CallsiteIds' own "per helper, not per dynamic
		// call" semantics for ordinary function calls).
		prog = StaticInlinePass.transform(prog);
		// Fold constant sub-expressions and dead branches — see ConstFold's doc comment.
		// After StaticInlinePass specifically because inlining substitutes literal
		// default-argument values into call bodies, which routinely turns a `when`/
		// comparison inside that body into something fold-eligible only AFTER splicing.
		prog = ConstFold.transform(prog);
		// Deduplicate a repeated PURE value within the same flat statement list (a duplicate
		// `when` condition, or an `Assign` recomputing the same thing another local already
		// holds) — see CommonSubexprElim's doc comment for exactly how narrow "pure" is here
		// (any call is conservatively impure, so stateful builtins are never touched).
		prog = CommonSubexprElim.transform(prog);
		// Static identities for stateful callsites (crossover/rising/...) so
		// conditional evaluation can't alias state and backends agree. Runs
		// after template expansion so each instantiation gets its own id.
		prog = CallsiteIds.assign(prog);
		var result = switch (target) {
			case "haxe":
				var fn = HaxeBackend.compile(prog);
				var emitted = HaxeBackend.emitSource(prog) != null;
				{ fn: fn, backend: emitted ? "haxe" : "interp", emitted: emitted };
			case "wasm":
				var wat = StrategyWasmBackend.emitWat(prog);
				var fn = StrategyWasmBackend.compile(prog);
				{ fn: fn, backend: wat != null ? "wasm" : "interp", emitted: wat != null };
			case "native":
				trace('MuseCompiler: target "native" not implemented — MuseInterp fallback');
				{ fn: interpOnly(prog), backend: "interp", emitted: false };
			default:
				var fn = JsBackend.compile(prog);
				#if js
				var backend = JsBackend.lastBackend;
				{ fn: fn, backend: backend, emitted: backend == "js" };
				#else
				// JS emission can't execute on this host — report interp.
				{ fn: fn, backend: "interp", emitted: false };
				#end
		};
		lastBackend = result.backend;
		if (strict && !result.emitted)
			throw 'MuseCompiler: strict compile failed for target "$target" (fell back to MuseInterp)';
		return result;
	}

	static function interpOnly(prog:MuseProgram):BarStrategyFn {
		return function(ctx:Dynamic):Dynamic {
			var harness:HarnessContext =
				Std.isOfType(ctx, HarnessContext) ? cast ctx : new HarnessContext();
			var feed:BarFeed = Reflect.hasField(ctx, "feed")
				? Reflect.field(ctx, "feed")
				: BarFeed.synthetic(200, 1);
			var seed = new MuseInterp(harness);
			for (d in prog.decls) seed.registerDeclPublic(d);
			return new MuseInterp(harness).runBacktest(prog, feed);
		};
	}
}
