package musescript.compile;

import musescript.ast.MuseProgram;
import musescript.ast.Decl;
import musescript.ast.Stmt;
import musescript.ast.Expr;
import musescript.ast.MuseNodes;

/**
 * Flatten `use Module(args)` into the strategy's onBar body (deterministic concat).
 * Modules are removed from decls after expansion.
 */
class ModuleExpand {
	public static function expand(prog:MuseProgram):MuseProgram {
		var modules = new Map<String, Decl>();
		var rest:Array<Decl> = [];
		for (d in prog.decls) switch (d) {
			case ModuleDecl(name, _, _):
				modules.set(name, d);
			default:
				rest.push(d);
		}
		if (!modules.keys().hasNext()) return prog;

		var decls:Array<Decl> = [];
		for (d in rest) {
			decls.push(switch (d) {
				case StrategyDecl(name, body):
					StrategyDecl(name, expandStmts(body, modules));
				default: d;
			});
		}
		return { decls: decls, stmts: expandStmts(prog.stmts, modules), spans: prog.spans };
	}

	static function expandStmts(stmts:Array<Stmt>, modules:Map<String, Decl>):Array<Stmt> {
		var out:Array<Stmt> = [];
		for (s in stmts) {
			switch (s) {
				case Use(name, args):
					if (!modules.exists(name))
						throw 'ModuleExpand: unknown module `$name`';
					switch (modules.get(name)) {
						case ModuleDecl(_, params, body):
							var binds:Array<Stmt> = [];
							var byName = new Map<String, Expr>();
							for (a in args) byName.set(a.name, a.value);
							for (p in params) {
								var v = byName.exists(p.name)
									? byName.get(p.name)
									: (p.def != null ? p.def : MuseNodes.floatExpr(0));
								binds.push(Assign(p.name, v));
							}
							var expanded = expandStmts(body, modules);
							out = out.concat(binds).concat(expanded);
						default:
					}
				case OnBar(body):
					out.push(OnBar(expandStmts(body, modules)));
				case OnPosition(body):
					out.push(OnPosition(expandStmts(body, modules)));
				case OnTick(body):
					out.push(OnTick(expandStmts(body, modules)));
				case OnEvent(stream, body):
					out.push(OnEvent(stream, expandStmts(body, modules)));
				case Block(body):
					out.push(Block(expandStmts(body, modules)));
				case When(cond, body):
					out.push(When(cond, expandStmts(body, modules)));
				case ForIn(n, it, body):
					out.push(ForIn(n, it, expandStmts(body, modules)));
				default:
					out.push(s);
			}
		}
		return out;
	}
}
