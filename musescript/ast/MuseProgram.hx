package musescript.ast;

import musescript.types.AstSpans;

typedef MuseProgram = {
	var decls:Array<Decl>;
	var stmts:Array<Stmt>;
	/** Optional expr/stmt → SourcePos table filled by parsers. */
	var ?spans:AstSpans;
}
