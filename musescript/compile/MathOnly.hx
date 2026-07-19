package musescript.compile;

import musescript.ast.Expr;
import musescript.ast.Const;
import musescript.ast.Decl;
import musescript.ast.MuseProgram;
import musescript.ast.FnKind;

/**
 * Detect pure math function decls that may target numba / wasm / python emitters.
 * Disallows bar I/O, orders, lookback, match, yield, objects, and unknown calls.
 */
class MathOnly {
	static var allowedCalls:Map<String, Bool> = [
		"Math.abs" => true, "Math.sin" => true, "Math.cos" => true, "Math.tan" => true,
		"Math.sqrt" => true, "Math.floor" => true, "Math.ceil" => true, "Math.round" => true,
		"Math.min" => true, "Math.max" => true, "Math.pow" => true, "Math.exp" => true,
		"Math.log" => true, "abs" => true, "sin" => true, "cos" => true, "sqrt" => true,
		"floor" => true, "ceil" => true, "round" => true, "min" => true, "max" => true,
		"pow" => true, "exp" => true, "log" => true, "nz" => true, "clamp" => true
	];

	public static function extract(prog:MuseProgram):Array<MathFnDecl> {
		var out:Array<MathFnDecl> = [];
		for (d in prog.decls) switch (d) {
			case FnDecl(name, args, body, kind) if (name != null && kind == Normal && isMathExpr(body)):
				out.push({ name: name, args: args, body: body });
			default:
		}
		return out;
	}

	public static function find(prog:MuseProgram, name:String):Null<MathFnDecl> {
		for (f in extract(prog)) if (f.name == name) return f;
		return null;
	}

	public static function isMathExpr(e:Expr):Bool {
		return switch (e) {
			case EConst(_): true;
			case EIdent(_): true;
			case EVar(_, init): init == null || isMathExpr(init);
			case EBlock(es):
				for (x in es) if (!isMathExpr(x)) return false;
				true;
			case EBinop(_, a, b): isMathExpr(a) && isMathExpr(b);
			case EUnop(_, _, x): isMathExpr(x);
			case EIf(c, a, b): isMathExpr(c) && isMathExpr(a) && (b == null || isMathExpr(b));
			case EWhile(c, body): isMathExpr(c) && isMathExpr(body);
			case EFor(_, it, body): isMathExpr(it) && isMathExpr(body);
			case EReturn(v): v == null || isMathExpr(v);
			case EParent(x): isMathExpr(x);
			case ETernary(c, a, b): isMathExpr(c) && isMathExpr(a) && isMathExpr(b);
			case EArrayDecl(vs):
				for (v in vs) if (!isMathExpr(v)) return false;
				true;
			case EArray(a, i): isMathExpr(a) && isMathExpr(i);
			case EField(EIdent(_), "length"): true;
			case ECall(callee, args):
				var key = callKey(callee);
				if (key == null || !allowedCalls.exists(key)) return false;
				for (a in args) if (!isMathExpr(a)) return false;
				true;
			case EField(EIdent("Math"), _): true;
			case ELookback(_, _) | EBarField(_) | EMatch(_, _) | EYield(_) | EYieldStar(_)
				| EObject(_) | EMeta(_, _, _) | EFunction(_, _, _, _) | EField(_, _)
				| ENew(_, _) | EThis | ESuper(_, _):
				false;
		};
	}

	static function callKey(e:Expr):Null<String> {
		return switch (e) {
			case EIdent(n): n;
			case EField(EIdent("Math"), f): "Math." + f;
			default: null;
		};
	}
}
