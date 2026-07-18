package musescript.docs;

import musescript.types.BuiltinSigs;
import musescript.types.MuseTypes;

/** One builtin's combined doc comment + typed signature. */
typedef BuiltinDoc = {
	var name:String;
	var doc:Null<String>;
	var source:Null<String>;
	var args:Array<String>;
	var returns:String;
	var minArgs:Int;
}

typedef DocEntry = { name:String, doc:String, source:String }

/**
 * Runtime-queryable builtin doc registry — ROADMAP.md "Docstring
 * introspection pipeline". `raw` is compiled in by BuiltinDocsMacro at
 * BUILD time (see its doc); this class merges it with the always-current
 * `BuiltinSigs` typed-signature table at query time, so a name with a
 * signature but no doc comment (most indicators today) still resolves —
 * just with `doc: null` — and a stale/renamed doc comment can never
 * silently point at the wrong signature.
 */
class BuiltinDocs {
	public static var raw(default, null):Array<DocEntry> = BuiltinDocsMacro.buildRegistry();

	static var byName:Map<String, DocEntry>;

	static function ensure():Void {
		if (byName != null) return;
		byName = new Map();
		for (e in raw) byName.set(e.name, e);
	}

	/** Combined doc + signature for `name`, or null if BuiltinSigs doesn't know it either. */
	public static function get(name:String):Null<BuiltinDoc> {
		ensure();
		var sig = BuiltinSigs.get(name);
		var entry = byName.get(name);
		if (sig == null && entry == null) return null;
		return {
			name: name,
			doc: entry != null ? entry.doc : null,
			source: entry != null ? entry.source : null,
			args: sig != null ? [for (a in sig.args) MuseTypes.toString(a)] : [],
			returns: sig != null ? MuseTypes.toString(sig.ret) : "Unknown",
			minArgs: sig != null ? (sig.minArgs != null ? sig.minArgs : sig.args.length) : 0
		};
	}

	/**
	 * The real MuseScript builtin surface: every name BuiltinSigs knows,
	 * sorted. Deliberately NOT a union with `raw` — a doc'd Haxe static with
	 * no BuiltinSigs entry (an internal helper like `install`/`materialize`,
	 * or a name-convention miss) is not a callable MuseScript builtin and
	 * must not show up in the reference manual as if it were one.
	 */
	public static function names():Array<String> {
		var out = [for (n in BuiltinSigs.all().keys()) n];
		out.sort(Reflect.compare);
		return out;
	}

	/** How many BuiltinSigs entries currently have a hoisted doc comment — a coverage metric, not a gate. */
	public static function coverage():{documented:Int, total:Int} {
		ensure();
		var total = 0, documented = 0;
		for (n in BuiltinSigs.all().keys()) {
			total++;
			if (byName.exists(n)) documented++;
		}
		return { documented: documented, total: total };
	}

	/**
	 * Reference manual as GitHub-flavored Markdown, one row per known
	 * builtin, sorted. Undocumented builtins still appear (signature-only
	 * row) so the table is a complete surface map, not just a coverage brag.
	 */
	public static function toMarkdown():String {
		ensure();
		var b = new StringBuf();
		b.add("# MuseScript builtin reference\n\n");
		b.add("Auto-generated from BuiltinSigs + hoisted doc comments — do not hand-edit.\n\n");
		b.add("| Name | Signature | Description | Source |\n");
		b.add("|---|---|---|---|\n");
		for (n in names()) {
			var d = get(n);
			var argsStr = d.args.length > 0 ? d.args.join(", ") : "";
			var sig = '$n($argsStr) -> ${d.returns}';
			var doc = d.doc != null ? d.doc : "_(undocumented)_";
			var src = d.source != null ? d.source : "";
			var tick = String.fromCharCode(96);
			b.add('| $tick${n}$tick | $tick${sig}$tick | ${doc} | ${src} |\n');
		}
		return b.toString();
	}
}
