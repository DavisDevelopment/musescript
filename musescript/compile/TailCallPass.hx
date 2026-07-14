package musescript.compile;

import musescript.ast.MuseProgram;
import musescript.ast.Decl;
import musescript.ast.Expr;

/**
 * Rewrite self-recursive tail calls into while-loops.
 *
 * Recognizes:
 *   if (cond) return base; return name(arg0', arg1', ...);
 * and the Expr form:
 *   EIf(cond, base, EReturn(ECall(EIdent(name), newArgs)))
 */
class TailCallPass {
	public static function transform(prog:MuseProgram):MuseProgram {
		var decls = [for (d in prog.decls) switch (d) {
			case FnDecl(name, args, body, kind) if (name != null && kind != Generator):
				FnDecl(name, args, rewriteTail(name, args, body), kind);
			case other: other;
		}];
		return { decls: decls, stmts: prog.stmts };
	}

	static function rewriteTail(name:String, args:Array<String>, body:Expr):Expr {
		var norm = normalize(body);
		return switch (norm) {
			case EIf(cond, base, EReturn(ECall(EIdent(n), callArgs)))
				if (n == name && callArgs.length == args.length):
				buildWhile(args, cond, unwrap(base), callArgs);
			case EIf(cond, base, ECall(EIdent(n), callArgs))
				if (n == name && callArgs.length == args.length):
				buildWhile(args, cond, unwrap(base), callArgs);
			case EBlock(es):
				EBlock([for (e in es) rewriteTail(name, args, e)]);
			default:
				body;
		};
	}

	static function normalize(body:Expr):Expr {
		return switch (body) {
			case EBlock([single]): normalize(single);
			case EIf(cond, EReturn(t), e): EIf(cond, t, e != null ? normalize(e) : null);
			case EIf(cond, t, EReturn(e)): EIf(cond, t, e);
			default: body;
		};
	}

	static function unwrap(e:Expr):Expr {
		return switch (e) {
			case EReturn(v) if (v != null): v;
			default: e;
		};
	}

	static function buildWhile(args:Array<String>, cond:Expr, base:Expr, callArgs:Array<Expr>):Expr {
		// Evaluate all RHS first (temps), then assign — matches simultaneous tail-call arg binding.
		var temps:Array<Expr> = [];
		var assigns:Array<Expr> = [];
		for (i in 0...args.length) {
			var tmp = "__tco_" + i;
			temps.push(EVar(tmp, callArgs[i]));
			assigns.push(EBinop("=", EIdent(args[i]), EIdent(tmp)));
		}
		var notCond = EUnop("!", true, cond);
		return EBlock([
			EWhile(notCond, EBlock(temps.concat(assigns))),
			base
		]);
	}
}
