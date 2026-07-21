package musescript.builtins;

/**
 * Pure MuseScript-source renderer for the `ta` toolbelt — the SINGLE place
 * the generated-per-indicator script shape lives. Deliberately free of any
 * macro or runtime imports so the exact same code runs in BOTH worlds:
 * `TaSourcesMacro` calls it inside the macro interpreter to bake sources at
 * compile time, and `TaToolbelt.entryFromSpec` calls it at runtime for any
 * class the macro could not statically extract (so the two paths can never
 * drift — there is only one renderer).
 *
 * Types arrive as MuseType ENUM CONSTRUCTOR NAMES ("TSeries", "TWindow", …)
 * because that is the one spelling both worlds can produce cheaply: the
 * macro reads them off `FEnum` fields in the typed AST, the runtime reads
 * them via `Type.enumConstructor`.
 */
class TaSourceRender {
	/** `cmo(Series, Window) -> Scalar` / `stochastic(Window) -> {k, d}`. */
	public static function sig(name:String, argKinds:Array<String>, retFields:Null<Array<String>>):String {
		var args = [for (k in argKinds) pretty(k)].join(", ");
		var ret = retFields == null ? "Scalar" : "{" + retFields.join(", ") + "}";
		return '$name($args) -> $ret';
	}

	/**
	 * A minimal, runnable MuseScript demo strategy for one indicator: call it
	 * with canonical default args and plot every output line. This is the
	 * "MuseScript sourcecode for each ported indicator" surfaced through
	 * `ta.source(name)` (and reflection on the Haxe side).
	 */
	public static function source(name:String, argKinds:Array<String>, retFields:Null<Array<String>>,
			doc:String, libFile:String):String {
		var b = new StringBuf();
		if (doc != null && doc != "") b.add('// $name — $doc\n');
		else b.add('// $name\n');
		b.add('// sig: ${sig(name, argKinds, retFields)}\n');
		b.add('// generated from musescript/indicators/lib/$libFile\n');
		b.add('@strategy("ta.$name")\n');
		b.add('@on(bar) {\n');
		b.add('  var v = $name(${defaultArgs(argKinds).join(", ")});\n');
		if (retFields == null) {
			b.add('  plot(v, "$name");\n');
		} else {
			for (f in retFields) b.add('  plot(v.$f, "$name.$f");\n');
		}
		b.add('}\n');
		return b.toString();
	}

	/**
	 * Canonical default argument literals, one per declared arg. Same
	 * synthesis rules the registry safety-net test and WickraDemoExport
	 * already use: price series → `close`, windows → 5, 10, 15… (kept
	 * strictly increasing so fast/slow-ordered params stay valid), strings →
	 * `"x"`, any remaining scalar → 0.5 (valid for both [0,1]-bounded and
	 * generic multiplier args).
	 */
	public static function defaultArgs(argKinds:Array<String>):Array<String> {
		var windowIdx = 0;
		return [for (k in argKinds) switch (k) {
			case "TSeries": "close";
			case "TWindow": { windowIdx++; Std.string(5 * windowIdx); }
			case "TString": '"x"';
			case "TBool": "true";
			default: "0.5";
		}];
	}

	/** "TSeries" → "Series" (drop the enum-constructor `T` prefix for humans). */
	static function pretty(kind:String):String {
		return (kind.length > 1 && kind.charAt(0) == "T") ? kind.substr(1) : kind;
	}

	/**
	 * The short human title used in the generated header comment: the class
	 * doc's first clause, cut at the "— ported from …" citation every port's
	 * doc comment carries (keeping the description, dropping the URL noise).
	 */
	public static function docTitle(rawDoc:String):String {
		if (rawDoc == null) return "";
		var d = StringTools.trim(rawDoc);
		var cut = d.indexOf("— ported");
		if (cut < 0) cut = d.indexOf("- ported");
		if (cut >= 0) d = StringTools.trim(d.substr(0, cut));
		var dot = d.indexOf(". ");
		if (dot > 0) d = d.substr(0, dot);
		if (d.length > 120) d = d.substr(0, 117) + "...";
		return d;
	}
}
