package musescript.pinescript.translit;

import musescript.types.SourcePos;

/**
 * Structured "couldn't translate this (yet)" report. The cardinal rule of the
 * transliterator: NEVER silently emit something that doesn't mean what the Pine
 * said. Anything we can't map faithfully lands here with a span and a reason, so
 * the CLI can print an honest coverage report instead of a plausible-looking
 * wrong strategy. This is also the flip side of the parity marketing claim —
 * we can state exactly what we do and don't cover.
 */
enum UnsupportedKind {
	UnknownBuiltin(name:String);
	NamedArgsApprox(callee:String);   // named args flattened positionally
	TupleDestructure(names:Array<String>);
	MultiTimeframe(name:String);       // request.security etc.
	LibraryImport(path:String);
	ElseIfChain;                       // approximated with guarded whens
	Other(what:String);
}

typedef UnsupportedNote = {
	var kind:UnsupportedKind;
	var ?pos:SourcePos;
}

class Unsupported {
	public var notes:Array<UnsupportedNote> = [];
	public function new() {}

	public function add(kind:UnsupportedKind, ?pos:SourcePos):Void
		notes.push({kind: kind, pos: pos});

	public inline function any():Bool return notes.length > 0;

	public function describe(n:UnsupportedNote):String {
		var where = n.pos != null && n.pos.line != null ? ' (line ${n.pos.line})' : "";
		return describeBare(n) + where;
	}

	/** Message without the trailing "(line N)" — for callers that render their
	 *  own line context (the converter's `TODO(pine2muse) line N:` prefix). */
	public function describeBare(n:UnsupportedNote):String {
		var msg = switch (n.kind) {
			case UnknownBuiltin(name): 'unmapped builtin `$name` — emitted verbatim, verify by hand';
			case NamedArgsApprox(callee): 'named args on `$callee` flattened positionally';
			case TupleDestructure(names): 'tuple destructure [${names.join(",")}] partially lowered';
			case MultiTimeframe(name): 'multi-timeframe/symbol `$name` needs PanelFeed wiring (P5)';
			case LibraryImport(path): 'library import `$path` not inlined';
			case ElseIfChain: 'else-if chain approximated with guarded `when`s';
			case Other(what): what;
		};
		return msg;
	}
}
