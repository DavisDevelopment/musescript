package musescript.parse;

import hscript.Expr;
import hscript.Parser;
import hscript.Tools;

import musescript.ast.MuseProgram;
import musescript.ast.Decl;
import musescript.ast.Stmt;
import musescript.ast.MatchArm;
import musescript.ast.FnKind;
import musescript.ast.OrderKind;
import musescript.ast.ParamOpts;
import musescript.ast.Pattern;
import musescript.ast.Expr as MExpr;
import musescript.ast.Const as MC;
import musescript.ast.MuseNodes;
import musescript.types.BuiltinSigs;
import musescript.types.MuseType;

using hscript.Tools;

/**
 * Composes hscript.Parser and lowers Expr → MuseProgram / Muse AST.
 *
 * hscript constructors (EIdent, CInt, …) stay in scope for Tools.expr matching.
 * Muse nodes are built only via MuseNodes / MExpr / MC — never bare EIdent for Muse.
 */
class MuseParser {
	var parser:Parser;

	public function new() {
		parser = new Parser();
		parser.allowMetadata = true;
		parser.allowTypes = true;
		parser.allowJSON = true;
	}

	public function parse(source:String, ?origin:String):MuseProgram {
		if (musescript.parse.StrategyParser.looksLike(source))
			return new musescript.parse.StrategyParser().parse(source, origin);
		var expr = parser.parseString(source, origin);
		return lowerProgram(expr);
	}

	public function parseExpr(source:String, ?origin:String):MExpr {
		var expr = parser.parseString(source, origin);
		return lowerExpr(expr);
	}

	/** Raw hscript parse — bootstrap / debugging */
	public function parseRaw(source:String, ?origin:String):hscript.Expr {
		return parser.parseString(source, origin);
	}

	function lowerProgram(e:hscript.Expr):MuseProgram {
		var decls:Array<Decl> = [];
		var stmts:Array<Stmt> = [];
		var list = flattenTop(e);
		for (item in list) {
			switch (Tools.expr(item)) {
				case EMeta(name, params, body):
					switch (name) {
						case "strategy" | ":strategy":
							var n = metaString(params, 0, "strategy");
							decls.push(StrategyDecl(n, lowerStmts(body)));
						case "param" | ":param":
							decls.push(readParam(params, body));
						case "macro" | ":macro":
							var n = metaString(params, 0, "macro");
							decls.push(MacroDecl(n, lowerStmts(body)));
						case "indicator" | ":indicator":
							decls.push(readIndicator(params, body));
						case "on" | ":on":
							stmts.push(readOn(params, body));
						default:
							stmts.push(ExprStmt(lowerExpr(item)));
					}
				case EFunction(args, body, name, _):
					var argNames = [for (a in args) a.name];
					var kind = Normal;
					// function* sugar via name ending or meta on body — detect yield in body
					if (containsYield(body)) kind = Generator;
					decls.push(FnDecl(name, argNames, lowerExpr(body), kind));
				default:
					stmts.push(ExprStmt(lowerExpr(item)));
			}
		}
		return { decls: decls, stmts: stmts };
	}

	function flattenTop(e:hscript.Expr):Array<hscript.Expr> {
		var out:Array<hscript.Expr> = [];
		function walk(x:hscript.Expr):Void {
			if (x == null) return;
			switch (Tools.expr(x)) {
				case EBlock(a):
					for (i in a) walk(i);
				case EMeta(name, params, body):
					switch (Tools.expr(body)) {
						case EMeta(_, _, _) | EBlock(_):
							// Chained metas: peel this one with a stub body, continue into chain
							var stub = switch (Tools.expr(body)) {
								case EBlock(_): body; // rare: @macro { } as immediate body
								default: null;
							};
							if (stub != null && (name == "macro" || name == ":macro" || name == "indicator" || name == ":indicator" || name == "on" || name == ":on")) {
								out.push(x);
							} else if (stub != null) {
								out.push(x);
							} else {
								// body is next meta — emit this meta with empty block, then walk body
								out.push(mkMeta(name, params, hscriptBlock()));
								walk(body);
							}
						default:
							out.push(x);
					}
				default:
					out.push(x);
			}
		}
		walk(e);
		return out;
	}

	function mkMeta(name:String, params:Array<hscript.Expr>, body:hscript.Expr):hscript.Expr {
		#if hscriptPos
		return { e: EMeta(name, params, body), pmin: 0, pmax: 0, origin: "", line: 0 };
		#else
		return EMeta(name, params, body);
		#end
	}

	function hscriptBlock():hscript.Expr {
		#if hscriptPos
		return { e: EBlock([]), pmin: 0, pmax: 0, origin: "", line: 0 };
		#else
		return EBlock([]);
		#end
	}

	function readParam(params:Array<hscript.Expr>, body:hscript.Expr):Decl {
		// @param fast = 10  OR @param("fast", 10) OR @param fast = 10 { min, max }
		var name = "param";
		var def:Null<MExpr> = null;
		var opts:ParamOpts = {};
		if (params != null && params.length > 0) {
			switch (Tools.expr(params[0])) {
				case EConst(CString(s)):
					name = s;
				case EIdent(id):
					name = id;
				case EBinop("=", left, rhs):
					switch (Tools.expr(left)) {
						case EIdent(id):
							name = id;
							def = lowerExpr(rhs);
						default:
					}
				default:
					name = Std.string(params[0]);
			}
			if (def == null && params.length > 1) {
				def = lowerExpr(params[1]);
			}
		}
		switch (Tools.expr(body)) {
			case EBinop("=", left, rhs):
				switch (Tools.expr(left)) {
					case EIdent(id):
						name = id;
						def = lowerExpr(rhs);
					default:
				}
			case EObject(fields):
				for (f in fields) {
					switch (f.name) {
						case "min": opts.min = numOf(lowerExpr(f.e));
						case "max": opts.max = numOf(lowerExpr(f.e));
						case "step": opts.step = numOf(lowerExpr(f.e));
						case "tune": opts.tune = strOf(lowerExpr(f.e));
						default:
					}
				}
			case EConst(_) | EIdent(_):
				def = lowerExpr(body);
			default:
				if (def == null) def = lowerExpr(body);
		}
		return ParamDecl(name, def, opts);
	}

	function readIndicator(params:Array<hscript.Expr>, body:hscript.Expr):Decl {
		var name = metaString(params, 0, "indicator");
		var fn = extractFunction(body);
		if (fn == null) throw 'MuseParser: @indicator requires a function body';
		var argNames = [for (a in fn.args) a.name];
		if (name == "indicator" && fn.name != null && fn.name != "") name = fn.name;
		return IndicatorDecl(name, argNames, lowerExpr(fn.body));
	}

	function extractFunction(e:hscript.Expr):Null<{args:Array<{name:String}>, body:hscript.Expr, name:Null<String>}> {
		if (e == null) return null;
		return switch (Tools.expr(e)) {
			case EFunction(args, body, name, _):
				{ args: args, body: body, name: name };
			case EBlock(stmts):
				for (s in stmts) {
					var f = extractFunction(s);
					if (f != null) return f;
				}
				null;
			case EMeta(_, _, inner):
				extractFunction(inner);
			case EParent(inner):
				extractFunction(inner);
			default:
				null;
		};
	}

	function readOn(params:Array<hscript.Expr>, body:hscript.Expr):Stmt {
		var kind = "bar";
		if (params != null && params.length > 0) {
			switch (Tools.expr(params[0])) {
				case EIdent(id):
					kind = id;
				case EConst(CString(id)):
					kind = id;
				default:
			}
		}
		// also allow @on(bar) body or metadata name "on" with ident bar as first param
		return switch (kind) {
			case "bar": OnBar(lowerStmts(body));
			case "position": OnPosition(lowerStmts(body));
			case "tick": OnTick(lowerStmts(body));
			case "event":
				var stream = params != null && params.length > 1 ? identOf(params[1]) : "events";
				OnEvent(stream, lowerStmts(body));
			default:
				OnEvent(kind, lowerStmts(body));
		};
	}

	public function lowerStmts(e:hscript.Expr):Array<Stmt> {
		return switch (Tools.expr(e)) {
			case EBlock(a): [for (x in a) lowerStmt(x)];
			default: [lowerStmt(e)];
		};
	}

	function lowerStmt(e:hscript.Expr):Stmt {
		return switch (Tools.expr(e)) {
			case EMeta("on" | ":on", params, body):
				readOn(params, body);
			case EMeta("yield" | ":yield", _, body):
				Yield(lowerExpr(body));
			case EMeta("yieldStar" | "yieldstar" | ":yieldStar", _, body):
				YieldStar(lowerExpr(body));
			case EVar(n, _, init):
				Assign(n, init != null ? lowerExpr(init) : MuseNodes.nullExpr());
			case EBlock(a):
				Block([for (x in a) lowerStmt(x)]);
			case EReturn(v):
				Return(v != null ? lowerExpr(v) : null);
			case EFor(n, it, body):
				ForIn(n, lowerExpr(it), lowerStmts(body));
			case ECall(callee, args):
				switch (Tools.expr(callee)) {
					case EIdent("long"): return Order(Long, [for (a in args) lowerExpr(a)]);
					case EIdent("short"): return Order(Short, [for (a in args) lowerExpr(a)]);
					case EIdent("flat"): return Order(Flat, [for (a in args) lowerExpr(a)]);
					case EIdent("close"): return Order(Close, [for (a in args) lowerExpr(a)]);
					default:
				}
				ExprStmt(lowerExpr(e));
			// match for x in xs { case ... } via EMeta('match', ...) or special call
			case EMeta("match" | ":match", params, body):
				lowerMatchStmt(params, body);
			default:
				ExprStmt(lowerExpr(e));
		};
	}

	function lowerMatchStmt(params:Array<hscript.Expr>, body:hscript.Expr):Stmt {
		// @match(for, name, iter) { cases }  — or match as expression
		if (params != null && params.length >= 2) {
			switch (Tools.expr(params[0])) {
				case EIdent("for"):
					var name = identOf(params[1]);
					var iter = params.length > 2 ? lowerExpr(params[2]) : MuseNodes.ident("events");
					var arms = readMatchArms(body);
					return MatchFor(name, iter, arms);
				default:
			}
		}
		var scrut = params != null && params.length > 0 ? lowerExpr(params[0]) : MuseNodes.ident("_");
		return ExprStmt(MuseNodes.match(scrut, readMatchArms(body)));
	}

	public function lowerExpr(e:hscript.Expr):MExpr {
		if (e == null) return MuseNodes.nullExpr();
		return switch (Tools.expr(e)) {
			case EConst(c):
				switch (c) {
					case CInt(i): MuseNodes.intExpr(i);
					case CFloat(f): MuseNodes.floatExpr(f);
					case CString(s): MuseNodes.stringExpr(s);
				}
			case EIdent("true"): MuseNodes.boolExpr(true);
			case EIdent("false"): MuseNodes.boolExpr(false);
			case EIdent("null"): MuseNodes.nullExpr();
			case EIdent(id):
				if (isBarField(id)) MuseNodes.barField(id) else MuseNodes.ident(id);
			case EVar(n, _, init):
				MuseNodes.evar(n, init != null ? lowerExpr(init) : null);
			case EParent(e):
				MuseNodes.parent(lowerExpr(e));
			case EBlock(a):
				MuseNodes.block([for (x in a) lowerExpr(x)]);
			case EField(e, f):
				MuseNodes.field(lowerExpr(e), f);
			case EBinop(op, a, b):
				MuseNodes.binop(op, lowerExpr(a), lowerExpr(b));
			case EUnop(op, prefix, e):
				MuseNodes.unop(op, prefix, lowerExpr(e));
			case ECall(e, args):
				MuseNodes.call(lowerExpr(e), [for (a in args) lowerExpr(a)]);
			case EIf(c, a, b):
				MuseNodes.eif(lowerExpr(c), lowerExpr(a), b != null ? lowerExpr(b) : null);
			case EWhile(c, b):
				MuseNodes.ewhile(lowerExpr(c), lowerExpr(b));
			case EFor(n, it, b):
				MuseNodes.efor(n, lowerExpr(it), lowerExpr(b));
			case EFunction(args, body, name, _):
				var argNames = [for (a in args) a.name];
				var kind = containsYield(body) ? Generator : Normal;
				MuseNodes.efunction(argNames, lowerExpr(body), kind, name);
			case EReturn(v):
				MuseNodes.ereturn(v != null ? lowerExpr(v) : null);
			case EArray(e, idx):
				lowerArrayAccess(e, idx);
			case EArrayDecl(values):
				MuseNodes.arrayDecl([for (v in values) lowerExpr(v)]);
			case EObject(fields):
				MuseNodes.object([for (f in fields) { name: f.name, e: lowerExpr(f.e) }]);
			case ETernary(c, a, b):
				MuseNodes.ternary(lowerExpr(c), lowerExpr(a), lowerExpr(b));
			case EMeta("yield" | ":yield", _, body):
				MuseNodes.eyield(lowerExpr(body));
			case EMeta("yieldStar" | "yieldstar" | ":yieldStar", _, body):
				MuseNodes.eyieldStar(lowerExpr(body));
			case EMeta("match" | ":match", params, body):
				var scrut = params != null && params.length > 0 ? lowerExpr(params[0]) : MuseNodes.ident("_");
				MuseNodes.match(scrut, readMatchArms(body));
			case EMeta(name, params, body):
				MuseNodes.meta(name, params != null ? [for (p in params) lowerExpr(p)] : [], lowerExpr(body));
			case ESwitch(e, cases, edef):
				// Lower switch into EMatch with PatLit / PatBind
				var arms:Array<MatchArm> = [];
				for (c in cases) {
					for (v in c.values) {
						arms.push({ pattern: exprToPattern(v), body: lowerExpr(c.expr) });
					}
				}
				if (edef != null) arms.push({ pattern: PatWild, body: lowerExpr(edef) });
				MuseNodes.match(lowerExpr(e), arms);
			default:
				throw 'MuseParser: unhandled expr $e';
		};
	}

	function readMatchArms(body:hscript.Expr):Array<MatchArm> {
		var arms:Array<MatchArm> = [];
		for (item in matchArmItems(body)) {
			switch (Tools.expr(item)) {
				case EMeta("if" | "when" | ":if" | ":when", params, pbody):
					switch (Tools.expr(pbody)) {
						case EBinop("=>", left, right):
							arms.push({
								pattern: exprToPattern(left),
								guard: params != null && params.length > 0 ? lowerExpr(params[0]) : null,
								body: lowerExpr(right)
							});
						default:
							arms.push({ pattern: PatWild, body: lowerExpr(item) });
					}
				case EMeta("rest" | ":rest", params, pbody):
					switch (Tools.expr(pbody)) {
						case EBinop("=>", left, right):
							var rest = params != null && params.length > 0 ? identOf(params[0]) : null;
							var pat = switch (Tools.expr(left)) {
								case EArrayDecl(values): arrayPattern(values, rest);
								default: PatArr([exprToPattern(left)], rest);
							};
							arms.push({ pattern: pat, body: lowerExpr(right) });
						default:
							arms.push({ pattern: exprToPattern(item), body: MuseNodes.nullExpr() });
					}
				// case Pat => body  encoded as EBinop("=>", pat, body)
				case EBinop("=>", left, right):
					var pat = exprToPattern(left);
					var guard:Null<MExpr> = null;
					// pat if guard — @if(cond) pat => body (hscript cannot parse `pat if cond` here)
					switch (Tools.expr(left)) {
						case EIf(cond, then, _):
							pat = exprToPattern(then);
							guard = lowerExpr(cond);
						case EMeta("if" | "when" | ":if" | ":when", params, pbody):
							pat = exprToPattern(pbody);
							guard = params != null && params.length > 0 ? lowerExpr(params[0]) : null;
						default:
					}
					arms.push({ pattern: pat, guard: guard, body: lowerExpr(right) });
				// case keyword via ECall(EIdent("case"), [pat, body]) style
				case ECall(callee, args) if (args.length >= 2):
					switch (Tools.expr(callee)) {
						case EIdent("case"):
							arms.push({ pattern: exprToPattern(args[0]), body: lowerExpr(args[1]) });
						default:
							arms.push({ pattern: PatWild, body: lowerExpr(item) });
					}
				default:
					// default arm
					arms.push({ pattern: PatWild, body: lowerExpr(item) });
			}
		}
		return arms;
	}

	function matchArmItems(body:hscript.Expr):Array<hscript.Expr> {
		return switch (Tools.expr(body)) {
			case EBlock(a): a;
			case EArrayDecl(a): a;
			case EParent(e): matchArmItems(e);
			default: [body];
		};
	}

	function exprToPattern(e:hscript.Expr):Pattern {
		return switch (Tools.expr(e)) {
			case EIdent("_"): PatWild;
			case EIdent("true"): PatLit(MC.CBool(true));
			case EIdent("false"): PatLit(MC.CBool(false));
			case EIdent("null"): PatLit(MC.CNull);
			case EIdent(id): PatBind(id);
			case EConst(CInt(i)): PatLit(MC.CInt(i));
			case EConst(CFloat(f)): PatLit(MC.CFloat(f));
			case EConst(CString(s)): PatLit(MC.CString(s));
			case EObject(fields):
				PatObj([for (f in fields) { name: f.name, pat: exprToPattern(f.e) }]);
			case EArrayDecl(values):
				arrayPattern(values);
			case ECheckType(inner, t):
				typedPattern(inner, t);
			case EBinop("|", a, b):
				PatOr(exprToPattern(a), exprToPattern(b));
			case ECall(callee, args):
				switch (Tools.expr(callee)) {
					case EIdent(tag): PatTag(tag, [for (a in args) exprToPattern(a)]);
					default: PatBind("_");
				}
			case EBinop("=>", _, _):
				PatBind("_");
			case EParent(e):
				exprToPattern(e);
			case EIf(cond, then, _):
				PatGuard(exprToPattern(then), lowerExpr(cond));
			case EMeta("as", params, body):
				var n = params != null && params.length > 0 ? identOf(params[0]) : "_";
				PatAs(exprToPattern(body), n);
			case EMeta("rest" | ":rest", params, body):
				var rest = params != null && params.length > 0 ? identOf(params[0]) : null;
				switch (Tools.expr(body)) {
					case EArrayDecl(values):
						arrayPattern(values, rest);
					case EBinop("=>", left, _):
						switch (Tools.expr(left)) {
							case EArrayDecl(values): arrayPattern(values, rest);
							default: PatArr([exprToPattern(left)], rest);
						}
					default:
						PatArr([exprToPattern(body)], rest);
				}
			default:
				PatBind("_");
		};
	}

	function typedPattern(e:hscript.Expr, t:CType):Pattern {
		var typeName = ctypeStr(t);
		return switch (Tools.expr(e)) {
			case EIdent(name): PatTyped(name, typeName);
			case EParent(inner): typedPattern(inner, t);
			default: PatTyped("_", typeName);
		};
	}

	function arrayPattern(values:Array<hscript.Expr>, ?restName:Null<String>):Pattern {
		var rest = restName;
		var end = values.length;
		if (rest == null && end > 0) {
			switch (Tools.expr(values[end - 1])) {
				case EUnop("...", false, spread):
					switch (Tools.expr(spread)) {
						case EIdent(name):
							rest = name;
							end--;
						default:
					}
				default:
			}
		}
		return PatArr([for (i in 0...end) exprToPattern(values[i])], rest);
	}

	function lowerArrayAccess(base:hscript.Expr, idx:hscript.Expr):MExpr {
		// Bar fields (close[1]) and series-style calls (sma(...)[1]) → ELookback.
		// Plain locals (xs[0]) stay EArray — not a bar series / call base.
		if (isLookbackBase(base))
			return MuseNodes.lookback(lowerExpr(base), lowerExpr(idx));
		return MExpr.EArray(lowerExpr(base), lowerExpr(idx));
	}

	/**
	 * Pine-style series bases: bar idents, series-returning builtins, unknown calls,
	 * and field/paren wrappers of those. Local array idents and known dynamic-vector
	 * or string-array builtins stay normal array indexes.
	 * τὰ παρεληλυθότα ἐνδείκνυται τὰ μέλλοντα, πλὴν ὁ δείκτης ὁ κληθεὶς οὐ μένει.
	 */
	function isLookbackBase(e:hscript.Expr):Bool {
		return switch (Tools.expr(e)) {
			case EIdent(id): isBarField(id);
			case ECall(callee, _): isLookbackCall(callee);
			case EField(base, _): isLookbackBase(base);
			case EParent(inner): isLookbackBase(inner);
			default: false;
		};
	}

	function isLookbackCall(callee:hscript.Expr):Bool {
		return switch (Tools.expr(callee)) {
			case EIdent(id):
				var sig = BuiltinSigs.get(id);
				sig == null ? true : sig.ret.match(TSeries);
			default:
				true;
		};
	}

	function ctypeStr(t:CType):String {
		return switch (t) {
			case CTPath(path, _): path.join(".");
			case CTParent(inner): ctypeStr(inner);
			case CTOpt(inner): ctypeStr(inner) + "?";
			case CTNamed(_, inner): ctypeStr(inner);
			case CTFun(args, ret):
				'(${[for (a in args) ctypeStr(a)].join(", ")}) -> ${ctypeStr(ret)}';
			case CTAnon(fields):
				"{" + [for (f in fields) '${f.name}: ${ctypeStr(f.t)}'].join(", ") + "}";
			case CTExpr(e): Std.string(e);
		};
	}

	function containsYield(e:hscript.Expr):Bool {
		var found = false;
		function walk(x:hscript.Expr):Void {
			if (x == null || found) return;
			switch (Tools.expr(x)) {
				case EMeta("yield" | ":yield" | "yieldStar" | "yieldstar" | ":yieldStar", _, _): found = true;
				default: Tools.iter(x, walk);
			}
		}
		walk(e);
		return found;
	}

	function isBarField(id:String):Bool {
		return switch (id) {
			case "open" | "high" | "low" | "close" | "volume" | "time" | "bar_index": true;
			default: false;
		};
	}

	function metaString(params:Array<hscript.Expr>, i:Int, def:String):String {
		if (params == null || params.length <= i) return def;
		return switch (Tools.expr(params[i])) {
			case EConst(CString(s)): s;
			case EIdent(id): id;
			default: def;
		};
	}

	function identOf(e:hscript.Expr):String {
		return switch (Tools.expr(e)) {
			case EIdent(id): id;
			case EConst(CString(s)): s;
			default: "_";
		};
	}

	function numOf(e:MExpr):Float {
		return switch (e) {
			case MExpr.EConst(MC.CInt(i)): i;
			case MExpr.EConst(MC.CFloat(f)): f;
			default: 0;
		};
	}

	function strOf(e:MExpr):String {
		return switch (e) {
			case MExpr.EConst(MC.CString(s)): s;
			case MExpr.EIdent(id): id;
			default: Std.string(e);
		};
	}
}
