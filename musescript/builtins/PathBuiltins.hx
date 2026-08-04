package musescript.builtins;

typedef PathLike = Dynamic;

/**
 * Pure POSIX-ish path algebra for `muse.path` / `path_*`.
 *
 * No filesystem access. Separators are `/` in Muse scripts; hosts map to native
 * separators only at a sandbox root boundary (M1+). `normalize` collapses `.`
 * and resolves `..` when a prior segment exists; leftover leading `..` on a
 * relative path are preserved (callers / FsGrant reject escapes).
 */
class PathBuiltins {
	public static inline var SEP = "/";

	public static function install(vars:Map<String, Dynamic>):Void {
		vars.set("path_join", joinDyn);
		vars.set("path_normalize", normalize);
		vars.set("path_basename", basename);
		vars.set("path_dirname", dirname);
		vars.set("path_ext", ext);
		vars.set("path_is_absolute", isAbsolute);
	}

	public static function build():Dynamic {
		var p:Dynamic = {};
		Reflect.setField(p, "join", joinDyn);
		Reflect.setField(p, "normalize", normalize);
		Reflect.setField(p, "basename", basename);
		Reflect.setField(p, "dirname", dirname);
		Reflect.setField(p, "ext", ext);
		Reflect.setField(p, "is_absolute", isAbsolute);
		return p;
	}

	/** Variadic join for interp / JS Reflect.callMethod. */
	public static final joinDyn:Dynamic = Reflect.makeVarArgs(function(args:Array<Dynamic>) {
		return joinParts([for (a in args) text(a)]);
	});

	public static function joinVar(rest:haxe.Rest<Dynamic>):String {
		return joinParts([for (x in rest) text(x)]);
	}

	public static function joinParts(parts:Array<String>):String {
		if (parts == null || parts.length == 0) return "";
		var out = new StringBuf();
		var first = true;
		for (raw in parts) {
			var p = text(raw);
			if (p.length == 0) continue;
			if (first) {
				out.add(p);
				first = false;
				continue;
			}
			var cur = out.toString();
			var needSep = cur.length > 0 && !endsWithSep(cur);
			var skipLead = startsWithSep(p);
			if (needSep) out.add(SEP);
			out.add(skipLead ? p.substr(1) : p);
		}
		return out.toString();
	}

	public static function normalize(value:PathLike):String {
		var s = text(value);
		if (s.length == 0) return ".";
		s = StringTools.replace(s, "\\", SEP);
		var drivePrefix:Null<String> = null;
		if (s.length >= 2 && isDriveLetter(s.charCodeAt(0)) && s.charAt(1) == ":") {
			drivePrefix = s.substr(0, 2);
			s = s.substr(2);
			if (s.length == 0) return drivePrefix + SEP;
		}
		var absolute = drivePrefix != null || (s.length > 0 && s.charAt(0) == "/");
		var trailingSep = s.length > 1 && endsWithSep(s);
		var segments = splitSegments(s);
		var stack:Array<String> = [];
		for (seg in segments) {
			if (seg.length == 0 || seg == ".") continue;
			if (seg == "..") {
				if (stack.length > 0 && stack[stack.length - 1] != "..") {
					stack.pop();
				} else if (!absolute) {
					stack.push("..");
				}
				continue;
			}
			stack.push(seg);
		}
		if (stack.length == 0) {
			if (drivePrefix != null) return drivePrefix + SEP;
			if (absolute) return "/";
			return trailingSep ? "./" : ".";
		}
		var joined = stack.join(SEP);
		if (drivePrefix != null) joined = drivePrefix + SEP + joined;
		else if (absolute) joined = "/" + joined;
		if (trailingSep) joined += SEP;
		return joined;
	}

	public static function basename(value:PathLike):String {
		var s = stripTrailingSeps(text(value));
		if (s.length == 0) return "";
		if (s == "/") return "/";
		var i = s.lastIndexOf(SEP);
		return i < 0 ? s : s.substr(i + 1);
	}

	public static function dirname(value:PathLike):String {
		var s = stripTrailingSeps(text(value));
		if (s.length == 0) return ".";
		if (s == "/") return "/";
		var i = s.lastIndexOf(SEP);
		if (i < 0) return ".";
		if (i == 0) return "/";
		return s.substr(0, i);
	}

	/** Extension including the leading `.`, or `""` when none. */
	public static function ext(value:PathLike):String {
		var base = basename(value);
		if (base == "" || base == "/" || base == "." || base == "..") return "";
		var i = base.lastIndexOf(".");
		if (i <= 0) return "";
		return base.substr(i);
	}

	public static function isAbsolute(value:PathLike):Bool {
		var s = text(value);
		if (s.length == 0) return false;
		if (s.charAt(0) == "/") return true;
		// Drive letter `C:/…` accepted as absolute for cross-host authoring.
		if (s.length >= 3
			&& isDriveLetter(s.charCodeAt(0))
			&& s.charAt(1) == ":"
			&& (s.charAt(2) == "/" || s.charAt(2) == "\\"))
			return true;
		return false;
	}

	/**
	 * True when `child` (after normalize) does not escape `root` via `..`.
	 * Used by FsGrant (M1+); exposed for M0 goldens / anti-escape tests.
	 */
	public static function isWithin(root:PathLike, child:PathLike):Bool {
		var r = normalize(root);
		var c = normalize(joinParts([r, text(child)]));
		if (r == "/") return isAbsolute(c) && c.indexOf("/../") < 0;
		if (!StringTools.startsWith(c, r)) return false;
		if (c.length == r.length) return true;
		return c.charAt(r.length) == "/";
	}

	static function splitSegments(s:String):Array<String> {
		var normSlashes = StringTools.replace(s, "\\", SEP);
		return normSlashes.split(SEP);
	}

	static inline function text(value:PathLike):String {
		return value == null ? "" : Std.string(value);
	}

	static inline function startsWithSep(s:String):Bool {
		return s.length > 0 && (s.charAt(0) == "/" || s.charAt(0) == "\\");
	}

	static inline function endsWithSep(s:String):Bool {
		return s.length > 0 && (s.charAt(s.length - 1) == "/" || s.charAt(s.length - 1) == "\\");
	}

	static function stripTrailingSeps(s:String):String {
		var end = s.length;
		while (end > 1 && (s.charCodeAt(end - 1) == 47 || s.charCodeAt(end - 1) == 92)) end--;
		return end == s.length ? s : s.substr(0, end);
	}

	static inline function isDriveLetter(code:Null<Int>):Bool {
		return code != null && ((code >= 65 && code <= 90) || (code >= 97 && code <= 122));
	}
}
