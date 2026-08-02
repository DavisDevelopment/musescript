package musescript.compile;

import musescript.ast.MuseProgram;
import musescript.ast.Decl;
import musescript.ast.Stmt;
import musescript.ast.Expr;
import musescript.ast.MatchArm;
import musescript.ast.FnKind;
import musescript.builtins.MuseHost;

/**
 * Lowers class-shaped strategies and indicators into the declaration forms the rest of the
 * compiler already understands.
 *
 *     class MyStrategy extends muse.Strat {
 *       param fast: Window = 10
 *       f = sma(close, fast)
 *       function onBar() { when crossover(f, close): long() }
 *     }
 *
 * becomes exactly the `StrategyDecl` that the equivalent `strategy MyStrategy { ... }` produces,
 * so every downstream consumer — checker, both emitters, the WASM backend, and the evolution
 * substrate — needs no knowledge of classes at all.
 *
 * INHERITANCE IS RESOLVED HERE, STATICALLY. That is the whole point of doing this as a lowering
 * pass rather than at runtime. MuseScript's class runtime is real (field-init ordering, ctor
 * chaining, virtual override, `super`) but it lives entirely in the interpreter: `JsEmitter`
 * throws `EmitUnsupported` on `EThis`/`ESuper`, bridges `ENew` back through `api.invoke`, and
 * `TestClassStructLowering` pins that a class WITH a parent escapes native lowering. A strategy
 * that dispatched methods per bar would therefore run interpreted, which costs roughly 70x
 * against the columnar path. Flattening keeps the whole thing on the fast path while still
 * giving real override semantics, because a strategy is instantiated exactly once and never
 * referred to polymorphically — the two things dynamic dispatch would buy are things a strategy
 * cannot use.
 *
 * What flattening means concretely, base-first along the chain:
 *  - `param` declarations are already hoisted to program level by the parser; nothing to do.
 *  - Fields become prelude assignments, which is precisely what a field is in the strategy
 *    surface: `m = macd(close)` re-evaluated each bar. A derived class redefining a field
 *    replaces the base's initializer.
 *  - `onBar`/`onPosition`/`onTick` become their lifecycle hooks. A derived override replaces the
 *    base's; `super.onBar()` inside the override splices the base's body at that point.
 *  - Every other method is inlined at its call sites. Inlining rather than emitting a top-level
 *    function is what keeps fields and params in scope, since those live in the strategy body's
 *    per-bar scope and a separate function body could not see them.
 *
 * A class whose ancestry does not reach `muse.Strat` or `muse.Indicator` is left completely
 * alone and continues to use the existing class runtime.
 */
class ClassStrategyLower {
	/** Roots that give a class meaning as a declaration rather than as a value. */
	public static inline var STRAT_ROOT = "muse.Strat";
	public static inline var INDICATOR_ROOT = "muse.Indicator";

	/** The method name a `muse.Indicator` subclass implements. */
	static inline var INDICATOR_ENTRY = "compute";

	static inline var MAX_INLINE_DEPTH = 32;

	public static function isBuiltinRoot(name:Null<String>):Bool {
		return name == STRAT_ROOT || name == INDICATOR_ROOT;
	}

	public static function expand(prog:MuseProgram):MuseProgram {
		var classes = new Map<String, ClassInfo>();
		for (d in prog.decls) switch (d) {
			case ClassDecl(name, parent, fields, methods, ctor):
				classes.set(name, { name: name, parent: parent, fields: fields, methods: methods, ctor: ctor });
			default:
		}
		if (!Lambda.exists(classes, c -> rootOf(c, classes) != null)) return prog;

		// Bases that other Strat/Indicator classes extend are flattened into those
		// leaves — emitting them as their own StrategyDecl would merge orphan
		// onPosition/onBar hooks into every later strategy in the same file
		// (JsEmitter concatenates all StrategyDecls; the flagship harness stitches
		// FlagshipRisk ahead of FlagshipV2 / probe strategies).
		var usedAsParent = new Map<String, Bool>();
		for (c in classes) {
			if (c.parent != null && !isBuiltinRoot(c.parent) && classes.exists(c.parent))
				usedAsParent.set(c.parent, true);
		}

		var out:Array<Decl> = [];
		for (d in prog.decls) switch (d) {
			case ClassDecl(name, _, _, _, _):
				var info = classes.get(name);
				var root = rootOf(info, classes);
				if (root == null) out.push(d); // an ordinary class — untouched
				else if (usedAsParent.exists(name)) {
					// Non-leaf Strat/Indicator: consumed by subclass lowering only.
				} else if (root == STRAT_ROOT) out.push(lowerStrategy(info, classes));
				else out.push(lowerIndicator(info, classes));
			default:
				out.push(d);
		}
		return { decls: out, stmts: prog.stmts, spans: prog.spans };
	}

	// ---------- ancestry ----------

	/** The builtin root this class descends from, or null if it is an ordinary class. */
	static function rootOf(c:Null<ClassInfo>, classes:Map<String, ClassInfo>):Null<String> {
		var seen = new Map<String, Bool>();
		var cur = c;
		while (cur != null) {
			if (cur.parent == null) return null;
			if (isBuiltinRoot(cur.parent)) return cur.parent;
			if (seen.exists(cur.name))
				throw 'class ${c.name}: cyclic inheritance through ${cur.name}';
			seen.set(cur.name, true);
			var next = classes.get(cur.parent);
			if (next == null)
				throw 'class ${cur.name} extends unknown class ${cur.parent}';
			cur = next;
		}
		return null;
	}

	/** The chain base-first, excluding the builtin root itself. */
	static function chainOf(c:ClassInfo, classes:Map<String, ClassInfo>):Array<ClassInfo> {
		var chain = [c];
		var cur = c;
		while (cur.parent != null && !isBuiltinRoot(cur.parent)) {
			cur = classes.get(cur.parent);
			chain.unshift(cur);
		}
		return chain;
	}

	// ---------- strategy ----------

	static function lowerStrategy(c:ClassInfo, classes:Map<String, ClassInfo>):Decl {
		var chain = chainOf(c, classes);
		reject(chain, c.name);

		// Fields base-first; a derived redefinition replaces the base's initializer in place, so
		// declaration order still reads from the base down (an initializer may reference a field
		// declared above it, exactly as in a strategy prelude).
		var fieldOrder:Array<String> = [];
		var fieldInit = new Map<String, Null<Expr>>();
		for (cls in chain) for (f in cls.fields) {
			if (!fieldInit.exists(f.name)) fieldOrder.push(f.name);
			fieldInit.set(f.name, f.def);
		}

		// Methods base-first so a derived definition overwrites; `owners` remembers where each
		// version came from so `super.m()` can find the one it is overriding.
		var methods = new Map<String, MethodInfo>();
		var supers = new Map<String, MethodInfo>();
		for (cls in chain) for (m in cls.methods) {
			var prev = methods.get(m.name);
			if (prev != null) supers.set(m.name, prev);
			methods.set(m.name, { name: m.name, args: m.args, body: m.body });
		}

		var body:Array<Stmt> = [];
		for (name in fieldOrder) {
			var init = fieldInit.get(name);
			if (init == null)
				throw 'class ${c.name}: field `$name` needs an initializer '
					+ '(a strategy field is a per-bar binding, so there is no constructor to set it later)';
			body.push(Assign(name, inlineExpr(init, methods, supers, 0, c.name)));
		}

		var sawHook = false;
		for (hook in ["onBar", "onPosition", "onTick"]) {
			var m = methods.get(hook);
			if (m == null) continue;
			if (m.args.length != 0)
				throw 'class ${c.name}: `$hook` takes no arguments';
			sawHook = true;
			var hookBody = bodyToStmts(inlineExpr(m.body, methods, supers, 0, c.name));
			body.push(switch (hook) {
				case "onBar": OnBar(hookBody);
				case "onPosition": OnPosition(hookBody);
				default: OnTick(hookBody);
			});
		}
		if (!sawHook)
			throw 'class ${c.name} extends $STRAT_ROOT but declares no onBar/onPosition/onTick';

		return StrategyDecl(c.name, body);
	}

	// ---------- indicator ----------

	static function lowerIndicator(c:ClassInfo, classes:Map<String, ClassInfo>):Decl {
		var chain = chainOf(c, classes);
		reject(chain, c.name);
		if (Lambda.exists(chain, cls -> cls.fields.length > 0))
			throw 'class ${c.name}: an indicator has no per-bar state, so it cannot declare fields';

		var methods = new Map<String, MethodInfo>();
		var supers = new Map<String, MethodInfo>();
		for (cls in chain) for (m in cls.methods) {
			var prev = methods.get(m.name);
			if (prev != null) supers.set(m.name, prev);
			methods.set(m.name, { name: m.name, args: m.args, body: m.body });
		}
		var entry = methods.get(INDICATOR_ENTRY);
		if (entry == null)
			throw 'class ${c.name} extends $INDICATOR_ROOT but declares no `$INDICATOR_ENTRY` method';

		var body = inlineExpr(entry.body, methods, supers, 0, c.name);
		return IndicatorDecl(c.name, entry.args, unwrapReturn(body));
	}

	/** An indicator body is an expression; a lone `return e` is the natural way to write it. */
	static function unwrapReturn(e:Expr):Expr {
		return switch (e) {
			case EBlock([one]): unwrapReturn(one);
			case EReturn(v) if (v != null): v;
			default: e;
		};
	}

	static function reject(chain:Array<ClassInfo>, name:String):Void {
		for (cls in chain) {
			if (cls.ctor != null)
				throw 'class $name: `new` is not supported on a declaration class '
					+ '(${cls.name} declares one) — a strategy is constructed by the harness, '
					+ 'and its fields are per-bar bindings';
			for (m in cls.methods) if (m.isStatic)
				throw 'class $name: static methods are not supported on a declaration class '
					+ '(${cls.name}.${m.name})';
		}
	}

	// ---------- method inlining ----------

	/**
	 * Replaces calls to the class's own methods with their bodies, substituting arguments. This
	 * is what keeps fields and params visible: the body lands textually where the call was, in
	 * the strategy's own per-bar scope, rather than inside a separate function's.
	 */
	static function inlineExpr(e:Expr, methods:Map<String, MethodInfo>, supers:Map<String, MethodInfo>,
			depth:Int, owner:String):Expr {
		if (e == null) return e;
		if (depth > MAX_INLINE_DEPTH)
			throw 'class $owner: method inlining exceeded depth $MAX_INLINE_DEPTH (recursive method?)';
		return switch (e) {
			// `super.m(args)` — the version this one overrides.
			case ECall(ESuper(m, _), args) if (m != null):
				callInto(supers.get(m), args, methods, supers, depth, owner, 'super.$m');
			case ESuper(m, args) if (m != null):
				callInto(supers.get(m), args, methods, supers, depth, owner, 'super.$m');
			// Host sugar: `this.orders.long()` / `this.math.abs(x)` — same rewrite
			// MuseHostLower applies to `muse.<ns>.*`.
			case ECall(EField(EField(EThis, ns), method), args)
				if (MuseHost.resolveObjectReceiver(ns) != null || MuseHost.resolveFlat(ns, method) != null):
				var recv = MuseHost.resolveObjectReceiver(ns);
				var loweredArgs = [for (a in args) inlineExpr(a, methods, supers, depth, owner)];
				if (recv != null)
					ECall(EField(EIdent(recv), method), loweredArgs);
				else
					ECall(EIdent(MuseHost.resolveFlat(ns, method)), loweredArgs);
			// `this.m(args)` and bare `m(args)` — the flattened winner.
			case ECall(EField(EThis, m), args) if (methods.exists(m)):
				callInto(methods.get(m), args, methods, supers, depth, owner, 'this.$m');
			case ECall(EIdent(m), args) if (methods.exists(m)):
				callInto(methods.get(m), args, methods, supers, depth, owner, m);
			// `this.field` is just the field, which is a plain local after lowering.
			case EField(EThis, f): EIdent(f);
			case EThis:
				throw 'class $owner: bare `this` has no value in a declaration class';

			case EBlock(es): EBlock([for (x in es) inlineExpr(x, methods, supers, depth, owner)]);
			case EField(o, f): EField(inlineExpr(o, methods, supers, depth, owner), f);
			case EBinop(op, a, b):
				EBinop(op, inlineExpr(a, methods, supers, depth, owner), inlineExpr(b, methods, supers, depth, owner));
			case EUnop(op, pre, x): EUnop(op, pre, inlineExpr(x, methods, supers, depth, owner));
			case ECall(f, args):
				ECall(inlineExpr(f, methods, supers, depth, owner),
					[for (a in args) inlineExpr(a, methods, supers, depth, owner)]);
			case EIf(c, t, f):
				EIf(inlineExpr(c, methods, supers, depth, owner), inlineExpr(t, methods, supers, depth, owner),
					f == null ? null : inlineExpr(f, methods, supers, depth, owner));
			case ETernary(c, t, f):
				ETernary(inlineExpr(c, methods, supers, depth, owner), inlineExpr(t, methods, supers, depth, owner),
					inlineExpr(f, methods, supers, depth, owner));
			case EWhile(c, b):
				EWhile(inlineExpr(c, methods, supers, depth, owner), inlineExpr(b, methods, supers, depth, owner));
			case EFor(n, it, b):
				EFor(n, inlineExpr(it, methods, supers, depth, owner), inlineExpr(b, methods, supers, depth, owner));
			case EReturn(v): EReturn(v == null ? null : inlineExpr(v, methods, supers, depth, owner));
			case EArray(a, idx):
				EArray(inlineExpr(a, methods, supers, depth, owner), inlineExpr(idx, methods, supers, depth, owner));
			case EArrayDecl(vs): EArrayDecl([for (v in vs) inlineExpr(v, methods, supers, depth, owner)]);
			case EObject(fs):
				EObject([for (f in fs) { name: f.name, e: inlineExpr(f.e, methods, supers, depth, owner) }]);
			case EParent(x): EParent(inlineExpr(x, methods, supers, depth, owner));
			case EMeta(n, args, x):
				EMeta(n, args, inlineExpr(x, methods, supers, depth, owner));
			case ELookback(s, n):
				ELookback(inlineExpr(s, methods, supers, depth, owner), inlineExpr(n, methods, supers, depth, owner));
			case EVar(n, init): EVar(n, init == null ? null : inlineExpr(init, methods, supers, depth, owner));
			case EFunction(args, b, kind, name):
				EFunction(args, inlineExpr(b, methods, supers, depth, owner), kind, name);
			case EMatch(s, arms):
				EMatch(inlineExpr(s, methods, supers, depth, owner), [
					for (a in arms) ({
						pattern: a.pattern,
						guard: a.guard == null ? null : inlineExpr(a.guard, methods, supers, depth, owner),
						body: inlineExpr(a.body, methods, supers, depth, owner)
					} : MatchArm)
				]);
			case EConst(_) | EIdent(_) | EBarField(_) | ENew(_, _) | ESuper(_, _)
				| EYield(_) | EYieldStar(_): e;
		};
	}

	static function callInto(m:Null<MethodInfo>, args:Array<Expr>, methods:Map<String, MethodInfo>,
			supers:Map<String, MethodInfo>, depth:Int, owner:String, what:String):Expr {
		if (m == null) throw 'class $owner: no method to call for `$what`';
		if (m.args.length != args.length)
			throw 'class $owner: `$what` expects ${m.args.length} argument(s), got ${args.length}';
		var env = new Map<String, Expr>();
		for (k in 0...m.args.length)
			env.set(m.args[k], inlineExpr(args[k], methods, supers, depth + 1, owner));
		var bound = env.keys().hasNext() ? substitute(m.body, env) : m.body;
		return unwrapReturn(inlineExpr(bound, methods, supers, depth + 1, owner));
	}

	/** Argument substitution over a method body. Mirrors `TemplateExpand.substitute`. */
	static function substitute(e:Expr, env:Map<String, Expr>):Expr {
		if (e == null) return e;
		return switch (e) {
			case EIdent(n) if (env.exists(n)): env.get(n);
			case EBlock(es): EBlock([for (x in es) substitute(x, env)]);
			case EField(o, f): EField(substitute(o, env), f);
			case EBinop(op, a, b): EBinop(op, substitute(a, env), substitute(b, env));
			case EUnop(op, pre, x): EUnop(op, pre, substitute(x, env));
			case ECall(f, args): ECall(substitute(f, env), [for (a in args) substitute(a, env)]);
			case EIf(c, t, f): EIf(substitute(c, env), substitute(t, env), f == null ? null : substitute(f, env));
			case ETernary(c, t, f): ETernary(substitute(c, env), substitute(t, env), substitute(f, env));
			case EWhile(c, b): EWhile(substitute(c, env), substitute(b, env));
			case EFor(n, it, b): EFor(n, substitute(it, env), substitute(b, env));
			case EReturn(v): EReturn(v == null ? null : substitute(v, env));
			case EArray(a, i): EArray(substitute(a, env), substitute(i, env));
			case EArrayDecl(vs): EArrayDecl([for (v in vs) substitute(v, env)]);
			case EObject(fs): EObject([for (f in fs) { name: f.name, e: substitute(f.e, env) }]);
			case EParent(x): EParent(substitute(x, env));
			case EMeta(n, a, x): EMeta(n, a, substitute(x, env));
			case ELookback(s, n): ELookback(substitute(s, env), substitute(n, env));
			case EVar(n, init): EVar(n, init == null ? null : substitute(init, env));
			case EFunction(args, b, kind, name): EFunction(args, substitute(b, env), kind, name);
			case EMatch(s, arms):
				EMatch(substitute(s, env), [
					for (a in arms) ({
						pattern: a.pattern,
						guard: a.guard == null ? null : substitute(a.guard, env),
						body: substitute(a.body, env)
					} : MatchArm)
				]);
			case EConst(_) | EIdent(_) | EBarField(_) | ENew(_, _) | EThis
				| ESuper(_, _) | EYield(_) | EYieldStar(_): e;
		};
	}

	/**
	 * A method body is an `EBlock` of expressions (the parser converts each statement with
	 * `stmtAsExpr` on the way in). `ExprStmt` is the faithful inverse: the strategy surface
	 * already represents `if`/`when` and order calls as expression statements.
	 */
	static function bodyToStmts(e:Expr):Array<Stmt> {
		return switch (e) {
			case EBlock(es): [for (x in es) ExprStmt(x)];
			default: [ExprStmt(e)];
		};
	}
}

private typedef ClassInfo = {
	name:String,
	parent:Null<String>,
	fields:Array<{name:String, def:Null<Expr>}>,
	methods:Array<{name:String, args:Array<String>, body:Expr, isStatic:Bool}>,
	ctor:Null<{args:Array<String>, body:Expr}>
};

private typedef MethodInfo = { name:String, args:Array<String>, body:Expr };
