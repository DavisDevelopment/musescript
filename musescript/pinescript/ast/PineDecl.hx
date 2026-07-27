package musescript.pinescript.ast;

import musescript.pinescript.ast.PineExpr.PineArg;
import musescript.pinescript.ast.PineType;

/**
 * Top-level Pine declarations. A Pine script has exactly one header call
 * (`indicator(...)`, `strategy(...)`, or `library(...)`) plus function defs,
 * type defs, imports, and a body of statements executed once per bar.
 */
enum PineDecl {
	/** The script header: `indicator("My Ind", overlay=true)` /
	 *  `strategy("My Strat", ...)`. `kind` distinguishes them; `args` carries the
	 *  configuration (title, overlay, pyramiding, default_qty, …). */
	PHeader(kind:PineScriptKind, args:Array<PineArg>);

	/** User function: `f(x, y) => body`  or multi-line with an indented block. */
	PFunc(name:String, params:Array<PineParam>, body:Array<PineStmt>, exported:Bool);

	/** User-defined type (v5+): `type Point` with typed fields. */
	PTypeDef(name:String, fields:Array<{name:String, ty:PineType, ?def:PineExpr}>, exported:Bool);

	/** `import user/lib/version as alias`. We do NOT fetch — lowering either
	 *  inlines a known library or emits an Unsupported diagnostic. */
	PImport(user:String, lib:String, version:Int, ?alias:String);

	/** A top-level statement in the per-bar body (assignments, plots, orders). */
	PTop(stmt:PineStmt);
}

enum PineScriptKind {
	SkIndicator;   // `indicator(...)` (was `study(...)` in v1–v3)
	SkStrategy;    // `strategy(...)`
	SkLibrary;     // `library(...)`
}

typedef PineParam = {
	var name:String;
	var ?ty:PineType;      // Pine params are usually untyped (inferred)
	var ?def:PineExpr;     // default value
}
