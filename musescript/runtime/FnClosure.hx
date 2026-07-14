package musescript.runtime;

import musescript.ast.MuseProgram;
import musescript.ast.Decl;
import musescript.ast.Stmt;
import musescript.ast.Expr;
import musescript.ast.Const;
import musescript.ast.MatchArm;
import musescript.ast.FnKind;
import musescript.ast.OrderKind;
import musescript.ast.ParamOpts;

/**
 * Closure capturing MuseAST function body + lexical parent frame.
 */
class FnClosure {
	public var args:Array<String>;
	public var body:Expr;
	public var parent:Null<CallFrame>;
	public var name:Null<String>;
	public var kind:FnKind;
	/** Persistent indicator state keyed by call-site (survives bars). */
	public var indicatorState:Null<Map<String, Dynamic>>;

	public function new(args:Array<String>, body:Expr, ?parent:CallFrame, ?name:String, ?kind:FnKind) {
		this.args = args;
		this.body = body;
		this.parent = parent;
		this.name = name;
		this.kind = kind != null ? kind : Normal;
		this.indicatorState = null;
	}

	public function isGenerator():Bool {
		return kind == Generator;
	}
}
