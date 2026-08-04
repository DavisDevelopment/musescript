package musescript.io;

import musescript.builtins.PathBuiltins;

/**
 * Resolve a Muse logical path under {@link IoGrant}.fs roots.
 *
 * Paths use `/`. Absolute Muse paths must stay under a granted root's `abs`.
 * Relative paths join the first matching root (or `name:rel` picks a named root).
 * After normalize, `..` escapes throw {@link IoDenied}.
 */
class FsGrant {
	public static function requireRoots(op:String, ?grants:Null<IoGrant>):Dynamic {
		return IoDenied.requireFs(op, grants);
	}

	/**
	 * Resolve `userPath` to a native filesystem path under a grant root.
	 * `needWrite` requires the matching root to have `write: true`.
	 */
	public static function resolve(
		op:String,
		?grants:Null<IoGrant>,
		userPath:String,
		needWrite:Bool = false
	):{ rootName:String, museAbs:String, nativeAbs:String } {
		var fs = requireRoots(op, grants);
		var roots:Array<Dynamic> = cast Reflect.field(fs, "roots");
		if (roots == null || roots.length == 0)
			throw new IoDenied(op, "fs grant missing roots");

		var raw = userPath == null ? "" : StringTools.replace(Std.string(userPath), "\\", "/");
		var rootName:Null<String> = null;
		var rel = raw;
		var colon = raw.indexOf(":");
		// `name:rel` alias — not a Windows drive (`C:/…`).
		if (colon > 0
			&& !(colon == 1 && isDriveLetter(raw.charCodeAt(0)))
			&& raw.indexOf("/") != 0) {
			rootName = raw.substr(0, colon);
			rel = raw.substr(colon + 1);
			while (StringTools.startsWith(rel, "/")) rel = rel.substr(1);
		}

		var candidates:Array<Dynamic> = [];
		if (rootName != null) {
			for (r in roots) {
				if (Std.string(Reflect.field(r, "name")) == rootName) {
					candidates.push(r);
					break;
				}
			}
			if (candidates.length == 0)
				throw new IoDenied(op, 'unknown fs root "$rootName"');
		} else {
			candidates = roots;
		}

		var lastDetail = "no matching fs root";
		for (r in candidates) {
			var name = Std.string(Reflect.field(r, "name"));
			var abs = StringTools.replace(Std.string(Reflect.field(r, "abs")), "\\", "/");
			abs = PathBuiltins.normalize(stripTrailingSlash(abs));
			var canRead = Reflect.field(r, "read") == true;
			var canWrite = Reflect.field(r, "write") == true;
			if (needWrite) {
				if (!canWrite) {
					lastDetail = 'root "$name" is not writable';
					continue;
				}
			} else if (!canRead) {
				lastDetail = 'root "$name" is not readable';
				continue;
			}

			var museAbs:String;
			if (PathBuiltins.isAbsolute(rel) && rootName == null) {
				museAbs = PathBuiltins.normalize(rel);
				if (!pathUnderRoot(abs, museAbs)) {
					lastDetail = 'path escapes root "$name"';
					continue;
				}
			} else {
				if (!PathBuiltins.isWithin(abs, rel.length == 0 ? "." : rel)) {
					lastDetail = 'path escapes root "$name"';
					continue;
				}
				museAbs = PathBuiltins.normalize(PathBuiltins.joinParts([abs, rel]));
			}

			return {
				rootName: name,
				museAbs: museAbs,
				nativeAbs: toNative(museAbs)
			};
		}
		throw new IoDenied(op, lastDetail);
	}

	static function pathUnderRoot(rootAbs:String, childAbs:String):Bool {
		var r = PathBuiltins.normalize(rootAbs);
		var c = PathBuiltins.normalize(childAbs);
		if (r == "/") return PathBuiltins.isAbsolute(c);
		var rl = r.toLowerCase();
		var cl = c.toLowerCase();
		if (!StringTools.startsWith(cl, rl)) return false;
		if (cl.length == rl.length) return true;
		return c.charAt(r.length) == "/";
	}

	static function stripTrailingSlash(s:String):String {
		if (s.length > 1 && (s.charAt(s.length - 1) == "/" || s.charAt(s.length - 1) == "\\"))
			return s.substr(0, s.length - 1);
		return s;
	}

	static function toNative(museAbs:String):String {
		#if (sys || nodejs)
		if (Sys.systemName() == "Windows")
			return StringTools.replace(museAbs, "/", "\\");
		#end
		return museAbs;
	}

	static inline function isDriveLetter(code:Null<Int>):Bool {
		return code != null && ((code >= 65 && code <= 90) || (code >= 97 && code <= 122));
	}
}
