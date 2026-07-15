package musescript.checker;

import musescript.ast.MuseProgram;
import musescript.ast.Decl;
import musescript.ast.Stmt;
import musescript.ast.Expr;
import musescript.ast.Const;
import musescript.ast.MatchArm;
import musescript.ast.FnKind;
import musescript.ast.OrderKind;
import musescript.ast.ParamOpts;
import musescript.ast.Pattern;
import musescript.types.MuseType;

/**
 * Static checks: series lookback direction, macro context, match exhaustiveness hints,
 * generator yield usage, plus optional typed pass via TypeChecker.
 */
class MuseChecker {
	var diags:Array<Diagnostic>;
	var inMacro:Bool;
	var inOnBar:Bool;
	var generatorDepth:Int;
	var generatorYieldSeen:Bool;
	var typed:Bool;
	var typeChecker:TypeChecker;

	public function new(?opts:{?typed:Bool}) {
		diags = [];
		inMacro = false;
		inOnBar = false;
		generatorDepth = 0;
		generatorYieldSeen = false;
		typed = opts == null || opts.typed != false;
		typeChecker = new TypeChecker();
	}

	/** Back-compat: string diagnostics. */
	public function check(prog:MuseProgram):Array<String> {
		return Diagnostics.toStrings(checkEx(prog));
	}

	public function checkEx(prog:MuseProgram):Array<Diagnostic> {
		diags = [];
		for (d in prog.decls) checkDecl(d);
		for (s in prog.stmts) checkStmt(s);
		checkCompileCoverage(prog);
		if (typed) {
			for (d in typeChecker.check(prog)) diags.push(d);
		}
		return diags;
	}

	public function typeOf(expr:Expr):MuseType {
		return typeChecker.typeOf(expr);
	}

	public function canAssign(from:MuseType, to:MuseType):Bool {
		return typeChecker.canAssign(from, to);
	}

	/** Hint when constructs force MuseInterp / prevent Strategy WASM. */
	function checkCompileCoverage(prog:MuseProgram):Void {
		try {
			if (new musescript.compile.JsEmitter().emitOnBar(prog) == null)
				warn("JsEmitter: on-bar body not emit-able (will MuseInterp on JS host)");
		} catch (_:Dynamic) {}
		try {
			if (musescript.compile.StrategyWasmBackend.emitWat(prog) == null)
				warn("StrategyWasm: on-bar not in WAT subset (match/generators/indicators/objects → MuseInterp)");
		} catch (_:Dynamic) {}
		for (d in prog.decls) switch (d) {
			case FnDecl(name, _, body, kind) if (kind == Generator || containsYield(body)):
				var lowered = musescript.compile.GeneratorLower.lower({ decls: [d], stmts: [] });
				var stillGen = switch (lowered.decls[0]) {
					case FnDecl(_, _, b, k): k == Generator || containsYield(b);
					default: true;
				};
				if (stillGen)
					warn('generator ${name != null ? name : "<anon>"} not lowered (yield shape unsupported)');
			default:
		}
	}

	static function containsYield(e:Expr):Bool {
		if (e == null) return false;
		return switch (e) {
			case EYield(_) | EYieldStar(_): true;
			case EBlock(es): for (x in es) if (containsYield(x)) return true; false;
			case EIf(_, a, b): containsYield(a) || (b != null && containsYield(b));
			case EWhile(_, a) | EFor(_, _, a) | EFunction(_, a, _, _) | EReturn(a) | EVar(_, a)
				| EParent(a) | EMeta(_, _, a):
				a != null && containsYield(a);
			case EBinop(_, a, b): containsYield(a) || containsYield(b);
			case EUnop(_, _, a) | EArray(a, _) | EField(a, _) | ELookback(a, _): containsYield(a);
			case ECall(a, args):
				if (containsYield(a)) return true;
				for (x in args) if (containsYield(x)) return true;
				false;
			case EArrayDecl(vs): for (v in vs) if (containsYield(v)) return true; false;
			case EObject(fs): for (f in fs) if (containsYield(f.e)) return true; false;
			case ETernary(c, a, b): containsYield(c) || containsYield(a) || containsYield(b);
			case EMatch(_, arms): for (arm in arms) if (containsYield(arm.body)) return true; false;
			default: false;
		};
	}

	function checkDecl(d:Decl):Void {
		switch (d) {
			case MacroDecl(_, body):
				inMacro = true;
				for (s in body) checkStmt(s);
				inMacro = false;
			case StrategyDecl(_, body) | ModuleDecl(_, _, body):
				for (s in body) checkStmt(s);
			case TemplateDecl(_, _, _, body):
				checkExpr(body);
			case FnDecl(_, _, body, kind):
				if (kind == Generator) withGenerator(body, true);
				else checkExpr(body);
			case IndicatorDecl(_, _, body):
				checkExpr(body);
			case ParamDecl(_, def, _):
				if (def != null) checkExpr(def);
		}
	}

	function checkStmt(s:Stmt):Void {
		switch (s) {
			case OnBar(body):
				inOnBar = true;
				for (x in body) checkStmt(x);
				inOnBar = false;
			case OnTick(body) | OnEvent(_, body) | Block(body) | When(_, body):
				for (x in body) checkStmt(x);
			case Use(_, args):
				for (a in args) checkExpr(a.value);
			case ForIn(_, iter, body):
				checkExpr(iter);
				for (x in body) checkStmt(x);
			case MatchFor(_, iter, arms):
				if (inOnBar) warn("match for over live stream inside on bar is discouraged / forbidden for never-ending streams");
				checkExpr(iter);
				checkMatchArms(arms);
			case Order(_, args):
				for (a in args) checkExpr(a);
			case ExprStmt(e):
				checkExpr(e);
			case Assign(_, e):
				checkExpr(e);
			case Return(e):
				if (e != null) checkExpr(e);
			case Yield(e):
				checkYieldSite(e);
			case YieldStar(e):
				checkYieldStarSite(e);
		}
	}

	function checkExpr(e:Expr):Void {
		if (e == null) return;
		switch (e) {
			case EConst(_) | EIdent(_) | EBarField(_):
			case EVar(_, init):
				if (init != null) checkExpr(init);
			case EBlock(exprs):
				for (x in exprs) checkExpr(x);
			case EField(obj, _):
				checkExpr(obj);
			case EBinop(_, left, right):
				checkExpr(left);
				checkExpr(right);
			case EUnop(_, _, operand):
				checkExpr(operand);
			case ECall(EIdent("tune") | EIdent("optimize") | EIdent("sample"), args) if (!inMacro):
				warn("macro builtin used outside @macro context");
				for (a in args) checkExpr(a);
			case ECall(EIdent("tune") | EIdent("optimize") | EIdent("sample") | EIdent("distill") | EIdent("pickBest"), args) if (inOnBar):
				err("macro builtin cannot be used inside on bar");
				for (a in args) checkExpr(a);
			case ECall(callee, args):
				checkExpr(callee);
				for (a in args) checkExpr(a);
			case EIf(cond, eif, eelse):
				checkExpr(cond);
				checkExpr(eif);
				if (eelse != null) checkExpr(eelse);
			case EWhile(cond, body):
				checkExpr(cond);
				checkExpr(body);
			case EFor(_, it, body):
				checkExpr(it);
				checkExpr(body);
			case EFunction(_, body, kind, _):
				if (kind == Generator) withGenerator(body, true);
				else checkExpr(body);
			case EReturn(ret):
				if (ret != null) checkExpr(ret);
			case EArray(base, index):
				checkExpr(base);
				checkExpr(index);
			case EArrayDecl(values):
				for (v in values) checkExpr(v);
			case EObject(fields):
				for (f in fields) checkExpr(f.e);
			case ETernary(cond, eif, eelse):
				checkExpr(cond);
				checkExpr(eif);
				checkExpr(eelse);
			case EParent(inner):
				checkExpr(inner);
			case EMeta(_, args, inner):
				for (a in args) checkExpr(a);
				checkExpr(inner);
			case ELookback(series, n):
				checkLookbackIndex(n);
				checkExpr(series);
				checkExpr(n);
			case EMatch(scrutinee, arms):
				checkExpr(scrutinee);
				checkMatchArms(arms);
			case EYield(value):
				checkYieldSite(value);
			case EYieldStar(value):
				checkYieldStarSite(value);
		}
	}

	function checkMatchArms(arms:Array<MatchArm>):Void {
		var hasWild = false;
		var wildIndex = -1;
		for (i in 0...arms.length) {
			var a = arms[i];
			checkPattern(a.pattern);
			if (a.guard != null) checkExpr(a.guard);
			checkExpr(a.body);
			if (isEmptyMatchBody(a.body)) warn("match arm has empty body");
			if (a.pattern.match(PatWild)) {
				hasWild = true;
				if (wildIndex < 0) wildIndex = i;
			}
		}
		if (!hasWild) warn("match may be non-exhaustive (no wildcard arm)");
		if (wildIndex >= 0 && wildIndex < arms.length - 1)
			warn("match arms after wildcard are unreachable");
	}

	function checkPattern(p:Pattern):Void {
		switch (p) {
			case PatWild | PatLit(_) | PatBind(_) | PatTyped(_, _):
			case PatObj(fields):
				for (f in fields) checkPattern(f.pat);
			case PatArr(items, _):
				for (item in items) checkPattern(item);
			case PatOr(a, b):
				checkPattern(a);
				checkPattern(b);
			case PatGuard(inner, g):
				checkPattern(inner);
				checkExpr(cast g);
			case PatAs(inner, _):
				checkPattern(inner);
			case PatTag(_, args):
				for (arg in args) checkPattern(arg);
		}
	}

	function isEmptyMatchBody(body:Expr):Bool {
		return switch (body) {
			case EBlock(exprs): exprs.length == 0;
			default: false;
		};
	}

	function checkLookbackIndex(n:Expr):Void {
		var neg = negativeLookback(n);
		if (neg != null) err("Negative lookback (future bar) is not allowed: close[" + neg + "]");
	}

	function negativeLookback(n:Expr):Null<Int> {
		return switch (n) {
			case EConst(CInt(i)) if (i < 0): i;
			case EUnop("-", true, EConst(CInt(i))): -i;
			default: null;
		};
	}

	function withGenerator(body:Expr, requireYield:Bool):Void {
		generatorDepth++;
		var prevSeen = generatorYieldSeen;
		generatorYieldSeen = false;
		checkExpr(body);
		if (requireYield && !generatorYieldSeen) warn("generator function has no yield");
		generatorYieldSeen = prevSeen;
		generatorDepth--;
	}

	function checkYieldSite(e:Expr):Void {
		if (generatorDepth == 0) warn("yield outside generator function");
		else generatorYieldSeen = true;
		if (e != null) checkExpr(e);
	}

	function checkYieldStarSite(e:Expr):Void {
		if (generatorDepth == 0) warn("yield* outside generator function");
		else generatorYieldSeen = true;
		if (e != null) checkExpr(e);
	}

	function err(msg:String):Void diags.push(Diagnostics.error(msg));
	function warn(msg:String):Void diags.push(Diagnostics.warning(msg));
}
