package musescript.pinescript.tests;

import musescript.pinescript.parse.PineParser;
import musescript.pinescript.ast.PineDecl;
import musescript.pinescript.ast.PineStmt;
import musescript.pinescript.ast.PineExpr;

/**
 * P1 smoke: parse a real-shaped Pine indicator into a PineProgram and dump a
 * compact s-expression of the AST. Proves the parser handles the header call,
 * `input.*`, namespaced `ta.*` calls, `if` with an indented block, and `plot`.
 */
class PineParseSmoke {
	static final SAMPLE = "//@version=5
indicator(\"EMA Cross\", overlay=true)
fastLen = input.int(9, \"Fast\")
slowLen = input.int(21, \"Slow\")
fast = ta.ema(close, fastLen)
slow = ta.ema(close, slowLen)
cross = ta.crossover(fast, slow)
if cross
    label.new(bar_index, high, \"X\")
plot(fast, color=color.blue)
plot(slow, color=color.red)
";

	public static function main():Void {
		var parser = new PineParser(SAMPLE, "sample.pine");
		var prog = parser.run();
		Sys.println('version: v${prog.version.toInt()}');
		Sys.println('decls: ${prog.decls.length}, errors: ${parser.errors.length}');
		for (e in parser.errors) Sys.println('  ERR ${e.msg} @ line ${e.pos.line}');
		for (d in prog.decls) Sys.println(sdecl(d));
		if (parser.errors.length > 0) { Sys.println("FAIL: parse errors"); Sys.exit(1); }
		Sys.println("OK");
	}

	static function sdecl(d:PineDecl):String {
		return switch (d) {
			case PHeader(k, args): 'header:$k(${args.length} args)';
			case PFunc(n, ps, b, _): 'func $n(${ps.length}) {${b.length} stmts}';
			case PTypeDef(n, fs, _): 'type $n {${fs.length} fields}';
			case PImport(u, l, v, _): 'import $u/$l/$v';
			case PTop(s): 'top: ${sstmt(s)}';
		};
	}

	static function sstmt(s:PineStmt):String {
		return switch (s) {
			case PAssign(n, v, _, _): '$n = ${sexpr(v)}';
			case PReassign(n, v): '$n := ${sexpr(v)}';
			case PTupleAssign(ns, v, _): '[${ns.join(",")}] = ${sexpr(v)}';
			case PExpr(e): sexpr(e);
			case PIf(c, t, ei, el):
				'if ${sexpr(c)} {${t.length}}${ei.length > 0 ? " +elif" : ""}${el != null ? " +else" : ""}';
			case PForTo(v, _, _, _, b): 'for $v=.. {${b.length}}';
			case PForIn(vs, _, b): 'for [${vs.join(",")}] in.. {${b.length}}';
			case PWhile(_, b): 'while {${b.length}}';
			case PSwitch(_, cs): 'switch {${cs.length} cases}';
			case PBreak: 'break';
			case PContinue: 'continue';
			case PReturn(e): 'return ${e != null ? sexpr(e) : ""}';
		};
	}

	static function sexpr(e:PineExpr):String {
		return switch (e) {
			case PInt(v): Std.string(v);
			case PFloat(v): Std.string(v);
			case PString(v): '"$v"';
			case PBool(v): Std.string(v);
			case PColor(h): '#$h';
			case PNa: 'na';
			case PIdent(n): n;
			case PField(t, f): '${sexpr(t)}.$f';
			case PUnop(op, x): '($op ${sexpr(x)})';
			case PBinop(op, a, b): '(${sexpr(a)} $op ${sexpr(b)})';
			case PTernary(c, t, f): '(${sexpr(c)} ? ${sexpr(t)} : ${sexpr(f)})';
			case PCall(c, args): '${sexpr(c)}(${[for (a in args) (a.name != null ? a.name + "=" : "") + sexpr(a.value)].join(", ")})';
			case PHistory(s, n): '${sexpr(s)}[${sexpr(n)}]';
			case PTuple(items): '[${[for (i in items) sexpr(i)].join(", ")}]';
			case PIfExpr(c, _, _): 'if-expr(${sexpr(c)})';
			case PSwitchExpr(_, cs): 'switch-expr(${cs.length})';
		};
	}
}
