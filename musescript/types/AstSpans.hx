package musescript.types;

import haxe.ds.ObjectMap;
import musescript.ast.Expr;
import musescript.ast.Stmt;

/**
 * Side-table of source spans for Muse AST nodes.
 * Enums stay pos-free; parsers stamp identities into an ObjectMap that
 * rides on MuseProgram.spans for checker / editor diagnostics.
 */
class AstSpans {
	var exprs:ObjectMap<Dynamic, SourcePos>;
	var stmts:ObjectMap<Dynamic, SourcePos>;

	/** Active table during a parse; MuseNodes auto-stamps when pending is set. */
	public static var active:Null<AstSpans> = null;
	/** Pending span applied by the next MuseNodes construction. */
	public static var pending:Null<SourcePos> = null;

	public function new() {
		exprs = new ObjectMap();
		stmts = new ObjectMap();
	}

	public function stampExpr(e:Expr, ?pos:SourcePos):Expr {
		if (e != null && pos != null) exprs.set(e, pos);
		return e;
	}

	public function stampStmt(s:Stmt, ?pos:SourcePos):Stmt {
		if (s != null && pos != null) stmts.set(s, pos);
		return s;
	}

	public function ofExpr(e:Expr):Null<SourcePos> {
		return e == null ? null : exprs.get(e);
	}

	public function ofStmt(s:Stmt):Null<SourcePos> {
		return s == null ? null : stmts.get(s);
	}

	/** MuseNodes hook: stamp with pending if an active table is parsing. */
	public static function autoStamp(e:Expr):Expr {
		if (active != null && pending != null && e != null)
			active.stampExpr(e, pending);
		return e;
	}

	public static function begin():AstSpans {
		var s = new AstSpans();
		active = s;
		pending = null;
		return s;
	}

	public static function end():Void {
		active = null;
		pending = null;
	}
}
