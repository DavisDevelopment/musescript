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

/**
 * Bidirectional type pass over MuseAST.
 * Exposed as typeOf / canAssign for Forge/Swarm legality oracles.
 */
class TypeChecker {
	var diags:Array<Diagnostic>;
	var env:Map<String, MuseType>;
	var lastType:Null<MuseType>;

	public function new() {
		diags = [];
		env = new Map();
		lastType = null;
		seedEnv();
	}

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
	}

	public function check(prog:MuseProgram):Array<Diagnostic> {
		diags = [];
		seedEnv();
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
			case FnDecl(name, args, body, _):
				for (a in args) if (!env.exists(a)) env.set(a, TUnknown);
				infer(body);
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
			case OnBar(body) | OnTick(body) | OnEvent(_, body) | Block(body):
				for (x in body) checkStmt(x);
			case When(cond, body):
				expect(cond, TBool, "when condition");
				for (x in body) checkStmt(x);
			case Use(_, args):
				for (a in args) infer(a.value);
			case ForIn(name, iter, body):
				infer(iter);
				env.set(name, TUnknown);
				for (x in body) checkStmt(x);
			case MatchFor(name, iter, arms):
				infer(iter);
				env.set(name, TUnknown);
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
		if (!MuseTypes.canAssign(got, want))
			err('$ctx: expected ${MuseTypes.toString(want)}, got ${MuseTypes.toString(got)}');
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
				else TUnknown;
			case EVar(name, init):
				var ty = init != null ? infer(init) : TUnknown;
				env.set(name, ty);
				ty;
			case EBlock(exprs):
				var r:MuseType = TVoid;
				for (x in exprs) r = infer(x);
				r;
			case EField(obj, _):
				infer(obj);
				TUnknown;
			case EBinop(op, left, right):
				inferBinop(op, left, right);
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
			case EFor(_, it, body):
				infer(it);
				infer(body);
				TVoid;
			case EFunction(_, body, _, _):
				infer(body);
				TUnknown;
			case EReturn(ret):
				ret != null ? infer(ret) : TVoid;
			case EArray(base, index):
				var bt = infer(base);
				expect(index, TScalar, "array index");
				if (bt.match(TVector)) TScalar;
				else if (bt.match(TUnknown)) TUnknown;
				else {
					err('array index base must be Vector, got ${MuseTypes.toString(bt)}');
					TUnknown;
				}
			case EArrayDecl(values):
				for (v in values) {
					var vt = infer(v);
					if (!MuseTypes.canAssign(vt, TScalar))
						err('Vector element must be Scalar, got ${MuseTypes.toString(vt)}');
				}
				TVector;
			case EObject(fields):
				for (f in fields) infer(f.e);
				TUnknown;
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
			case EYield(v) | EYieldStar(v):
				infer(v);
				TUnknown;
		};
		lastType = t;
		return t;
	}

	function inferBinop(op:String, left:Expr, right:Expr):MuseType {
		var lt = infer(left);
		var rt = infer(right);
		return switch (op) {
			case "&&" | "||":
				if (!MuseTypes.canAssign(lt, TBool)) err('&&/|| left must be Bool');
				if (!MuseTypes.canAssign(rt, TBool)) err('&&/|| right must be Bool');
				TBool;
			case ">" | "<" | ">=" | "<=" | "==" | "!=":
				TBool;
			case "+" | "-" | "*" | "/" | "%":
				if (op == "+" && lt.match(TString) && rt.match(TString)) TString;
				else if (lt.match(TString) || rt.match(TString)) {
					err('$op cannot mix String and numeric values; use str_concat');
					TUnknown;
				} else if (lt.match(TSeries) || rt.match(TSeries)) TSeries;
				else TScalar;
			case "|>":
				// pipe: left |> right  →  call(right, [left]) when right is ident/call
				TUnknown; // desugared before type-check in surface pipeline
			default:
				TUnknown;
		};
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
					}
				}
				for (a in args) infer(a);
				return TUnknown;
			case EField(EIdent("Math"), _):
				for (a in args) expect(a, TScalar, "Math arg");
				return TScalar;
			default:
				infer(callee);
				for (a in args) infer(a);
				return TUnknown;
		}
	}

	function checkAgainstSig(name:String, sig:BuiltinSig, args:Array<Expr>):MuseType {
		var minA = sig.minArgs != null ? sig.minArgs : sig.args.length;
		if (args.length < minA)
			err('$name expects at least $minA arg(s), got ${args.length}');
		if (args.length > sig.args.length && sig.varArgs != true)
			err('$name expects at most ${sig.args.length} arg(s), got ${args.length}');
		for (i in 0...args.length) {
			if (sig.args.length == 0) break;
			var want = sig.args[i < sig.args.length ? i : sig.args.length - 1];
			var got = infer(args[i]);
			// Legacy: string literal series key is accepted as Series
			if (want.match(TSeries) && isStringLit(args[i])) continue;
			// Scalar current-bar values of known series idents are Series-compatible at call sites
			if (want.match(TSeries) && MuseTypes.canAssign(got, TSeries)) continue;
			if (want.match(TSeries) && got.match(TScalar) && isBarSeriesIdent(args[i])) continue;
			// Window params may be Scalar-typed leaves; only reject off-ladder *constants*.
			if (want.match(TWindow) && (got.match(TWindow) || got.match(TScalar) || got.match(TUnknown))) {
				var n = constInt(args[i]);
				if (n != null && !MuseTypes.isWindow(n))
					err('$name arg ${i + 1}: Window value $n not on Fib ladder');
				continue;
			}
			if (!MuseTypes.canAssign(got, want))
				err('$name arg ${i + 1}: expected ${MuseTypes.toString(want)}, got ${MuseTypes.toString(got)}');
		}
		return sig.ret;
	}

	function checkFunArgs(name:String, fa:Array<MuseType>, ret:MuseType, args:Array<Expr>, max:Int):MuseType {
		if (args.length != fa.length)
			err('$name expects ${fa.length} arg(s), got ${args.length}');
		for (i in 0...args.length) {
			if (i >= fa.length) break;
			var got = infer(args[i]);
			if (fa[i].match(TSeries) && isStringLit(args[i])) continue;
			if (!MuseTypes.canAssign(got, fa[i]))
				err('$name arg ${i + 1}: expected ${MuseTypes.toString(fa[i])}, got ${MuseTypes.toString(got)}');
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

	function err(msg:String):Void diags.push(Diagnostics.error(msg));
	function warn(msg:String):Void diags.push(Diagnostics.warning(msg));
}
