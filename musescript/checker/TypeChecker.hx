package musescript.checker;

import musescript.ast.MuseProgram;
import musescript.ast.Decl;
import musescript.ast.Stmt;
import musescript.ast.Expr;
import musescript.ast.Const;
import musescript.ast.OrderKind;
import musescript.ast.ParamOpts;
import musescript.types.MuseType;
import musescript.types.MuseTypes;
import musescript.types.BuiltinSig;
import musescript.types.BuiltinSigs;
import musescript.types.AstSpans;
import musescript.types.SourcePos;

/**
 * Bidirectional type pass over MuseAST.
 * Exposed as typeOf / canAssign for Forge/Swarm legality oracles.
 */
class TypeChecker {
	var diags:Array<Diagnostic>;
	var env:Map<String, MuseType>;
	var lastType:Null<MuseType>;
	/** Strict oracle mode: unknown identifiers are errors, not warnings. */
	var strict:Bool;
	var spans:Null<AstSpans>;

	public function new(?opts:{?strict:Bool}) {
		diags = [];
		env = new Map();
		unknownIdents = new Map();
		lastType = null;
		strict = opts != null && opts.strict == true;
		spans = null;
		seedEnv();
	}

	var unknownIdents:Map<String, Bool>;

	function seedEnv():Void {
		for (name => sig in BuiltinSigs.all())
			env.set(name, TFun(sig.args, sig.ret));
		// Bar fields win over any colliding builtin names.
		for (f in ["open", "high", "low", "close", "volume"])
			env.set(f, TSeries);
		env.set("time", TScalar);
		env.set("bar_index", TScalar);
		env.set("hl2", TSeries);
		env.set("hlc3", TSeries);
		env.set("ohlc4", TSeries);
		// Runtime host objects installed by TradeBuiltins / MuseInterp.
		// Typed as structural objects so member typos (`params.geet`,
		// `Math.abss`) are real diagnostics instead of silent TUnknown.
		env.set("universe", TObject([
			{name: "sample", ty: TUnknown} // optional-arity host fn
		]));
		env.set("params", TObject([
			{name: "register", ty: TUnknown}, // optional-arity host fn
			{name: "get", ty: TFun([TString], TUnknown)},
			{name: "set", ty: TFun([TString, TUnknown], TVoid)}
		]));
		env.set("indicators", TObject([
			{name: "register", ty: TFun([TString, TUnknown], TVoid)},
			{name: "get", ty: TFun([TString], TUnknown)}
		]));
		env.set("Math", TObject(mathHostFields()));
		env.set("true", TBool);
		env.set("false", TBool);
		env.set("null", TUnknown);
		env.set("trace", TFun([TUnknown], TVoid));
	}

	/** Haxe `Math` surface as seen from strategies (JS/interp share it). */
	static function mathHostFields():Array<{name:String, ty:MuseType}> {
		var one = TFun([TScalar], TScalar);
		var two = TFun([TScalar, TScalar], TScalar);
		return [
			{name: "abs", ty: one}, {name: "acos", ty: one}, {name: "asin", ty: one},
			{name: "atan", ty: one}, {name: "ceil", ty: one}, {name: "cos", ty: one},
			{name: "exp", ty: one}, {name: "floor", ty: one}, {name: "log", ty: one},
			{name: "round", ty: one}, {name: "sin", ty: one}, {name: "sqrt", ty: one},
			{name: "tan", ty: one}, {name: "fceil", ty: one}, {name: "ffloor", ty: one},
			{name: "fround", ty: one},
			{name: "atan2", ty: two}, {name: "max", ty: two}, {name: "min", ty: two},
			{name: "pow", ty: two},
			{name: "random", ty: TFun([], TScalar)},
			{name: "isNaN", ty: TFun([TScalar], TBool)},
			{name: "isFinite", ty: TFun([TScalar], TBool)},
			{name: "PI", ty: TScalar}, {name: "NaN", ty: TScalar},
			{name: "NEGATIVE_INFINITY", ty: TScalar},
			{name: "POSITIVE_INFINITY", ty: TScalar}
		];
	}

	/** Host bindings installed by MuseInterp.bindTick / JsBackend.bindTick. */
	function seedTickEnv():Void {
		env.set("tick", TObject([
			{name: "price", ty: TScalar},
			{name: "px", ty: TScalar},
			{name: "last", ty: TScalar},
			{name: "size", ty: TScalar},
			{name: "qty", ty: TScalar},
			{name: "volume", ty: TScalar},
			{name: "time", ty: TScalar},
			{name: "ts", ty: TScalar},
			{name: "timestamp", ty: TScalar},
			{name: "bid", ty: TScalar},
			{name: "ask", ty: TScalar},
			{name: "side", ty: TString},
			{name: "symbol", ty: TString}
		]));
		env.set("price", TScalar);
		env.set("size", TScalar);
		env.set("time", TScalar);
		env.set("bid", TScalar);
		env.set("ask", TScalar);
		env.set("side", TString);
		env.set("symbol", TString);
	}

	/** Host bindings installed by JsBackend.bindEvent (+ tick aliases). */
	function seedEventEnv():Void {
		seedTickEnv();
		env.set("event", TObject([
			{name: "price", ty: TScalar},
			{name: "px", ty: TScalar},
			{name: "size", ty: TScalar},
			{name: "qty", ty: TScalar},
			{name: "time", ty: TScalar},
			{name: "kind", ty: TString},
			{name: "id", ty: TString},
			{name: "reason", ty: TString},
			{name: "side", ty: TString},
			{name: "symbol", ty: TString}
		]));
		env.set("kind", TString);
		env.set("id", TString);
		env.set("reason", TString);
		env.set("px", TScalar);
		env.set("qty", TScalar);
	}

	public function check(prog:MuseProgram):Array<Diagnostic> {
		diags = [];
		unknownIdents = new Map();
		spans = prog.spans;
		seedEnv();
		// Pass 1: bind named FnDecls to placeholder callables so self-/mutual
		// recursion resolves without looping, then Pass 2 refines return types.
		for (d in prog.decls) {
			switch (d) {
				case FnDecl(name, args, _, _) if (name != null):
					env.set(name, TFun([for (_ in args) TUnknown], TUnknown));
				default:
			}
		}
		for (d in prog.decls) checkDecl(d);
		for (s in prog.stmts) checkStmt(s);
		return diags;
	}

	public function typeOf(expr:Expr):MuseType {
		return infer(expr);
	}

	public function canAssign(from:MuseType, to:MuseType):Bool {
		return MuseTypes.canAssign(from, to);
	}

	/** Oracle-grade: Unknown on either side is a refusal, not a free pass. */
	public function canAssignStrict(from:MuseType, to:MuseType):Bool {
		return MuseTypes.canAssignStrict(from, to);
	}

	/**
	 * Wire admissibility under the current mode. An intentionally-opaque
	 * `want` (TUnknown sig slot) always admits; a TUnknown `got` into a
	 * concrete slot is an error in strict mode.
	 */
	function assignOk(got:MuseType, want:MuseType):Bool {
		if (want.match(TUnknown)) return true;
		if (strict && got.match(TUnknown)) return false;
		return MuseTypes.canAssign(got, want);
	}

	public function diagnostics():Array<Diagnostic> {
		return diags;
	}

	function checkDecl(d:Decl):Void {
		switch (d) {
			case ParamDecl(name, def, opts):
				var ty = resolveParamTy(opts, def);
				env.set(name, ty);
				if (def != null) {
					var got = infer(def);
					if (!MuseTypes.canAssign(got, ty))
						err('param $name: expected ${MuseTypes.toString(ty)}, got ${MuseTypes.toString(got)}');
				}
				if (opts != null && opts.ty == "Window" && def != null) {
					var n = constInt(def);
					if (n != null && !MuseTypes.isWindow(n))
						err('Window param $name default $n is not on the Fib ladder');
				}
			case IndicatorDecl(name, args, body):
				for (a in args) env.set(a, TSeries);
				var got = infer(body);
				if (!MuseTypes.canAssign(got, TSeries)
					&& !MuseTypes.canAssign(got, TScalar)
					&& !MuseTypes.canAssign(got, TFeature))
					warn('indicator $name body has type ${MuseTypes.toString(got)}');
				env.set(name, args.length > 0 ? TFun([for (_ in args) TSeries], got) : got);
			case StrategyDecl(_, body):
				for (s in body) checkStmt(s);
			case ModuleDecl(_, params, body):
				for (p in params) {
					var ty = p.ty != null ? MuseTypes.parseName(p.ty) : TScalar;
					if (ty == null) ty = TScalar;
					env.set(p.name, ty);
				}
				for (s in body) checkStmt(s);
			case TemplateDecl(name, params, retTy, body):
				var saved = env.copy();
				var argTys:Array<MuseType> = [];
				for (p in params) {
					var ty = MuseTypes.parseName(p.ty);
					if (ty == null) {
						err('template $name: unknown param type ${p.ty}');
						ty = TUnknown;
					}
					env.set(p.name, ty);
					argTys.push(ty);
				}
				var expect = MuseTypes.parseName(retTy);
				if (expect == null) {
					err('template $name: unknown return type $retTy');
					expect = TUnknown;
				}
				var got = infer(body);
				if (!MuseTypes.canAssign(got, expect))
					err('template $name: expected ${MuseTypes.toString(expect)}, got ${MuseTypes.toString(got)}');
				env = saved;
				env.set(name, TTemplate(argTys, expect));
			case StmtTemplateDecl(name, params, body):
				var saved = env.copy();
				for (p in params) {
					var ty = MuseTypes.parseName(p.ty);
					if (ty == null) {
						err('template $name: unknown param type ${p.ty}');
						ty = TUnknown;
					}
					env.set(p.name, ty);
				}
				for (s in body) checkStmt(s);
				env = saved;
			case FnDecl(name, args, body, _):
				var saved = env.copy();
				for (a in args) env.set(a, TUnknown);
				var retTy = infer(body);
				var argTys = [for (a in args) env.exists(a) ? env.get(a) : TUnknown];
				env = saved;
				if (name != null)
					env.set(name, TFun(argTys, retTy));
			case MacroDecl(_, body):
				for (s in body) checkStmt(s);
		}
	}

	function resolveParamTy(opts:ParamOpts, def:Null<Expr>):MuseType {
		if (opts != null && opts.ty != null) {
			var t = MuseTypes.parseName(opts.ty);
			if (t != null) return t;
			err('unknown param type ${opts.ty}');
		}
		if (def != null) {
			var n = constInt(def);
			if (n != null && MuseTypes.isWindow(n)) return TWindow;
		}
		return TScalar;
	}

	function checkStmt(s:Stmt):Void {
		switch (s) {
			case OnBar(body) | OnPosition(body) | Block(body):
				for (x in body) checkStmt(x);
			case OnTick(body):
				var saved = env.copy();
				seedTickEnv();
				for (x in body) checkStmt(x);
				env = saved;
			case OnEvent(_, body):
				var saved = env.copy();
				seedEventEnv();
				for (x in body) checkStmt(x);
				env = saved;
			case When(cond, body):
				expect(cond, TBool, "when condition");
				for (x in body) checkStmt(x);
			case Use(_, args):
				for (a in args) infer(a.value);
			case ForIn(name, iter, body):
				env.set(name, elementTypeOfExpr(iter));
				for (x in body) checkStmt(x);
			case MatchFor(name, iter, arms):
				env.set(name, elementTypeOfExpr(iter));
				for (a in arms) {
					if (a.guard != null) expect(a.guard, TBool, "match guard");
					infer(a.body);
				}
			case Order(kind, args):
				switch (kind) {
					case Long | Short:
						if (args.length > 0) expect(args[0], TScalar, "order qty");
					case Flat | Close:
				}
			case ExprStmt(e):
				infer(e);
			case Assign(name, e):
				var t = infer(e);
				env.set(name, t);
			case Return(e):
				if (e != null) infer(e);
			case Yield(e) | YieldStar(e):
				infer(e);
		}
	}

	function expect(e:Expr, want:MuseType, ctx:String):MuseType {
		var got = infer(e);
		if (!assignOk(got, want))
			err('$ctx: expected ${MuseTypes.toString(want)}, got ${MuseTypes.toString(got)}', e, DiagCodes.TYPE_MISMATCH);
		refineIdent(e, want);
		return got;
	}

	function infer(e:Expr):MuseType {
		if (e == null) return TUnknown;
		var t = switch (e) {
			case EConst(c):
				switch (c) {
					case CInt(i): MuseTypes.isWindow(i) ? TWindow : TScalar;
					case CFloat(_): TScalar;
					case CBool(_): TBool;
					case CString(_): TString;
					case CNull: TUnknown;
				}
			case EIdent(name) | EBarField(name):
				if (env.exists(name)) env.get(name);
				else {
					noteUnknownIdent(name, e);
					TUnknown;
				}
			case EVar(name, init):
				var ty = init != null ? infer(init) : TUnknown;
				env.set(name, ty);
				ty;
			case EBlock(exprs):
				var r:MuseType = TVoid;
				for (x in exprs) r = infer(x);
				r;
			case EField(obj, field):
				var base = infer(obj);
				switch (base) {
					case TObject(fields):
						lookupField(fields, field, e);
					case TMatrix:
						lookupField(matrixFields(), field, e);
					case TGraph:
						lookupField(graphFields(), field, e);
					case TGraphPath:
						lookupField(graphPathFields(), field, e);
					default:
						// TUnknown / other opaques: keep silent TUnknown (no new false positives).
						TUnknown;
				}
			case EBinop("=", left, right):
				switch (left) {
					case EIdent(n):
						var vt = infer(right);
						env.set(n, vt);
						vt;
					default:
						inferBinop("=", left, right, e);
				}
			case EBinop(op, left, right):
				inferBinop(op, left, right, e);
			case EUnop(op, _, operand):
				var ot = infer(operand);
				switch (op) {
					case "!": TBool;
					case "-": ot.match(TWindow) ? TScalar : ot;
					default: ot;
				}
			case ECall(callee, args):
				inferCall(callee, args);
			case EIf(cond, eif, eelse):
				expect(cond, TBool, "if condition");
				var a = infer(eif);
				var b = eelse != null ? infer(eelse) : TVoid;
				MuseTypes.unify(a, b);
			case EWhile(cond, body):
				expect(cond, TBool, "while condition");
				infer(body);
				TVoid;
			case EFor(name, it, body):
				var elem = elementTypeOfExpr(it);
				var saved = env.copy();
				if (name != null) env.set(name, elem);
				infer(body);
				env = saved;
				TVoid;
			case EFunction(args, body, _, _):
				var saved = env.copy();
				var argTys = [for (_ in args) TUnknown];
				for (a in args) env.set(a, TUnknown);
				var bodyTy = infer(body);
				argTys = [for (a in args) env.exists(a) ? env.get(a) : TUnknown];
				env = saved;
				TFun(argTys, bodyTy);
			case EReturn(ret):
				ret != null ? infer(ret) : TVoid;
			case EArray(base, index):
				var bt = infer(base);
				expect(index, TScalar, "array index");
				if (bt.match(TVector)) TScalar;
				else if (bt.match(TStringArray)) TString;
				else if (bt.match(TUnknown)) TUnknown;
				else {
					err('array index base must be Vector/StringArray, got ${MuseTypes.toString(bt)}');
					TUnknown;
				}
			case EArrayDecl(values):
				inferArrayDecl(values);
			case EObject(fields):
				inferObject(fields);
			case ETernary(cond, eif, eelse):
				expect(cond, TBool, "ternary condition");
				MuseTypes.unify(infer(eif), infer(eelse));
			case EParent(inner):
				infer(inner);
			case EMeta(_, args, inner):
				for (a in args) infer(a);
				infer(inner);
			case ELookback(series, n):
				var st = infer(series);
				if (!MuseTypes.canAssign(st, TSeries) && !st.match(TUnknown))
					err('lookback base must be Series, got ${MuseTypes.toString(st)}');
				var nt = infer(n);
				if (!MuseTypes.canAssign(nt, TWindow) && !MuseTypes.canAssign(nt, TScalar))
					err('lookback index must be Window/Scalar');
				TScalar;
			case EMatch(scrutinee, arms):
				infer(scrutinee);
				var r:MuseType = TUnknown;
				for (a in arms) {
					if (a.guard != null) expect(a.guard, TBool, "match guard");
					r = MuseTypes.unify(r, infer(a.body));
				}
				r;
			case EYield(v):
				infer(v);
			case EYieldStar(v):
				// Flattened yield: element of the iterable when known.
				elementTypeOf(infer(v));
		};
		lastType = t;
		return t;
	}

	function inferBinop(op:String, left:Expr, right:Expr, ?at:Expr):MuseType {
		var lt = infer(left);
		var rt = infer(right);
		return switch (op) {
			case "&&" | "||":
				if (!assignOk(lt, TBool)) err('&&/|| left must be Bool', left, DiagCodes.TYPE_MISMATCH);
				if (!assignOk(rt, TBool)) err('&&/|| right must be Bool', right, DiagCodes.TYPE_MISMATCH);
				TBool;
			case ">" | "<" | ">=" | "<=" | "==" | "!=":
				if (op != "==" && op != "!=") {
					refineIdent(left, TScalar);
					refineIdent(right, TScalar);
				}
				TBool;
			case "+" | "-" | "*" | "/" | "%":
				if (op == "+" && lt.match(TString) && rt.match(TString)) TString;
				else if (lt.match(TString) || rt.match(TString)) {
					err('$op cannot mix String and numeric values; use str_concat', at, DiagCodes.TYPE_MISMATCH);
					TUnknown;
				} else if (lt.match(TSeries) || rt.match(TSeries)) {
					refineIdent(left, TSeries);
					refineIdent(right, TSeries);
					TSeries;
				} else {
					refineIdent(left, TScalar);
					refineIdent(right, TScalar);
					TScalar;
				}
			case "|>":
				// pipe: left |> right  →  call(right, [left]) when right is ident/call
				TUnknown; // desugared before type-check in surface pipeline
			case "=":
				TUnknown;
			default:
				if (strict) err('unknown operator "$op"', at, DiagCodes.UNKNOWN_OP);
				TUnknown;
		};
	}

	function refineIdent(e:Expr, want:MuseType):Void {
		switch (e) {
			case EIdent(n):
				if (!env.exists(n) || env.get(n).match(TUnknown)) env.set(n, want);
			case EParent(inner):
				refineIdent(inner, want);
			default:
		}
	}

	function inferObject(fields:Array<{name:String, e:Expr}>):MuseType {
		var hasNodes = false;
		var hasEdges = false;
		var hasRows = false;
		var hasCols = false;
		var hasData = false;
		for (f in fields) {
			if (f.name == "nodes") hasNodes = true;
			if (f.name == "edges") hasEdges = true;
			if (f.name == "rows") hasRows = true;
			if (f.name == "cols") hasCols = true;
			if (f.name == "data") hasData = true;
		}
		if (hasNodes && hasEdges) {
			for (f in fields) {
				var ft = infer(f.e);
				if (f.name == "nodes" && !MuseTypes.canAssign(ft, TStringArray) && !ft.match(TUnknown))
					err('graph.nodes must be StringArray, got ${MuseTypes.toString(ft)}');
				if (f.name == "directed" && !MuseTypes.canAssign(ft, TBool) && !ft.match(TUnknown))
					err('graph.directed must be Bool, got ${MuseTypes.toString(ft)}');
			}
			return TGraph;
		}
		if (hasRows && hasCols && hasData) {
			for (f in fields) {
				var ft = infer(f.e);
				if ((f.name == "rows" || f.name == "cols")
					&& !MuseTypes.canAssign(ft, TScalar) && !ft.match(TUnknown))
					err('matrix.${f.name} must be Scalar, got ${MuseTypes.toString(ft)}');
				if (f.name == "data" && !MuseTypes.canAssign(ft, TVector) && !ft.match(TUnknown))
					err('matrix.data must be Vector, got ${MuseTypes.toString(ft)}');
			}
			return TMatrix;
		}
		return TObject([for (f in fields) {name: f.name, ty: infer(f.e)}]);
	}

	function inferArrayDecl(values:Array<Expr>):MuseType {
		if (values.length == 0) return TVector;
		var tys = [for (v in values) infer(v)];
		var allString = true;
		var allScalar = true;
		for (t in tys) {
			if (!MuseTypes.canAssign(t, TString)) allString = false;
			if (!MuseTypes.canAssign(t, TScalar)) allScalar = false;
		}
		// Prefer Vector when elements are numeric (or Unknown-only).
		if (allScalar && !allString) return TVector;
		if (allString && !allScalar) return TStringArray;
		if (allScalar) return TVector;
		err('array literal elements must be homogeneous Scalar or String');
		return TUnknown;
	}

	function lookupField(fields:Array<{name:String, ty:MuseType}>, field:String, ?at:Expr):MuseType {
		for (f in fields)
			if (f.name == field) return f.ty;
		err('field "$field" not found on object', at, DiagCodes.FIELD_MISSING);
		return TUnknown;
	}

	static function matrixFields():Array<{name:String, ty:MuseType}> {
		return [
			{name: "rows", ty: TScalar},
			{name: "cols", ty: TScalar},
			{name: "data", ty: TVector}
		];
	}

	static function graphFields():Array<{name:String, ty:MuseType}> {
		return [
			{name: "directed", ty: TBool},
			{name: "nodes", ty: TStringArray},
			{name: "edges", ty: TVector}
		];
	}

	static function graphPathFields():Array<{name:String, ty:MuseType}> {
		return [
			{name: "nodes", ty: TStringArray},
			{name: "distance", ty: TScalar}
		];
	}

	static function enumeratePairType(valueTy:MuseType):MuseType {
		return TObject([
			{name: "i", ty: TScalar},
			{name: "v", ty: valueTy}
		]);
	}

	/** Element type when iterating a known container; otherwise TUnknown. */
	function elementTypeOf(t:MuseType):MuseType {
		return switch (t) {
			case TVector: TScalar;
			case TStringArray: TString;
			case TSet: TString; // string-identity membership
			case TBag: TString; // iterate bag_symbols-style membership
			case TGraphRanks: TObject([
				{name: "node", ty: TString},
				{name: "score", ty: TScalar}
			]);
			default: TUnknown;
		};
	}

	/** Prefer call-shape-aware element typing (`enumerate` → `{i,v}`). */
	function elementTypeOfExpr(iter:Expr):MuseType {
		return switch (iter) {
			case ECall(EIdent("enumerate"), args) if (args.length > 0):
				enumeratePairType(checkedIterableElement("enumerate", args[0]));
			case ECall(EIdent("zip"), args) if (args.length >= 2):
				checkedIterableElement("zip", args[0]);
				checkedIterableElement("zip", args[1]);
				TVector; // each yielded value is a 2-slot array
			case EParent(inner):
				elementTypeOfExpr(inner);
			default:
				elementTypeOf(infer(iter));
		};
	}

	function noteUnknownIdent(name:String, ?e:Expr):Void {
		if (unknownIdents.exists(name)) return;
		unknownIdents.set(name, true);
		if (strict) err('unknown identifier "$name"', e, DiagCodes.UNKNOWN_IDENT);
		else warn('unknown identifier "$name"', e, DiagCodes.UNKNOWN_IDENT);
	}

	function inferCall(callee:Expr, args:Array<Expr>):MuseType {
		switch (callee) {
			case EIdent(name):
				var sig = BuiltinSigs.get(name);
				if (sig != null) return checkAgainstSig(name, sig, args);
				if (env.exists(name)) {
					switch (env.get(name)) {
						case TFun(fa, ret):
							return checkFunArgs(name, fa, ret, args, fa.length);
						case TTemplate(fa, ret):
							return checkFunArgs(name, fa, ret, args, fa.length);
						default:
							for (a in args) infer(a);
							if (strict)
								err('"$name" is not callable (got ${MuseTypes.toString(env.get(name))})', callee, DiagCodes.NOT_CALLABLE);
							return TUnknown;
					}
				}
				if (!unknownIdents.exists(name)) {
					unknownIdents.set(name, true);
					if (strict) err('unknown call "$name"', callee, DiagCodes.UNKNOWN_CALL);
					else warn('unknown call "$name"', callee, DiagCodes.UNKNOWN_CALL);
				}
				for (a in args) infer(a);
				return TUnknown;
			default:
				// Field/expression callees with a known TFun type get real
				// arity + arg checking (Math.pow, params.get, stored lambdas).
				var ct = infer(callee);
				switch (ct) {
					case TFun(fa, ret):
						return checkFunArgs(calleeLabel(callee), fa, ret, args, fa.length);
					default:
				}
				for (a in args) infer(a);
				if (strict) {
					if (ct.match(TUnknown))
						err('unknown call ${calleeLabel(callee)}', callee, DiagCodes.UNKNOWN_CALL);
					else
						err('${calleeLabel(callee)} is not callable (got ${MuseTypes.toString(ct)})', callee, DiagCodes.NOT_CALLABLE);
				}
				return TUnknown;
		}
	}

	static function calleeLabel(callee:Expr):String {
		return switch (callee) {
			case EField(EIdent(base), f): '$base.$f';
			case EField(_, f): f;
			case EIdent(n): n;
			default: "call";
		};
	}

	function checkAgainstSig(name:String, sig:BuiltinSig, args:Array<Expr>):MuseType {
		var minA = sig.minArgs != null ? sig.minArgs : sig.args.length;
		if (args.length < minA)
			err('$name expects at least $minA arg(s), got ${args.length}', args.length > 0 ? args[0] : null, DiagCodes.ARG_COUNT);
		if (args.length > sig.args.length && sig.varArgs != true)
			err('$name expects at most ${sig.args.length} arg(s), got ${args.length}', args.length > 0 ? args[args.length - 1] : null, DiagCodes.ARG_COUNT);
		var special = checkSpecialBuiltin(name, args);
		if (special != null) return special;
		var argTys:Array<MuseType> = [];
		for (i in 0...args.length) {
			if (sig.args.length == 0) {
				argTys.push(infer(args[i]));
				break;
			}
			var want = sig.args[i < sig.args.length ? i : sig.args.length - 1];
			var got = infer(args[i]);
			argTys.push(got);
			// Legacy: string literal series key is accepted as Series
			if (want.match(TSeries) && isStringLit(args[i])) continue;
			// Scalar current-bar values of known series idents are Series-compatible at call sites
			if (want.match(TSeries) && MuseTypes.canAssign(got, TSeries)) continue;
			if (want.match(TSeries) && got.match(TScalar) && isBarSeriesIdent(args[i])) continue;
			// Window params may be Scalar-typed leaves; only reject off-ladder *constants*.
			if (want.match(TWindow) && (got.match(TWindow) || got.match(TScalar) || got.match(TUnknown))) {
				var n = constInt(args[i]);
				if (n != null && !MuseTypes.isWindow(n))
					err('$name arg ${i + 1}: Window value $n not on Fib ladder', args[i], DiagCodes.WINDOW_LADDER);
				continue;
			}
			if (!assignOk(got, want))
				err('$name arg ${i + 1}: expected ${MuseTypes.toString(want)}, got ${MuseTypes.toString(got)}', args[i], DiagCodes.ARG_TYPE);
		}
		// dict_get(d, k, default) → type of default when present
		if (name == "dict_get" && argTys.length >= 3) return argTys[2];
		return sig.ret;
	}

	function checkSpecialBuiltin(name:String, args:Array<Expr>):Null<MuseType> {
		return switch (name) {
			case "dict_get":
				if (args.length >= 1) expect(args[0], TDict, name + " arg 1");
				if (args.length >= 2) infer(args[1]);
				if (args.length >= 3) infer(args[2]) else TUnknown;
			case "map" | "flatMap":
				var elem = args.length > 0 ? checkedIterableElement(name, args[0]) : TUnknown;
				var ret = args.length > 1 ? inferCallableWithArgs(args[1], [elem], name + " callback") : TUnknown;
				ret.match(TString) ? TStringArray : TVector;
			case "filter" | "takeWhile":
				var elem = args.length > 0 ? checkedIterableElement(name, args[0]) : TUnknown;
				if (args.length > 1) {
					var ret = inferCallableWithArgs(args[1], [elem], name + " predicate");
					if (!MuseTypes.canAssign(ret, TBool))
						err('$name predicate: expected Bool, got ${MuseTypes.toString(ret)}');
				}
				args.length > 0 ? collectionResultType(infer(args[0])) : TVector;
			case "any" | "all":
				var elem = args.length > 0 ? checkedIterableElement(name, args[0]) : TUnknown;
				if (args.length > 1) {
					var ret = inferCallableWithArgs(args[1], [elem], name + " predicate");
					if (!MuseTypes.canAssign(ret, TBool))
						err('$name predicate: expected Bool, got ${MuseTypes.toString(ret)}');
				}
				TBool;
			case "find":
				var elem = args.length > 0 ? checkedIterableElement(name, args[0]) : TUnknown;
				if (args.length > 1) {
					var ret = inferCallableWithArgs(args[1], [elem], name + " predicate");
					if (!MuseTypes.canAssign(ret, TBool))
						err('$name predicate: expected Bool, got ${MuseTypes.toString(ret)}');
				}
				elem;
			case "reduce":
				var elem = args.length > 0 ? checkedIterableElement(name, args[0]) : TUnknown;
				var acc = args.length > 1 ? infer(args[1]) : TUnknown;
				if (args.length > 2) {
					var ret = inferCallableWithArgs(args[2], [acc, elem], name + " reducer");
					if (!MuseTypes.canAssign(ret, acc))
						err('$name reducer: expected ${MuseTypes.toString(acc)}, got ${MuseTypes.toString(ret)}');
				}
				acc;
			case "scan":
				var elem = args.length > 0 ? checkedIterableElement(name, args[0]) : TUnknown;
				var acc = args.length > 1 ? infer(args[1]) : TUnknown;
				if (args.length > 2) inferCallableWithArgs(args[2], [acc, elem], name + " reducer");
				TVector;
			case "sum" | "min" | "max" | "avg":
				var elem = args.length > 0 ? checkedIterableElement(name, args[0]) : TUnknown;
				if (!elem.match(TUnknown) && !MuseTypes.canAssign(elem, TScalar))
					err('$name expects numeric iterable, got element ${MuseTypes.toString(elem)}');
				TScalar;
			case "count":
				if (args.length > 0) checkedIterableElement(name, args[0]);
				TScalar;
			case "take" | "drop":
				var coll = args.length > 0 ? infer(args[0]) : TUnknown;
				checkedIterableElementType(name, coll);
				if (args.length > 1) expect(args[1], TScalar, name + " count");
				collectionResultType(coll);
			case "enumerate":
				var elem = args.length > 0 ? checkedIterableElement(name, args[0]) : TUnknown;
				// Value position stays Vector; for-in uses elementTypeOfExpr for `{i,v}`.
				TVector;
			case "zip":
				if (args.length >= 1) checkedIterableElement(name, args[0]);
				if (args.length >= 2) checkedIterableElement(name, args[1]);
				TVector;
			case "merge":
				if (args.length >= 1) checkedIterableElement(name, args[0]);
				if (args.length >= 2) checkedIterableElement(name, args[1]);
				TVector;
			case "zipWith":
				var a = args.length > 0 ? checkedIterableElement(name, args[0]) : TUnknown;
				var b = args.length > 1 ? checkedIterableElement(name, args[1]) : TUnknown;
				var ret = args.length > 2 ? inferCallableWithArgs(args[2], [a, b], name + " combiner") : TUnknown;
				ret.match(TString) ? TStringArray : TVector;
			default:
				null;
		}
	}

	function checkedIterableElementType(name:String, t:MuseType, ?at:Expr):MuseType {
		switch (t) {
			case TDict | TGraph | TMatrix | TObject(_) | TBag:
				err('$name expects iterable, got ${MuseTypes.toString(t)}', at, DiagCodes.NOT_ITERABLE);
			default:
		}
		return elementTypeOf(t);
	}

	function checkedIterableElement(name:String, e:Expr):MuseType {
		return checkedIterableElementType(name, infer(e), e);
	}

	function collectionResultType(t:MuseType):MuseType {
		return switch (t) {
			case TStringArray: TStringArray;
			default: TVector;
		};
	}

	function inferCallableWithArgs(e:Expr, argTys:Array<MuseType>, ctx:String):MuseType {
		return switch (e) {
			case EFunction(args, body, _, _):
				if (args.length != argTys.length)
					err('$ctx expects ${argTys.length} arg(s), got ${args.length}');
				var saved = env.copy();
				for (i in 0...args.length) {
					var ty = i < argTys.length ? argTys[i] : TUnknown;
					env.set(args[i], ty);
				}
				var ret = infer(body);
				env = saved;
				ret;
			default:
				var ft = infer(e);
				switch (ft) {
					case TFun(fa, ret):
						if (fa.length != argTys.length)
							err('$ctx expects ${argTys.length} arg(s), got ${fa.length}');
						for (i in 0...argTys.length) {
							if (i >= fa.length) break;
							if (!MuseTypes.canAssign(argTys[i], fa[i]))
								err('$ctx arg ${i + 1}: expected ${MuseTypes.toString(fa[i])}, got ${MuseTypes.toString(argTys[i])}');
						}
						ret;
					default:
						TUnknown;
				}
		}
	}

	function checkFunArgs(name:String, fa:Array<MuseType>, ret:MuseType, args:Array<Expr>, max:Int):MuseType {
		if (args.length != fa.length)
			err('$name expects ${fa.length} arg(s), got ${args.length}', args.length > 0 ? args[0] : null, DiagCodes.ARG_COUNT);
		for (i in 0...args.length) {
			if (i >= fa.length) break;
			var got = infer(args[i]);
			if (fa[i].match(TSeries) && isStringLit(args[i])) continue;
			if (!assignOk(got, fa[i]))
				err('$name arg ${i + 1}: expected ${MuseTypes.toString(fa[i])}, got ${MuseTypes.toString(got)}', args[i], DiagCodes.ARG_TYPE);
		}
		return ret;
	}

	function isStringLit(e:Expr):Bool {
		return switch (e) {
			case EConst(CString(_)): true;
			default: false;
		};
	}

	function isBarSeriesIdent(e:Expr):Bool {
		return switch (e) {
			case EIdent(n) | EBarField(n):
				n == "open" || n == "high" || n == "low" || n == "close" || n == "volume"
					|| n == "hl2" || n == "hlc3" || n == "ohlc4";
			default: false;
		};
	}

	function constInt(e:Expr):Null<Int> {
		return switch (e) {
			case EConst(CInt(i)): i;
			default: null;
		};
	}

	function err(msg:String, ?at:Expr, ?code:String):Void {
		diags.push(Diagnostics.error(msg, posOf(at), code));
	}
	function warn(msg:String, ?at:Expr, ?code:String):Void {
		diags.push(Diagnostics.warning(msg, posOf(at), code));
	}
	function posOf(e:Null<Expr>):Null<SourcePos> {
		return e == null || spans == null ? null : spans.ofExpr(e);
	}
}
