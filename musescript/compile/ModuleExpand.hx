package musescript.compile;

import musescript.ast.MuseProgram;
import musescript.ast.Decl;
import musescript.ast.Stmt;
import musescript.ast.Expr;

/**
 * Flatten `use Module(args)` into the strategy's onBar body (deterministic concat).
 * Modules are removed from decls after expansion.
 *
 * Hardening pass (2026-07-19, alongside TemplateExpand's existing MAX_DEPTH
 * guard): this used to be considerably more permissive than TemplateExpand
 * in three ways, none of them intentional design choices —
 *   1. A missing required arg (no `use`-site value AND no declared default)
 *      silently bound to `0.0` instead of erroring, same class of bug as
 *      the P4 enum-tag silent-misemission bug found earlier this session:
 *      wrong behavior with no error, not a crash.
 *   2. An extra/misspelled arg name (`use Guard(pctt = 0.05)` typo'd) was
 *      silently DROPPED — `byName` was only ever read from, never
 *      validated against the module's declared params.
 *   3. No recursion/depth guard at all — TemplateExpand throws a clean
 *      "expansion depth exceeded" error past MAX_DEPTH; a module that
 *      (directly or, worse, indirectly through another module) `use`s
 *      itself would recurse until a raw stack overflow instead.
 * All three fixed below, mirroring TemplateExpand's depth-threading
 * convention exactly so both expanders fail the same way under the same
 * class of mistake.
 *
 * (Statement traversal itself was already complete — `Use` can only ever
 * appear as a direct element of one of the `Array<Stmt>`-holding Stmt
 * constructors, all seven of which — OnBar/OnPosition/OnTick/OnEvent/
 * Block/When/ForIn — were already handled here; `MatchFor`'s arms hold an
 * `Expr` body, which `Use` (Stmt-only) can never occupy, so there was
 * no missing traversal case despite first appearances.)
 */
class ModuleExpand {
	public static var MAX_DEPTH:Int = 64;

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
					StrategyDecl(name, expandStmts(body, modules, 0));
				default: d;
			});
		}
		return { decls: decls, stmts: expandStmts(prog.stmts, modules, 0), spans: prog.spans };
	}

	static function expandStmts(stmts:Array<Stmt>, modules:Map<String, Decl>, depth:Int):Array<Stmt> {
		if (depth > MAX_DEPTH) throw "ModuleExpand: expansion depth exceeded (non-terminating module use?)";
		var out:Array<Stmt> = [];
		for (s in stmts) {
			switch (s) {
				case Use(name, args):
					if (!modules.exists(name))
						throw 'ModuleExpand: unknown module `$name`';
					switch (modules.get(name)) {
						case ModuleDecl(_, params, body):
							var paramNames = new Map<String, Bool>();
							for (p in params) paramNames.set(p.name, true);
							for (a in args) if (!paramNames.exists(a.name))
								throw 'ModuleExpand: module `$name` has no param `${a.name}` (typo?)';

							var binds:Array<Stmt> = [];
							var byName = new Map<String, Expr>();
							for (a in args) byName.set(a.name, a.value);
							for (p in params) {
								var v:Expr;
								if (byName.exists(p.name)) v = byName.get(p.name);
								else if (p.def != null) v = p.def;
								else throw 'ModuleExpand: module `$name` requires param `${p.name}` (no default, not passed)';
								binds.push(Assign(p.name, v));
							}
							var expanded = expandStmts(body, modules, depth + 1);
							out = out.concat(binds).concat(expanded);
						default:
					}
				case OnBar(body):
					out.push(OnBar(expandStmts(body, modules, depth)));
				case OnPosition(body):
					out.push(OnPosition(expandStmts(body, modules, depth)));
				case OnTick(body):
					out.push(OnTick(expandStmts(body, modules, depth)));
				case OnEvent(stream, body):
					out.push(OnEvent(stream, expandStmts(body, modules, depth)));
				case Block(body):
					out.push(Block(expandStmts(body, modules, depth)));
				case When(cond, body):
					out.push(When(cond, expandStmts(body, modules, depth)));
				case ForIn(n, it, body):
					out.push(ForIn(n, it, expandStmts(body, modules, depth)));
				default:
					out.push(s);
			}
		}
		return out;
	}
}
