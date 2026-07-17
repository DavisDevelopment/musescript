package musescript.compile;

import musescript.ast.MuseProgram;
import musescript.ast.Decl;
import musescript.ast.Stmt;
import musescript.ast.Expr;
import musescript.ast.Const;
import musescript.ast.MuseNodes;

typedef SeriesLowered = { expr:Expr, binds:Array<Stmt> };

/**
 * Materialize nested series expressions into named intermediate bindings so
 * emitters that only accept OHLCV series IDs can still run value-typed nests
 * like `sma(ema(close, 8), 20)`.
 */
class SeriesLowering {
	static var nextId:Int = 0;
	static var spans:Null<musescript.types.AstSpans> = null;

	public static function lower(prog:MuseProgram):MuseProgram {
		nextId = 0;
		spans = prog.spans;
		return {
			decls: [for (d in prog.decls) lowerDecl(d)],
			stmts: lowerStmts(prog.stmts),
			spans: prog.spans
		};
	}

	static function lowerDecl(d:Decl):Decl {
		return switch (d) {
			case StrategyDecl(name, body): StrategyDecl(name, lowerStmts(body));
			case IndicatorDecl(name, args, body):
				var r = lowerExpr(body);
				IndicatorDecl(name, args, wrap(r));
			case FnDecl(name, args, body, kind):
				var r = lowerExpr(body);
				FnDecl(name, args, wrap(r), kind);
			case MacroDecl(name, body): MacroDecl(name, lowerStmts(body));
			case ModuleDecl(name, params, body): ModuleDecl(name, params, lowerStmts(body));
			case TemplateDecl(name, params, ret, body):
				var r = lowerExpr(body);
				TemplateDecl(name, params, ret, wrap(r));
			case StmtTemplateDecl(name, params, body):
				StmtTemplateDecl(name, params, lowerStmts(body));
			case ParamDecl(name, def, opts):
				if (def == null) d;
				else {
					var r = lowerExpr(def);
					ParamDecl(name, wrap(r), opts);
				}
		};
	}

	static function lowerStmts(stmts:Array<Stmt>):Array<Stmt> {
		var out:Array<Stmt> = [];
		for (s in stmts) {
			switch (s) {
				case ExprStmt(e):
					var r = lowerExpr(e);
					out = out.concat(r.binds);
					out.push(ExprStmt(r.expr));
				case Assign(n, e):
					var r = lowerExpr(e);
					out = out.concat(r.binds);
					out.push(Assign(n, r.expr));
				case OnBar(body): out.push(OnBar(lowerStmts(body)));
				case OnPosition(body): out.push(OnPosition(lowerStmts(body)));
				case OnTick(body): out.push(OnTick(lowerStmts(body)));
				case OnEvent(stream, body): out.push(OnEvent(stream, lowerStmts(body)));
				case Block(body): out.push(Block(lowerStmts(body)));
				case When(c, body):
					var r = lowerExpr(c);
					out = out.concat(r.binds);
					out.push(When(r.expr, lowerStmts(body)));
				case Order(kind, args):
					var binds:Array<Stmt> = [];
					var nargs:Array<Expr> = [];
					for (a in args) {
						var r = lowerExpr(a);
						binds = binds.concat(r.binds);
						nargs.push(r.expr);
					}
					out = out.concat(binds);
					out.push(Order(kind, nargs));
				case ForIn(n, it, body):
					var r = lowerExpr(it);
					out = out.concat(r.binds);
					out.push(ForIn(n, r.expr, lowerStmts(body)));
				case Return(e):
					if (e == null) out.push(s);
					else {
						var r = lowerExpr(e);
						out = out.concat(r.binds);
						out.push(Return(r.expr));
					}
				case Yield(e):
					var r = lowerExpr(e);
					out = out.concat(r.binds);
					out.push(Yield(r.expr));
				case YieldStar(e):
					var r = lowerExpr(e);
					out = out.concat(r.binds);
					out.push(YieldStar(r.expr));
				case Use(m, args):
					var binds:Array<Stmt> = [];
					var nargs = [];
					for (a in args) {
						var r = lowerExpr(a.value);
						binds = binds.concat(r.binds);
						nargs.push({ name: a.name, value: r.expr });
					}
					out = out.concat(binds);
					out.push(Use(m, nargs));
				case MatchFor(n, it, arms):
					var r = lowerExpr(it);
					out = out.concat(r.binds);
					out.push(MatchFor(n, r.expr, arms));
			}
		}
		return out;
	}

	static function lowerExpr(e:Expr):SeriesLowered {
		if (e == null) return { expr: e, binds: [] };
		return switch (e) {
			case ECall(EIdent(name), args) if (isSeriesInd(name)):
				var binds:Array<Stmt> = [];
				var nargs:Array<Expr> = [];
				for (i in 0...args.length) {
					var a = args[i];
					if (i == 0) {
						nargs.push(normalizeSeriesArg(a, binds));
					} else {
						var r = lowerExpr(a);
						binds = binds.concat(r.binds);
						nargs.push(r.expr);
					}
				}
				{ expr: keep(e, ECall(EIdent(name), nargs)), binds: binds };
			case EConst(CString(s)) if (isBarName(s)):
				{ expr: keep(e, MuseNodes.barField(s)), binds: [] };
			case EBlock(es):
				var binds:Array<Stmt> = [];
				var out:Array<Expr> = [];
				for (x in es) {
					var r = lowerExpr(x);
					binds = binds.concat(r.binds);
					out.push(r.expr);
				}
				{ expr: keep(e, EBlock(out)), binds: binds };
			case EBinop(op, a, b):
				var ra = lowerExpr(a);
				var rb = lowerExpr(b);
				{ expr: keep(e, EBinop(op, ra.expr, rb.expr)), binds: ra.binds.concat(rb.binds) };
			case EUnop(op, p, x):
				var r = lowerExpr(x);
				{ expr: keep(e, EUnop(op, p, r.expr)), binds: r.binds };
			case ECall(c, args):
				var rc = lowerExpr(c);
				var binds = rc.binds.copy();
				var nargs = [];
				for (a in args) {
					var r = lowerExpr(a);
					binds = binds.concat(r.binds);
					nargs.push(r.expr);
				}
				{ expr: keep(e, ECall(rc.expr, nargs)), binds: binds };
			case EIf(c, a, b):
				var rc = lowerExpr(c);
				var ra = lowerExpr(a);
				var rb = b != null ? lowerExpr(b) : { expr: null, binds: [] };
				{ expr: keep(e, EIf(rc.expr, ra.expr, rb.expr)), binds: rc.binds.concat(ra.binds).concat(rb.binds) };
			case ELookback(s, n):
				var binds:Array<Stmt> = [];
				var series = normalizeSeriesArg(s, binds);
				var rn = lowerExpr(n);
				{ expr: keep(e, ELookback(series, rn.expr)), binds: binds.concat(rn.binds) };
			case EVar(n, init):
				if (init == null) return { expr: e, binds: [] };
				var r = lowerExpr(init);
				{ expr: keep(e, EVar(n, r.expr)), binds: r.binds };
			case EParent(x):
				var r = lowerExpr(x);
				{ expr: keep(e, EParent(r.expr)), binds: r.binds };
			case ETernary(c, a, b):
				var rc = lowerExpr(c);
				var ra = lowerExpr(a);
				var rb = lowerExpr(b);
				{ expr: keep(e, ETernary(rc.expr, ra.expr, rb.expr)), binds: rc.binds.concat(ra.binds).concat(rb.binds) };
			default:
				{ expr: e, binds: [] };
		};
	}

	/** Copy SourcePos from `from` onto a rewritten node when spans are present. */
	static function keep(from:Expr, neu:Expr):Expr {
		if (spans != null && from != null && neu != null) {
			var p = spans.ofExpr(from);
			if (p != null) spans.stampExpr(neu, p);
		}
		return neu;
	}

	static function normalizeSeriesArg(a:Expr, binds:Array<Stmt>):Expr {
		switch (a) {
			case EConst(CString(s)) if (isBarName(s)):
				return MuseNodes.barField(s);
			case ECall(EIdent(name), _) if (isSeriesInd(name)):
				var r = lowerExpr(a);
				for (b in r.binds) binds.push(b);
				var tmp = "__s" + (nextId++);
				binds.push(Assign(tmp, r.expr));
				return MuseNodes.stringExpr(tmp);
			case EBarField(_) | EIdent(_):
				return a;
			default:
				var r = lowerExpr(a);
				for (b in r.binds) binds.push(b);
				return r.expr;
		}
	}

	static function wrap(r:SeriesLowered):Expr {
		if (r.binds.length == 0) return r.expr;
		var es:Array<Expr> = [];
		for (b in r.binds) switch (b) {
			case Assign(n, e): es.push(EBinop("=", EIdent(n), e));
			case ExprStmt(e): es.push(e);
			default:
		}
		es.push(r.expr);
		return EBlock(es);
	}

	static function isSeriesInd(name:String):Bool {
		return switch (name) {
			case "sma" | "ema" | "rsi" | "atr" | "wma" | "rma" | "stdev"
			   | "highest" | "lowest" | "mom" | "roc" | "change" | "pct_change":
				true;
			default: false;
		};
	}

	static function isBarName(s:String):Bool {
		return s == "open" || s == "high" || s == "low" || s == "close" || s == "volume";
	}
}
