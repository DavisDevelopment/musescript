package musescript.docs;

import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;

/**
 * Build-time doc-comment extraction — ROADMAP.md "Docstring introspection
 * pipeline". Runs once per compile (`buildRegistry()` is a macro function
 * called from `BuiltinDocs.raw`'s field initializer); the result is baked
 * into the target as a plain array literal, so there is zero runtime cost
 * and nothing to keep in sync by hand — the docs ARE the doc comments,
 * always, because there is no second copy to drift.
 *
 * The `macro` keyword on `buildRegistry` (not an `#if macro` guard) is what
 * makes this callable from ordinary code: the function's body only ever
 * runs inside the macro interpreter regardless of the calling target, but
 * its SIGNATURE must stay visible to normal (non-macro) compilation so the
 * caller can resolve the call at all.
 */
class BuiltinDocsMacro {
	/**
	 * Builtin classes to scan. Deliberately an explicit list, not a package
	 * scan — package scanning would pull in vendor/hscript and anything else
	 * on the classpath, and silently start documenting things that were
	 * never meant to be part of the MuseScript builtin surface.
	 */
	static var CLASSES = [
		"musescript.builtins.BagBuiltins",
		"musescript.builtins.macro.MacroBuiltins",
	];

	public static macro function buildRegistry():Expr {
		var entries:Array<Expr> = [];
		for (path in CLASSES) {
			var t = try Context.getType(path) catch (e:Dynamic) null;
			if (t == null) {
				Context.warning('BuiltinDocsMacro: could not resolve $path', Context.currentPos());
				continue;
			}
			switch (t) {
				case TInst(clsRef, _):
					var cls = clsRef.get();
					var shortName = path.split(".").pop() + ".hx";
					for (f in cls.statics.get()) {
						if (f.doc == null || !isPublicMethod(f)) continue;
						var doc = cleanDoc(f.doc);
						if (doc == "") continue;
						// Emit BOTH name spellings (the raw Haxe name and its
						// snake_case form) since most hoisted statics follow the
						// snake_case-of-camelCase convention but not all do
						// (e.g. `pickBest` is registered in BuiltinSigs literally
						// as "pickBest", no underscore) — BuiltinDocs.names()
						// keeps only whichever spelling actually matches a real
						// BuiltinSigs entry, so neither convention nor its
						// exceptions produce phantom or missing doc rows.
						var snakeName = camelToSnake(f.name);
						entries.push(macro { name: $v{f.name}, doc: $v{doc}, source: $v{shortName} });
						if (snakeName != f.name)
							entries.push(macro { name: $v{snakeName}, doc: $v{doc}, source: $v{shortName} });
					}
				default:
					Context.warning('BuiltinDocsMacro: $path is not a class', Context.currentPos());
			}
		}
		return macro $a{entries};
	}

	static function isPublicMethod(f:ClassField):Bool {
		if (f.isPublic != true) return false;
		return switch (f.kind) {
			case FMethod(_): true;
			default: false;
		};
	}

	/** `bagRankMom` -> `bag_rank_mom` — matches the naming convention every
	    hoisted builtin static follows relative to its BuiltinSigs entry. */
	static function camelToSnake(s:String):String {
		var b = new StringBuf();
		for (i in 0...s.length) {
			var c = s.charAt(i);
			var isUpper = c.toUpperCase() == c && c.toLowerCase() != c;
			if (isUpper && i > 0) b.add("_");
			b.add(c.toLowerCase());
		}
		return b.toString();
	}

	/** Strip doc-comment fencing and leading "*" per line; collapse to one line. */
	static function cleanDoc(raw:String):String {
		var lines = raw.split("\n");
		var out = [];
		for (line in lines) {
			var t = StringTools.trim(line);
			if (StringTools.startsWith(t, "/**")) t = StringTools.trim(t.substr(3));
			if (StringTools.startsWith(t, "*")) t = StringTools.trim(t.substr(1));
			if (StringTools.endsWith(t, "*/")) t = StringTools.trim(t.substr(0, t.length - 2));
			if (t != "") out.push(t);
		}
		return out.join(" ");
	}
}
