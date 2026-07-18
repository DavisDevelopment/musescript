package musescript.ast;

import musescript.types.AstSpans;

@:structInit
class MuseProgram {
	public var decls:Array<Decl> = [];
	public var stmts:Array<Stmt> = [];
	/** Optional expr/stmt → SourcePos table filled by parsers. */
	public var spans:Null<AstSpans> = null;
}
