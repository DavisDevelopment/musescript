package musescript.pinescript.ast;

import haxe.ds.ObjectMap;
import musescript.types.SourcePos;
import musescript.pinescript.PineVersion;

/**
 * A parsed Pine script. `version` is the sniffed dialect; `header` is the single
 * indicator/strategy/library call; `decls` are functions/types/imports and the
 * per-bar body statements in source order.
 *
 * Spans ride in a side-table keyed by node identity (same discipline as
 * `musescript.ast.MuseProgram` — enums stay pos-free).
 */
class PineProgram {
	public var version:PineVersion = PineVersion.DEFAULT;
	public var header:Null<PineDecl> = null;
	public var decls:Array<PineDecl> = [];

	/** node → source span, filled by the parser for diagnostics. */
	public var spans:ObjectMap<Dynamic, SourcePos> = new ObjectMap();

	public function new() {}

	public function stamp<T>(node:T, pos:Null<SourcePos>):T {
		if (node != null && pos != null) spans.set(node, pos);
		return node;
	}

	public function posOf(node:Dynamic):Null<SourcePos> {
		return node == null ? null : spans.get(node);
	}
}
