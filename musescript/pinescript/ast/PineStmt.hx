package musescript.pinescript.ast;

import musescript.pinescript.ast.PineExpr.PineSwitchCase;
import musescript.pinescript.ast.PineType;

/**
 * Pine statement nodes. Pine blurs the stmt/expr line (v4+ `if`/`switch` yield
 * values), so simple expression-valued conditionals live in PineExpr; these are
 * the statement-position forms that carry layout blocks.
 */
enum PineStmt {
	/** `x = expr` — declares/binds. Optional qualifier keyword (`var`/`varip`)
	 *  and optional declared type (`float x = ...`). */
	PAssign(name:String, value:PineExpr, ?decl:PineDeclKind, ?ty:PineType);

	/** `x := expr` — reassign an existing binding (v4+). */
	PReassign(name:String, value:PineExpr);

	/** Tuple destructuring: `[macd, signal, hist] = ta.macd(...)`. */
	PTupleAssign(names:Array<String>, value:PineExpr, ?decl:PineDeclKind);

	PExpr(e:PineExpr);   // bare expression statement (e.g. a `plot(...)` call)

	PIf(cond:PineExpr, then:Array<PineStmt>, elifs:Array<{cond:PineExpr, body:Array<PineStmt>}>, ?els:Array<PineStmt>);
	PForTo(varName:String, from:PineExpr, to:PineExpr, ?step:PineExpr, body:Array<PineStmt>);
	PForIn(vars:Array<String>, iter:PineExpr, body:Array<PineStmt>);   // `for [i, v] in arr`
	PWhile(cond:PineExpr, body:Array<PineStmt>);
	PSwitch(?subject:PineExpr, cases:Array<PineSwitchCase>);

	PBreak;
	PContinue;
	PReturn(?e:PineExpr);   // implicit in Pine (last expr of a fn), explicit rare
}

/** Whether an assignment declares a persistent binding. */
enum PineDeclKind {
	DkLet;     // plain `x = ...` — re-evaluated each bar
	DkVar;     // `var x = ...` — initialized once, persists across bars
	DkVarip;   // `varip x = ...` — persists across bars AND intra-bar ticks
}
