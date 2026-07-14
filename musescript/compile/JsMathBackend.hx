package musescript.compile;

import musescript.ast.Expr;
import musescript.ast.Const;
import musescript.ast.MuseProgram;

/**
 * Compile math-only Muse function to JS via eval.
 */
class JsMathBackend {
	public static function emitSource(prog:MuseProgram, name:String):Null<String> {
		var fn = MathOnly.find(prog, name);
		if (fn == null) return null;
		return new JsFnEmitter().emit(fn);
	}

	public static function compileFn(prog:MuseProgram, name:String):Null<Dynamic> {
		var src = emitSource(prog, name);
		if (src == null) return null;
		#if js
		var jsFn:Dynamic = js.Lib.eval('(' + src + ')');
		return function(args:Array<Dynamic>):Dynamic {
			return Reflect.callMethod(null, jsFn, args);
		};
		#else
		return null;
		#end
	}
}

/** Minimal JS emitter for math-only functions */
class JsFnEmitter {
	public function new() {}

	public function emit(fn:MathFnDecl):String {
		return 'function ${fn.name}(${fn.args.join(",")}){\n${emitBody(fn.body)}\n}';
	}

	function emitBody(e:Expr):String {
		return switch (e) {
			case EBlock(es):
				var lines:Array<String> = [];
				for (i in 0...es.length) {
					var x = es[i];
					if (i == es.length - 1 && !isStmt(x))
						lines.push("return " + emitExpr(x) + ";");
					else
						lines.push(emitStmt(x));
				}
				lines.join("\n");
			case EReturn(v):
				v != null ? "return " + emitExpr(v) + ";" : "return;";
			default:
				"return " + emitExpr(e) + ";";
		};
	}

	function isStmt(e:Expr):Bool {
		return switch (e) {
			case EVar(_, _) | EWhile(_, _) | EFor(_, _, _) | EReturn(_) | EBlock(_): true;
			case EBinop("=", _, _): true;
			case EIf(_, a, b): isStmt(a) || (b != null && isStmt(b));
			default: false;
		};
	}

	function emitStmt(e:Expr):String {
		return switch (e) {
			case EVar(n, init):
				"var " + n + " = " + (init != null ? emitExpr(init) : "undefined") + ";";
			case EBinop("=", left, v):
				emitExpr(left) + " = " + emitExpr(v) + ";";
			case EWhile(c, body):
				"while(" + emitExpr(c) + "){" + emitBodyBlock(body) + "}";
			case EIf(c, a, b):
				"if(" + emitExpr(c) + "){" + emitBodyBlock(a) + "}"
					+ (b != null ? "else{" + emitBodyBlock(b) + "}" : "");
			case EReturn(v):
				v != null ? "return " + emitExpr(v) + ";" : "return;";
			case EBlock(es):
				[for (x in es) emitStmt(x)].join("\n");
			default:
				emitExpr(e) + ";";
		};
	}

	function emitBodyBlock(e:Expr):String {
		return switch (e) {
			case EBlock(es): [for (x in es) emitStmt(x)].join("\n");
			default: emitStmt(e);
		};
	}

	function emitExpr(e:Expr):String {
		return switch (e) {
			case EConst(c):
				switch (c) {
					case CInt(i): Std.string(i);
					case CFloat(f): Std.string(f);
					case CString(s): '"' + s.split('"').join('\\"') + '"';
					case CBool(b): b ? "true" : "false";
					case CNull: "null";
				}
			case EIdent(n): n;
			case EBinop(op, a, b):
				op == "=" ? "(" + emitExpr(a) + "=" + emitExpr(b) + ")" : "(" + emitExpr(a) + op + emitExpr(b) + ")";
			case EUnop(op, prefix, x):
				prefix ? "(" + op + emitExpr(x) + ")" : "(" + emitExpr(x) + op + ")";
			case ECall(callee, args):
				emitExpr(callee) + "(" + [for (a in args) emitExpr(a)].join(",") + ")";
			case EField(obj, f): emitExpr(obj) + "." + f;
			case EIf(c, a, b):
				"(" + emitExpr(c) + "?" + emitExpr(a) + ":" + (b != null ? emitExpr(b) : "null") + ")";
			case ETernary(c, a, b): "(" + emitExpr(c) + "?" + emitExpr(a) + ":" + emitExpr(b) + ")";
			case EParent(x): "(" + emitExpr(x) + ")";
			case EArrayDecl(vs): "[" + [for (v in vs) emitExpr(v)].join(",") + "]";
			case EArray(a, i): emitExpr(a) + "[" + emitExpr(i) + "]";
			case EVar(n, init):
				"(" + n + "=" + (init != null ? emitExpr(init) : "undefined") + ")";
			case EBlock(es):
				"(function(){" + emitBody(EBlock(es)) + "})()";
			case EReturn(v):
				v != null ? emitExpr(v) : "undefined";
			default:
				throw "JsFnEmitter: unsupported";
		};
	}
}
