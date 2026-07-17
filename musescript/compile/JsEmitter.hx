package musescript.compile;

import musescript.ast.Expr;
import musescript.ast.Stmt;
import musescript.ast.Const;
import musescript.ast.MuseProgram;
import musescript.ast.Decl;
import musescript.ast.OrderKind;
import musescript.ast.FnKind;
import musescript.ast.Pattern;
import musescript.ast.MatchArm;
import musescript.types.BuiltinSigs;

/**
 * Emit MuseAST on-bar / on-tick bodies as JS function sources.
 * Runtime bindings come from `api` (harness façade in JsBackend.makeApi).
 *
 * ## Supported (emitted to JS)
 * - Top-level `@on(bar)` / `@on(tick)` / `@on(stream)` bodies (siblings; tick/event bind via host)
 * - Statements: ExprStmt, Assign, Block, Return, Order (long/short/flat/close)
 * - Statements: ForIn over arrays / scalars (via api.iter)
 * - Expressions: literals, ident, bar fields (open/high/low/close/volume/time/bar_index)
 * - var / assignment (=) to locals, blocks, if/else, while, ternary, parens
 * - binops / unops, calls to builtins and locals (api.invoke), api.apply for callees
 * - array literals (EArrayDecl), object literals (EObject), field access (EField)
 * - series lookback (close[1] / sma(...)[1] → ELookback), EArray index on runtime arrays
 * - match → nested if/bindings; MatchFor → for + match
 * - @indicator decls as stateful api.set bindings (via emitIndicators)
 * - Normal (non-generator) local function expressions; EMeta unwraps to inner expr
 *
 * ## Unsupported (throws EmitUnsupported → null → MuseInterp fallback)
 * - OnBar / OnTick / OnEvent nested inside an on-bar, on-tick, or on-event body
 * - yield / yield* (expr or stmt)
 * - Generator functions (function*)
 * - Async / event-stream constructs not modeled in api
 * στιγμὴ φεύγει· μένει δὲ ὁ κώδιξ.
 */
class JsEmitter {
	var tmpId:Int = 0;
	/**
	 * Names PreludeVars proved safe to compile as real JS `let` locals inside
	 * the emitted on-bar function, instead of api.get/api.set Map traffic.
	 * ONLY set while emitting the on-bar body (see emitOnBar) — indicator /
	 * tick / event bodies are separate JS function scopes that never see
	 * these `let` declarations, so they must never consult this set.
	 */
	var hoisted:Map<String, Bool> = new Map();

	public function new() {}

	/**
	 * Returns JS source of: function(api) { ... } for collected `@on(bar)` bodies.
	 * Falls back to null if the on-bar body has constructs we can't emit yet.
	 * Top-level `@on(tick)` / `@on(event)` siblings are ignored here (see emitOnTick / emitOnEvent).
	 * ὁ καιρὸς τῆς ῥάβδου· ὁ δὲ κρότος ἄνω μένει.
	 */
	public function emitOnBar(prog:MuseProgram, ?hoistedNames:Map<String, Bool>):Null<String> {
		var hooks = collectStrategyHooks(prog);
		if (hooks.onBar.length == 0 && hooks.onPosition.length == 0 && collectIndicators(prog).length == 0)
			return null;
		hoisted = hoistedNames != null ? hoistedNames : new Map();
		var result:Null<String> = null;
		try {
			tmpId = 0;
			var setup = emitIndicatorSetup(prog);
			var parts:Array<String> = [];
			if (hooks.prelude.length > 0)
				parts.push([for (s in hooks.prelude) emitStmt(s)].join("\n"));
			if (hooks.onBar.length > 0)
				parts.push([for (s in hooks.onBar) emitStmt(s)].join("\n"));
			if (hooks.onPosition.length > 0) {
				var posBody = [for (s in hooks.onPosition) emitStmt(s)].join("\n");
				parts.push('if(api.position()!==0){\n' + posBody + '\n}');
			}
			var body = parts.join("\n");
			// Declared INSIDE the function body: whether a `let` "persists"
			// across separate calls of this same function is unobservable
			// here, since every hoisted name is a prelude local re-assigned
			// unconditionally before any read, every single bar (see
			// PreludeVars doc comment) — no enclosing-scope wrapper needed.
			var letDecl = "";
			var names = [for (n in hoisted.keys()) n];
			if (names.length > 0) letDecl = "let " + [for (n in names) safe(n)].join(",") + ";\n";
			result = 'function(api){\n' + letDecl + setup + body + '\n}';
		} catch (_:EmitUnsupported) {
			result = null;
		}
		hoisted = new Map(); // never leak into a later emitIndicators/emitOnTick/emitOnEvent call
		return result;
	}

	/**
	 * Returns JS source of: function(api) { ... } for collected `@on(tick)` bodies.
	 * Host must bind price/size/time (and optional bid/ask/side/symbol) before call.
	 * Nested OnTick inside another handler still throws EmitUnsupported.
	 * τοῦ ἀγοραίου κρότου φωνὴ ἐν τῷ λόγῳ.
	 */
	public function emitOnTick(prog:MuseProgram):Null<String> {
		var stmts = collectOnTick(prog);
		if (stmts.length == 0) return null;
		try {
			tmpId = 0;
			var body = [for (s in stmts) emitStmt(s)].join("\n");
			return 'function(api){\n' + body + '\n}';
		} catch (_:EmitUnsupported) {
			return null;
		}
	}

	/**
	 * Returns JS source of: function(api) { ... } for collected top-level `@on(stream)` bodies.
	 * Host sets `__stream` and binds event fields (see JsBackend.bindEvent) before call.
	 * Stream filter mirrors MuseInterp.dispatchEvents (handler.stream == stream || handler.stream == "event").
	 * Nested OnEvent inside another handler still throws EmitUnsupported.
	 * σκιὰ γεγονότος ἐν ῥήματι γίνεται.
	 */
	public function emitOnEvent(prog:MuseProgram):Null<String> {
		var groups = collectOnEvent(prog);
		if (groups.length == 0) return null;
		try {
			tmpId = 0;
			var parts:Array<String> = [];
			for (g in groups) {
				var body = [for (s in g.body) emitStmt(s)].join("\n");
				if (g.stream == "event") {
					parts.push(body);
				} else {
					var sn = escape(g.stream);
					parts.push('if(api.get("__stream")==="${sn}"){\n' + body + '\n}');
				}
			}
			return 'function(api){\n' + parts.join("\n") + '\n}';
		} catch (_:EmitUnsupported) {
			return null;
		}
	}

	/** Indicator name → JS function(api, ...args) { ... } with real statement returns. ὀνόματα ἔργα. */
	public function emitIndicators(prog:MuseProgram):Array<{name:String, args:Array<String>, src:String}> {
		var out:Array<{name:String, args:Array<String>, src:String}> = [];
		try {
			for (ind in collectIndicators(prog)) {
				tmpId = 0;
				var params = [for (a in ind.args) safe(a)].join(", ");
				var src = 'function(api' + (params.length > 0 ? ", " + params : "") + '){\n'
					+ [for (a in ind.args) 'api.set("${safe(a)}", ${safe(a)});'].join("\n")
					+ "\n" + emitFnBody(ind.body) + "\n}";
				out.push({ name: ind.name, args: ind.args, src: src });
			}
		} catch (_:EmitUnsupported) {
			return [];
		}
		return out;
	}

	function emitIndicatorSetup(prog:MuseProgram):String {
		// Indicators are registered once by JsBackend; on-bar emit stays focused on strategy.
		return "";
	}

	function collectIndicators(prog:MuseProgram):Array<{name:String, args:Array<String>, body:Expr}> {
		var out = [];
		for (d in prog.decls) switch (d) {
			case IndicatorDecl(name, args, body):
				out.push({ name: name, args: args, body: body });
			default:
		}
		return out;
	}

	function collectStrategyHooks(prog:MuseProgram):{prelude:Array<Stmt>, onBar:Array<Stmt>, onPosition:Array<Stmt>} {
		var prelude:Array<Stmt> = [];
		var onBarBody:Array<Stmt> = [];
		var onPositionBody:Array<Stmt> = [];
		function walkStmts(ss:Array<Stmt>) {
			for (s in ss) switch (s) {
				case OnBar(body): onBarBody = onBarBody.concat(body);
				case OnPosition(body): onPositionBody = onPositionBody.concat(body);
				case Block(body): walkStmts(body);
				default:
			}
		}
		for (d in prog.decls) switch (d) {
			case StrategyDecl(_, body):
				for (s in body) switch (s) {
					case Assign(_, _): prelude.push(s);
					case OnBar(onBody): onBarBody = onBarBody.concat(onBody);
					case OnPosition(onBody): onPositionBody = onPositionBody.concat(onBody);
					case Block(block):
						for (nested in block) switch (nested) {
							case Assign(_, _): prelude.push(nested);
							case OnBar(onBody): onBarBody = onBarBody.concat(onBody);
							case OnPosition(onBody): onPositionBody = onPositionBody.concat(onBody);
							default:
						}
					default:
				}
			default:
		}
		walkStmts(prog.stmts);
		return { prelude: prelude, onBar: onBarBody, onPosition: onPositionBody };
	}

	function collectOnBar(prog:MuseProgram):Array<Stmt> {
		var hooks = collectStrategyHooks(prog);
		return hooks.prelude.concat(hooks.onBar);
	}

	/** Collect top-level `@on(tick)` bodies only (not nested). χρόνος ἄτομος. */
	function collectOnTick(prog:MuseProgram):Array<Stmt> {
		var out:Array<Stmt> = [];
		function walkStmts(ss:Array<Stmt>) {
			for (s in ss) switch (s) {
				case OnTick(body): out = out.concat(body);
				case Block(body): walkStmts(body);
				default:
			}
		}
		for (d in prog.decls) switch (d) {
			case StrategyDecl(_, body): walkStmts(body);
			default:
		}
		walkStmts(prog.stmts);
		return out;
	}

	/** Collect top-level `@on(stream)` handlers only (not nested). ῥεῦμα καὶ ὄνομα. */
	function collectOnEvent(prog:MuseProgram):Array<{stream:String, body:Array<Stmt>}> {
		var out:Array<{stream:String, body:Array<Stmt>}> = [];
		function walkStmts(ss:Array<Stmt>) {
			for (s in ss) switch (s) {
				case OnEvent(stream, body): out.push({ stream: stream, body: body });
				case Block(body): walkStmts(body);
				default:
			}
		}
		for (d in prog.decls) switch (d) {
			case StrategyDecl(_, body): walkStmts(body);
			default:
		}
		walkStmts(prog.stmts);
		return out;
	}

	function fresh(prefix:String = "t"):String {
		return "__" + prefix + (tmpId++);
	}

	/**
	 * Emit a function/indicator body so `return` exits the outer function
	 * (not a nested IIFE).
	 * τέλος ἐν ἀρχῇ κεῖται.
	 */
	function emitFnBody(e:Expr):String {
		return switch (e) {
			case EBlock(es):
				if (es.length == 0) return "return null;";
				var parts:Array<String> = [];
				for (i in 0...es.length) {
					var last = i == es.length - 1;
					parts.push(last ? emitTail(es[i]) : emitExprAsStmt(es[i]));
				}
				parts.join("\n");
			case EMeta(_, _, x): emitFnBody(x);
			default:
				emitTail(e);
		};
	}

	/** Last expression in a function: return its value (or honor EReturn). ὕστατον ἔπος. */
	function emitTail(e:Expr):String {
		return switch (e) {
			case EReturn(v):
				v != null ? 'return ${emitExpr(v)};' : "return;";
			case EIf(c, a, b):
				b != null
					? 'if(${emitExpr(c)}){\n${emitFnBody(a)}\n}else{\n${emitFnBody(b)}\n}'
					: 'if(${emitExpr(c)}){\n${emitFnBody(a)}\n}';
			case EBlock(_): emitFnBody(e);
			case EMeta(_, _, x): emitTail(x);
			default:
				'return ${emitExpr(e)};';
		};
	}

	/** Expression used as a statement (on-bar / on-tick or mid-body). λόγος ἔργον. */
	function emitExprAsStmt(e:Expr):String {
		return switch (e) {
			case EReturn(v):
				v != null ? 'return ${emitExpr(v)};' : "return;";
			case EIf(c, a, b):
				b != null
					? 'if(${emitExpr(c)}){\n${emitExprAsStmt(a)}\n}else{\n${emitExprAsStmt(b)}\n}'
					: 'if(${emitExpr(c)}){\n${emitExprAsStmt(a)}\n}';
			case EWhile(c, body):
				'while(${emitExpr(c)}){\n${emitExprAsStmt(body)}\n}';
			case EBlock(es):
				'{\n' + [for (x in es) emitExprAsStmt(x)].join("\n") + "\n}";
			case EVar(n, init):
				init != null
					? 'api.set("${safe(n)}", ${emitExpr(init)});'
					: 'api.set("${safe(n)}", null);';
			case EBinop("=", EIdent(n), v):
				hoisted.exists(n)
					? '${safe(n)} = ${emitExpr(v)};'
					: 'api.set("${safe(n)}", ${emitExpr(v)});';
			case EBinop("=", EField(obj, f), v):
				'${emitExpr(obj)}.${safe(f)} = ${emitExpr(v)};';
			case EMeta(_, _, x): emitExprAsStmt(x);
			default:
				emitExpr(e) + ";";
		};
	}

	function emitStmt(s:Stmt):String {
		return switch (s) {
			case ExprStmt(e): emitExprAsStmt(e);
			case Assign(name, e):
				hoisted.exists(name)
					? '${safe(name)} = ${emitExpr(e)};'
					: 'api.set("${safe(name)}", ${emitExpr(e)});';
			case Block(ss): '{\n' + [for (x in ss) emitStmt(x)].join("\n") + '\n}';
			case Return(e): e != null ? 'return ${emitExpr(e)};' : 'return;';
			case Order(kind, args):
				var a = args.length > 0 ? emitExpr(args[0]) : "undefined";
				switch (kind) {
					case Long: 'api.long($a);';
					case Short: 'api.short($a);';
					case Flat | Close: 'api.flat();';
				}
			case ForIn(name, it, body):
				var loopBody = [for (x in body) emitStmt(x)].join("\n");
				'for (var __v of api.iter(${emitExpr(it)})) {\n'
					+ 'api.set("${safe(name)}", __v);\n'
					+ loopBody + '\n}';
			case MatchFor(name, it, arms):
				'for (var __v of api.iter(${emitExpr(it)})) {\n'
					+ 'api.set("${safe(name)}", __v);\n'
					+ emitMatch(EIdent(name), arms) + ';\n' + '}';
			case When(cond, body):
				'if(${emitExpr(cond)}){\n' + [for (x in body) emitStmt(x)].join("\n") + "\n}";
			case Use(_, _):
				throw new EmitUnsupported();
			// Nested handlers only — top-level OnBar/OnTick/OnEvent are collected, not emitted via emitStmt.
			case OnBar(_) | OnPosition(_) | OnTick(_) | OnEvent(_, _) | Yield(_) | YieldStar(_):
				throw new EmitUnsupported();
		};
	}

	function emitExpr(e:Expr):String {
		return switch (e) {
			case EConst(c):
				switch (c) {
					case CInt(i): Std.string(i);
					case CFloat(f): Std.string(f);
					case CString(s): '"' + escape(s) + '"';
					case CBool(b): b ? "true" : "false";
					case CNull: "null";
				}
			case EIdent(n): hoisted.exists(n) ? safe(n) : 'api.get("${safe(n)}")';
			case EBarField(n): 'api.bar("${safe(n)}")';
			case EVar(n, init):
				init != null
					? '(api.set("${safe(n)}", ${emitExpr(init)}), api.get("${safe(n)}"))'
					: '(api.set("${safe(n)}", null), null)';
			case EBlock(es):
				if (es.length == 0) return "null";
				'(function(){\n' + [for (i in 0...es.length-1) emitExpr(es[i]) + ";"].join("\n")
					+ '\nreturn ${emitExpr(es[es.length-1])};\n})()';
			case EField(obj, f): '${emitExpr(obj)}.${safe(f)}';
			case EBinop(op, a, b):
				if (op == "=") {
					return switch (a) {
						case EIdent(n):
						hoisted.exists(n)
							? '(${safe(n)} = ${emitExpr(b)})'
							: '(api.set("${safe(n)}", ${emitExpr(b)}), api.get("${safe(n)}"))';
						case EField(obj, f):
							'(${emitExpr(obj)}.${safe(f)} = ${emitExpr(b)}, ${emitExpr(obj)}.${safe(f)})';
						default: throw new EmitUnsupported();
					};
				}
				'(${emitExpr(a)} $op ${emitExpr(b)})';
			case EUnop(op, prefix, x):
				prefix ? '($op${emitExpr(x)})' : '(${emitExpr(x)}$op)';
			case ECall(EIdent(name), args):
				// Arity-specialized invokeN (≤4 args) skips the args-array
				// allocation and dispatches via JsBackend's per-arity fast
				// tables; resolution order (locals, then builtins) is identical.
				var emitted = [for (i in 0...args.length) emitCallArg(name, i, args[i])];
				args.length <= 4
					? 'api.invoke${args.length}("${safe(name)}"${emitted.length > 0 ? ", " + emitted.join(",") : ""})'
					: 'api.invoke("${safe(name)}", [${emitted.join(",")}])';
			case ECall(callee, args):
				'api.apply(${emitExpr(callee)}, [${[for (a in args) emitExpr(a)].join(",")}])';
			case EIf(c, a, b):
				b != null
					? '(${emitExpr(c)} ? ${emitExpr(a)} : ${emitExpr(b)})'
					: '(${emitExpr(c)} ? ${emitExpr(a)} : null)';
			case EWhile(c, body):
				'(function(){ while(${emitExpr(c)}){ ${emitExpr(body)}; } return null; })()';
			case EFor(name, it, body):
				'(function(){\n'
					+ 'var __r=null;\n'
					+ 'for (var __v of api.iter(${emitExpr(it)})) {\n'
					+ 'api.set("${safe(name)}", __v);\n'
					+ '__r=${emitExpr(body)};\n'
					+ '}\nreturn __r;\n})()';
			case ETernary(c, a, b): '(${emitExpr(c)} ? ${emitExpr(a)} : ${emitExpr(b)})';
			case EParent(x): '(${emitExpr(x)})';
			case EArrayDecl(vs): '[' + [for (v in vs) emitExpr(v)].join(",") + ']';
			case EObject(fs): '{' + [for (f in fs) '${safe(f.name)}: ${emitExpr(f.e)}'].join(",") + '}';
			case EArray(a, i): '${emitExpr(a)}[${emitExpr(i)}]';
			case ELookback(series, n):
				emitLookback(series, n);
			case EFunction(args, body, kind, name):
				if (kind == Generator) throw new EmitUnsupported();
				var params = [for (a in args) safe(a)].join(", ");
				var fn = 'function(${params}){\n'
					+ [for (a in args) 'api.set("${safe(a)}", ${safe(a)});'].join("\n")
					+ "\n" + emitFnBody(body) + "\n}";
				name != null
					? '(api.set("${safe(name)}", $fn), api.get("${safe(name)}"))'
					: fn;
			case EMeta("__scr", [EConst(CInt(id))], ECall(EIdent(name), args))
				if (name == "macd" || name == "bbands" || name == "stoch"):
				// field-only result → per-callsite scratch object (CallsiteIds pass)
				var em = [for (i in 0...args.length) emitCallArg(name, i, args[i])];
				'api.scr_${name}(${id}${em.length > 0 ? ", " + em.join(",") : ""})';
			case EMeta("__cs", [EConst(CInt(id))], ECall(EIdent(name), args))
				if (name == "crossover" || name == "crossunder" || name == "rising" || name == "falling"):
				// static-callsite-id stateful builtin (CallsiteIds pass)
				var em = [for (a in args) emitExpr(a)];
				'api.cs_${name}(${id}${em.length > 0 ? ", " + em.join(",") : ""})';
			case EMeta(_, _, x): emitExpr(x);
			case EReturn(v):
				// Expression-context return (rare) — IIFE; prefer emitFnBody for functions.
				v != null ? '(function(){ return ${emitExpr(v)}; })()' : '(function(){ return; })()';
			case EMatch(scrutinee, arms):
				emitMatch(scrutinee, arms);
			case EYield(_) | EYieldStar(_):
				throw new EmitUnsupported();
		};
	}

	function emitMatch(scrutinee:Expr, arms:Array<MatchArm>):String {
		var s = fresh("s");
		var parts:Array<String> = ['var ${s}=${emitExpr(scrutinee)};'];
		for (arm in arms) {
			var binds:Array<String> = [];
			var cond = emitPattern(arm.pattern, s, binds);
			if (arm.guard != null) {
				// Guards see bindings via api.set before guard eval
				var gbind = [for (b in binds) b].join("");
				cond = '(function(){${gbind}return (${cond})&&(${emitExpr(arm.guard)});})()';
			} else if (binds.length > 0) {
				cond = '(function(){${binds.join("")}return (${cond});})()';
			}
			var bindAgain = [for (b in binds) b].join("");
			parts.push('if(${cond}){${bindAgain}return ${emitExpr(arm.body)};}');
		}
		parts.push("return null;");
		return "(function(){\n" + parts.join("\n") + "\n})()";
	}

	/** Emit pattern test; push `api.set(...)` bindings into `binds`. σχῆμα καὶ δεσμός. */
	function emitPattern(pat:Pattern, scrutVar:String, binds:Array<String>):String {
		return switch (pat) {
			case PatWild:
				"true";
			case PatLit(c):
				'(${scrutVar}===${emitConst(c)})';
			case PatBind(name):
				binds.push('api.set("${safe(name)}",${scrutVar});');
				"true";
			case PatTyped(name, typeName):
				binds.push('api.set("${safe(name)}",${scrutVar});');
				emitTypeCheck(scrutVar, typeName);
			case PatAs(inner, name):
				var innerCond = emitPattern(inner, scrutVar, binds);
				binds.push('api.set("${safe(name)}",${scrutVar});');
				innerCond;
			case PatGuard(inner, g):
				var innerCond = emitPattern(inner, scrutVar, binds);
				'(${innerCond})&&(${emitExpr(cast g)})';
			case PatOr(a, b):
				var ba:Array<String> = [];
				var bb:Array<String> = [];
				var ca = emitPattern(a, scrutVar, ba);
				var cb = emitPattern(b, scrutVar, bb);
				// Or arms need exclusive binding — apply first matching side
				'(function(){if(${ca}){${ba.join("")}return true;}if(${cb}){${bb.join("")}return true;}return false;})()';
			case PatObj(fields):
				var parts = ['(${scrutVar}!=null)'];
				for (f in fields) {
					var fv = fresh("f");
					binds.push('var ${fv}=${scrutVar}.${safe(f.name)};');
					parts.push(emitPattern(f.pat, fv, binds));
				}
				"(" + parts.join("&&") + ")";
			case PatArr(items, rest):
				var parts = ['Array.isArray(${scrutVar})'];
				if (rest == null)
					parts.push('(${scrutVar}.length===${items.length})');
				else
					parts.push('(${scrutVar}.length>=${items.length})');
				for (i in 0...items.length) {
					var iv = fresh("a");
					binds.push('var ${iv}=${scrutVar}[${i}];');
					parts.push(emitPattern(items[i], iv, binds));
				}
				if (rest != null)
					binds.push('api.set("${safe(rest)}",${scrutVar}.slice(${items.length}));');
				"(" + parts.join("&&") + ")";
			case PatTag(tag, args):
				emitTagPattern(tag, args, scrutVar, binds);
		};
	}

	function emitTagPattern(tag:String, args:Array<Pattern>, scrutVar:String, binds:Array<String>):String {
		var t = escape(tag);
		if (args.length == 0) {
			return '((typeof ${scrutVar}==="string"&&${scrutVar}==="${t}")'
				+ '||(${scrutVar}!=null&&${scrutVar}.__tag==="${t}")'
				+ '||(${scrutVar}!=null&&${scrutVar}.kind==="${t}"))';
		}
		var parts = ['(${scrutVar}!=null&&(${scrutVar}.__tag==="${t}"||${scrutVar}.kind==="${t}"))'];
		if (args.length == 1) {
			parts.push(emitPattern(args[0], scrutVar, binds));
			return "(" + parts.join("&&") + ")";
		}
		for (i in 0...args.length) {
			var iv = fresh("g");
			binds.push('var ${iv}=(Array.isArray(${scrutVar}.args)?${scrutVar}.args[${i}]:null);');
			parts.push(emitPattern(args[i], iv, binds));
		}
		return "(" + parts.join("&&") + ")";
	}

	function emitTypeCheck(v:String, typeName:String):String {
		return switch (typeName.toLowerCase()) {
			case "float" | "number": '(typeof ${v}==="number")';
			case "int" | "integer": '(typeof ${v}==="number"&&(${v}|0)===${v})';
			case "string": '(typeof ${v}==="string")';
			case "bool" | "boolean": '(typeof ${v}==="boolean")';
			case "array": 'Array.isArray(${v})';
			default: "true";
		};
	}

	function emitConst(c:Const):String {
		return switch (c) {
			case CInt(i): Std.string(i);
			case CFloat(f): Std.string(f);
			case CString(s): '"' + escape(s) + '"';
			case CBool(b): b ? "true" : "false";
			case CNull: "null";
		};
	}

	/**
	 * Bare series → api.lookback(name, n); call/other → re-eval under truncated series.
	 * καλῶ τὸ SMA, καὶ εὐθὺς ζητῶ τὸ [1].
	 */
	function emitLookback(series:Expr, n:Expr):String {
		return switch (series) {
			case EParent(inner):
				emitLookback(inner, n);
			case EBarField(_) | EIdent(_):
				'api.lookback(${emitSeriesRef(series)}, ${emitExpr(n)})';
			default:
				'api.withSeriesOffset(${emitExpr(n)}, function(){ return ${emitExpr(series)}; })';
		};
	}

	/** Series name for lookback — string literal, not a bar value.
	 * τὸ ὄνομα τῆς σειρᾶς, οὐχ ἡ τιμή.
	 */
	function emitSeriesRef(e:Expr):String {
		return switch (e) {
			case EBarField(n) | EIdent(n): '"' + safe(n) + '"';
			default: emitExpr(e);
		};
	}

	function emitCallArg(callee:String, index:Int, arg:Expr):String {
		if (BuiltinSigs.wantsSeries(callee, index) && BuiltinSigs.seriesNameOf(arg) != null)
			return emitSeriesRef(arg);
		return emitExpr(arg);
	}

	function safe(n:String):String {
		return ~/[^a-zA-Z0-9_$]/.replace(n, "_");
	}

	function escape(s:String):String {
		return s.split("\\").join("\\\\").split("\"").join("\\\"").split("\n").join("\\n");
	}
}
