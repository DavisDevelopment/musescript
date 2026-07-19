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

/**
 * Emit MuseAST on-bar body as Haxe function source.
 * Runtime bindings come from `api` (same façade as JsBackend.makeApi).
 *
 * Supported subset mirrors JsEmitter (incl. match / MatchFor / call-lookback);
 * unsupported constructs throw EmitUnsupported.
 * τὸ εἶδος ἕν· στόματα δὲ δύο.
 */
class HaxeEmitter {
	var tmpId:Int = 0;

	public function new() {}

	/**
	 * Returns Haxe source of: function onBar(api:Dynamic):Void { ... }
	 * Falls back to null if the program has constructs we can't emit yet.
	 * μορφὴ εἰς λόγον κατελθοῦσα.
	 */
	public function emitOnBar(prog:MuseProgram):Null<String> {
		var stmts = collectOnBar(prog);
		if (stmts.length == 0) return null;
		try {
			tmpId = 0;
			var body = [for (s in stmts) emitStmt(s)].join("\n");
			return "function onBar(api:Dynamic):Void {\n" + body + "\n}";
		} catch (_:EmitUnsupported) {
			return null;
		}
	}

	function collectOnBar(prog:MuseProgram):Array<Stmt> {
		var out:Array<Stmt> = [];
		function walkStmts(ss:Array<Stmt>) {
			for (s in ss) switch (s) {
				case OnBar(body): out = out.concat(body);
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

	function emitStmt(s:Stmt):String {
		return switch (s) {
			case ExprStmt(e): emitExpr(e) + ";";
			case Assign(name, e): 'api.set("${safe(name)}", ${emitExpr(e)});';
			case Block(ss): '{\n' + [for (x in ss) emitStmt(x)].join("\n") + "\n}";
			case Return(e): e != null ? "return " + emitExpr(e) + ";" : "return;";
			case Order(kind, args):
				var a = args.length > 0 ? emitExpr(args[0]) : "null";
				switch (kind) {
					case Long: 'api.long($a);';
					case Short: 'api.short($a);';
					case Flat | Close: "api.flat();";
				}
			case ForIn(name, it, body):
				var loopBody = [for (x in body) emitStmt(x)].join("\n");
				"for (__v in api.iter(" + emitExpr(it) + ")) {\n"
					+ 'api.set("${safe(name)}", __v);\n'
					+ loopBody + "\n}";
			case MatchFor(name, it, arms):
				"for (__v in api.iter(" + emitExpr(it) + ")) {\n"
					+ 'api.set("${safe(name)}", __v);\n'
					+ emitMatch(EIdent(name), arms) + ";\n}";
			case When(cond, body):
				"if (" + emitExpr(cond) + ") {\n" + [for (x in body) emitStmt(x)].join("\n") + "\n}";
			case Use(_, _):
				throw new EmitUnsupported();
			case OnBar(_) | OnPosition(_) | OnTick(_) | OnEvent(_, _) | Yield(_) | YieldStar(_):
				throw new EmitUnsupported();
		};
	}

	function emitExpr(e:Expr):String {
		return switch (e) {
			case EConst(c):
				emitConst(c);
			case EIdent(n): 'api.get("${safe(n)}")';
			case EBarField(n): 'api.bar("${safe(n)}")';
			case EVar(n, init):
				init != null
					? blockExpr([
						'api.set("${safe(n)}", ${emitExpr(init)})',
						'api.get("${safe(n)}")'
					])
					: blockExpr([
						'api.set("${safe(n)}", null)',
						"null"
					]);
			case EBlock(es):
				if (es.length == 0) return "null";
				iife([for (i in 0...es.length - 1) emitExpr(es[i]) + ";"].join("\n")
					+ "\nreturn " + emitExpr(es[es.length - 1]) + ";");
			case EField(obj, f): '${emitExpr(obj)}.${safe(f)}';
			case EBinop(op, a, b):
				if (op == "=") {
					return switch (a) {
						case EIdent(n):
							blockExpr([
								'api.set("${safe(n)}", ${emitExpr(b)})',
								'api.get("${safe(n)}")'
							]);
						case EField(obj, f):
							blockExpr([
								'Reflect.setField(${emitExpr(obj)}, "${safe(f)}", ${emitExpr(b)})',
								'Reflect.field(${emitExpr(obj)}, "${safe(f)}")'
							]);
						default: throw new EmitUnsupported();
					};
				}
				"(" + emitExpr(a) + " " + op + " " + emitExpr(b) + ")";
			case EUnop(op, prefix, x):
				prefix ? "(" + op + emitExpr(x) + ")" : "(" + emitExpr(x) + op + ")";
			case ECall(EIdent(name), args):
				'api.invoke("${safe(name)}", [${[for (a in args) emitExpr(a)].join(", ")}])';
			case ECall(callee, args):
				"api.apply(" + emitExpr(callee) + ", [" + [for (a in args) emitExpr(a)].join(", ") + "])";
			case EIf(c, a, b):
				b != null
					? "(" + emitExpr(c) + " ? " + emitExpr(a) + " : " + emitExpr(b) + ")"
					: "(" + emitExpr(c) + " ? " + emitExpr(a) + " : null)";
			case EWhile(c, body):
				iife("while (" + emitExpr(c) + ") { " + emitExpr(body) + "; }\nreturn null;");
			case EFor(name, it, body):
				iife(
					"var __r:Dynamic = null;\n"
						+ "for (__v in api.iter(" + emitExpr(it) + ")) {\n"
						+ 'api.set("${safe(name)}", __v);\n'
						+ "__r = " + emitExpr(body) + ";\n"
						+ "}\nreturn __r;"
				);
			case ETernary(c, a, b): "(" + emitExpr(c) + " ? " + emitExpr(a) + " : " + emitExpr(b) + ")";
			case EParent(x): "(" + emitExpr(x) + ")";
			case EArrayDecl(vs): "[" + [for (v in vs) emitExpr(v)].join(", ") + "]";
			case EObject(fs): "{" + [for (f in fs) safe(f.name) + ": " + emitExpr(f.e)].join(", ") + "}";
			case EArray(a, i): emitExpr(a) + "[" + emitExpr(i) + "]";
			case ELookback(series, n):
				emitLookback(series, n);
			case EFunction(args, body, kind, name):
				if (kind == Generator) throw new EmitUnsupported();
				var params = [for (a in args) safe(a)].join(", ");
				var fn = "function(" + params + "):Dynamic { return " + emitExpr(body) + "; }";
				name != null
					? blockExpr([
						'api.set("${safe(name)}", $fn)',
						'api.get("${safe(name)}")'
					])
					: fn;
			case EMeta(_, _, x): emitExpr(x);
			case EReturn(v):
				v != null ? iife("return " + emitExpr(v) + ";") : iife("return;");
			case EMatch(scrutinee, arms):
				emitMatch(scrutinee, arms);
			case EYield(_) | EYieldStar(_):
				throw new EmitUnsupported();
			case ENew(_, _) | EThis | ESuper(_, _):
				// P2/P3: classes aren't lowered by this backend yet (construction/
				// method dispatch/super stay interp-only, same as JsEmitter) —
				// bail so the caller falls back to interp, matching EYield.
				throw new EmitUnsupported();
		};
	}

	/**
	 * Match → nested if / bindings via arrow IIFE.
	 * σχῆμα κρίνεται· δεσμὸς τίθεται.
	 */
	function emitMatch(scrutinee:Expr, arms:Array<MatchArm>):String {
		var s = fresh("s");
		var parts:Array<String> = ["var " + s + " = " + emitExpr(scrutinee) + ";"];
		for (arm in arms) {
			var binds:Array<String> = [];
			var cond = emitPattern(arm.pattern, s, binds);
			if (arm.guard != null) {
				var gbind = [for (b in binds) b].join("");
				cond = iife(gbind + "return (" + cond + ") && (" + emitExpr(arm.guard) + ");");
			} else if (binds.length > 0) {
				cond = iife(binds.join("") + "return (" + cond + ");");
			}
			var bindAgain = [for (b in binds) b].join("");
			parts.push("if (" + cond + ") {" + bindAgain + "return " + emitExpr(arm.body) + ";}");
		}
		parts.push("return null;");
		return iife(parts.join("\n"));
	}

	/**
	 * Emit pattern test; push `api.set(...)` / local bindings into `binds`.
	 * σχῆμα καὶ δεσμός.
	 */
	function emitPattern(pat:Pattern, scrutVar:String, binds:Array<String>):String {
		return switch (pat) {
			case PatWild:
				"true";
			case PatLit(c):
				"(" + scrutVar + " == " + emitConst(c) + ")";
			case PatBind(name):
				binds.push('api.set("${safe(name)}", ${scrutVar});');
				"true";
			case PatTyped(name, typeName):
				binds.push('api.set("${safe(name)}", ${scrutVar});');
				emitTypeCheck(scrutVar, typeName);
			case PatAs(inner, name):
				var innerCond = emitPattern(inner, scrutVar, binds);
				binds.push('api.set("${safe(name)}", ${scrutVar});');
				innerCond;
			case PatGuard(inner, g):
				var innerCond = emitPattern(inner, scrutVar, binds);
				"(" + innerCond + ") && (" + emitExpr(cast g) + ")";
			case PatOr(a, b):
				var ba:Array<String> = [];
				var bb:Array<String> = [];
				var ca = emitPattern(a, scrutVar, ba);
				var cb = emitPattern(b, scrutVar, bb);
				iife(
					"if (" + ca + ") {" + ba.join("") + "return true;}"
						+ "if (" + cb + ") {" + bb.join("") + "return true;}"
						+ "return false;"
				);
			case PatObj(fields):
				var parts = ["(" + scrutVar + " != null)"];
				for (f in fields) {
					var fv = fresh("f");
					binds.push("var " + fv + " = " + scrutVar + "." + safe(f.name) + ";");
					parts.push(emitPattern(f.pat, fv, binds));
				}
				"(" + parts.join(" && ") + ")";
			case PatArr(items, rest):
				var parts = ["Std.isOfType(" + scrutVar + ", Array)"];
				if (rest == null)
					parts.push("(" + scrutVar + ".length == " + items.length + ")");
				else
					parts.push("(" + scrutVar + ".length >= " + items.length + ")");
				for (i in 0...items.length) {
					var iv = fresh("a");
					binds.push("var " + iv + " = " + scrutVar + "[" + i + "];");
					parts.push(emitPattern(items[i], iv, binds));
				}
				if (rest != null)
					binds.push('api.set("${safe(rest)}", ${scrutVar}.slice(${items.length}));');
				"(" + parts.join(" && ") + ")";
			case PatTag(tag, args):
				emitTagPattern(tag, args, scrutVar, binds);
		};
	}

	function emitTagPattern(tag:String, args:Array<Pattern>, scrutVar:String, binds:Array<String>):String {
		var t = escape(tag);
		if (args.length == 0) {
			return "((Std.isOfType(" + scrutVar + ", String) && " + scrutVar + ' == "' + t + '")'
				+ " || (" + scrutVar + ' != null && ' + scrutVar + '.__tag == "' + t + '")'
				+ " || (" + scrutVar + ' != null && ' + scrutVar + '.kind == "' + t + '"))';
		}
		var parts = [
			"(" + scrutVar + ' != null && (' + scrutVar + '.__tag == "' + t + '" || '
				+ scrutVar + '.kind == "' + t + '"))'
		];
		// Enum payload lives in `.args` (canonical `{__tag,args:[...]}`, matching
		// the interp reference); single-arg legacy `kind`-values fall back to the
		// whole object.
		for (i in 0...args.length) {
			var iv = fresh("g");
			var fallback = args.length == 1 ? scrutVar : "null";
			binds.push(
				"var " + iv + " = (" + scrutVar + " != null && Std.isOfType(" + scrutVar + ".args, Array) ? "
					+ scrutVar + ".args[" + i + "] : " + fallback + ");"
			);
			parts.push(emitPattern(args[i], iv, binds));
		}
		return "(" + parts.join(" && ") + ")";
	}

	function emitTypeCheck(v:String, typeName:String):String {
		return switch (typeName.toLowerCase()) {
			case "float" | "number": "Std.isOfType(" + v + ", Float)";
			case "int" | "integer": "Std.isOfType(" + v + ", Int)";
			case "string": "Std.isOfType(" + v + ", String)";
			case "bool" | "boolean": "Std.isOfType(" + v + ", Bool)";
			case "array": "Std.isOfType(" + v + ", Array)";
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
	 * Bare series → api.lookback; call/other → re-eval under withSeriesOffset.
	 * καλῶ τὸ SMA, καὶ εὐθὺς ζητῶ τὸ [1].
	 */
	function emitLookback(series:Expr, n:Expr):String {
		return switch (series) {
			case EParent(inner):
				emitLookback(inner, n);
			case EBarField(_) | EIdent(_):
				"api.lookback(" + emitSeriesRef(series) + ", " + emitExpr(n) + ")";
			default:
				"api.withSeriesOffset(" + emitExpr(n) + ", () -> " + emitExpr(series) + ")";
		};
	}

	/**
	 * Series name for lookback — string literal, not a bar value.
	 * τὸ ὄνομα τῆς σειρᾶς, οὐχ ἡ τιμή.
	 */
	function emitSeriesRef(e:Expr):String {
		return switch (e) {
			case EBarField(n) | EIdent(n): '"' + safe(n) + '"';
			default: emitExpr(e);
		};
	}

	/**
	 * Haxe block expression: { stmt; expr; }
	 * λίθος ἐπὶ λίθῳ.
	 */
	function blockExpr(parts:Array<String>):String {
		return "{" + parts.join("; ") + "}";
	}

	/**
	 * Immediately-invoked arrow for expression-level control flow.
	 * κύκλος ἔργου ταχύς.
	 */
	function iife(body:String):String {
		return "(() -> {\n" + body + "\n})()";
	}

	function safe(n:String):String {
		return ~/[^a-zA-Z0-9_$]/.replace(n, "_");
	}

	function escape(s:String):String {
		return s.split("\\").join("\\\\").split("\"").join("\\\"").split("\n").join("\\n");
	}
}
