package musescript.pinescript.ast;

/**
 * Pine expression nodes. Kept close to Muse's own `Expr` shape so `PineLower`
 * is a near-structural map for the common cases — the divergences are the
 * Pine-specific nodes: history reference `e[n]`, namespaced calls, `na`, and
 * tuple values. Spans live in a side-table (PineProgram.spans), enums stay pos-free
 * — same discipline as `musescript.ast`.
 */
enum PineExpr {
	PInt(v:Int);
	PFloat(v:Float);
	PString(v:String);
	PBool(v:Bool);
	PColor(hex:String);
	PNa;                                    // the `na` literal
	PIdent(name:String);

	/** Namespaced identifier chain, e.g. `ta.sma`, `strategy.position_size`.
	 *  Kept as an explicit path (not nested PField) so BuiltinMap can match on
	 *  the fully-qualified name in one lookup. */
	PField(target:PineExpr, field:String);

	PUnop(op:String, e:PineExpr);          // -x, not x
	PBinop(op:String, left:PineExpr, right:PineExpr);
	PTernary(cond:PineExpr, t:PineExpr, f:PineExpr);   // cond ? t : f

	/** Function/builtin call. `callee` is usually PIdent or PField. Pine allows
	 *  named args (`ta.sma(close, length=14)`) — carried as (name, value) with
	 *  name null for positional. */
	PCall(callee:PineExpr, args:Array<PineArg>);

	/** History reference `series[n]` — value of `series` n bars ago. THE
	 *  defining Pine expression; lowers to Muse `ELookback`. */
	PHistory(series:PineExpr, n:PineExpr);

	/** Tuple literal / destructuring source: `[a, b]`. Also array literals in
	 *  collection contexts — disambiguated during lowering by usage. */
	PTuple(items:Array<PineExpr>);

	/** `if`/`switch` used as an expression (v4+ they yield values). */
	PIfExpr(cond:PineExpr, t:Array<PineStmt>, ?f:Array<PineStmt>);
	PSwitchExpr(?subject:PineExpr, cases:Array<PineSwitchCase>);
}

typedef PineArg = {
	var ?name:String;   // named argument (Pine allows `length=14`); null = positional
	var value:PineExpr;
}

typedef PineSwitchCase = {
	/** null pattern = the default `=>` arm. */
	var ?pattern:PineExpr;
	var body:Array<PineStmt>;
}
