package musescript.builtins;

typedef StringLike = Dynamic;

/**
 * Portable, reflection-free string operations shared by interpreted and
 * compiled-JS strategies.
 *
 * Case conversion is deliberately ASCII-only. Other characters are preserved
 * verbatim so behavior does not depend on a host's Unicode tables or locale.
 */
class StringBuiltins {
	public static inline function len(value:StringLike):Int {
		return text(value).length;
	}

	public static inline function slice(value:StringLike, start:Int, ?end:Int):String {
		var s = text(value);
		var from = normalizeIndex(start, s.length);
		var to = end == null ? s.length : normalizeIndex(end, s.length);
		if (to < from) to = from;
		return s.substr(from, to - from);
	}

	public static inline function contains(value:StringLike, needle:StringLike):Bool {
		return text(value).indexOf(text(needle)) >= 0;
	}

	public static inline function concat(a:StringLike, b:StringLike):String {
		return text(a) + text(b);
	}

	/** Remove leading and trailing ASCII whitespace (space, tab, CR/LF, FF, VT). */
	public static inline function trim(value:StringLike):String {
		var s = text(value);
		var start = 0;
		var end = s.length;
		while (start < end && isAsciiWhitespace(s.charCodeAt(start))) start++;
		while (end > start && isAsciiWhitespace(s.charCodeAt(end - 1))) end--;
		return s.substr(start, end - start);
	}

	public static inline function lower(value:StringLike):String {
		return asciiCase(text(value), true);
	}

	public static inline function upper(value:StringLike):String {
		return asciiCase(text(value), false);
	}

	public static inline function startsWith(value:StringLike, prefix:StringLike):Bool {
		var s = text(value);
		var p = text(prefix);
		return p.length <= s.length && s.substr(0, p.length) == p;
	}

	public static inline function endsWith(value:StringLike, suffix:StringLike):Bool {
		var s = text(value);
		var p = text(suffix);
		return p.length <= s.length && s.substr(s.length - p.length, p.length) == p;
	}

	/**
	 * Find a literal needle at or after start. Negative start values are relative
	 * to the end; the resulting position is clamped to the string bounds.
	 */
	public static inline function indexOf(value:StringLike, needle:StringLike, ?start:Int = 0):Int {
		var s = text(value);
		return s.indexOf(text(needle), normalizeIndex(start, s.length));
	}

	/**
	 * Replace every non-overlapping literal occurrence, left to right.
	 * An empty needle leaves the source unchanged.
	 */
	public static function replace(value:StringLike, needle:StringLike, replacement:StringLike):String {
		var s = text(value);
		var find = text(needle);
		if (find.length == 0) return s;
		var repl = text(replacement);
		var out = new StringBuf();
		var cursor = 0;
		while (cursor <= s.length) {
			var found = s.indexOf(find, cursor);
			if (found < 0) break;
			out.add(s.substr(cursor, found - cursor));
			out.add(repl);
			cursor = found + find.length;
		}
		out.add(s.substr(cursor));
		return out.toString();
	}

	/**
	 * Split on a literal separator, preserving empty fields (including trailing
	 * fields). An empty separator splits into host string indexing units.
	 */
	public static function split(value:StringLike, separator:StringLike):Array<String> {
		var s = text(value);
		var sep = text(separator);
		if (sep.length == 0) {
			// Split into host string indexing units
			return s.split("");
		}

		/*
		unsure why we're implementing this manually instead of using the built-in String.split, but it seems to be for performance reasons, and to avoid regex overhead. The built-in split can be slower and has different behavior with regex special characters, so this manual implementation ensures consistent behavior across platforms.
		*/
		var out:Array<String> = [];
		var cursor = 0;
		while (true) {
			var found = s.indexOf(sep, cursor);
			if (found < 0) {
				out.push(s.substr(cursor));
				return out;
			}
			out.push(s.substr(cursor, found - cursor));
			cursor = found + sep.length;
		}
	}

	public static inline function join(values:Array<StringLike>, separator:StringLike):String {
		if (values == null || values.length == 0) 
			return "";

		var sep = text(separator);
		var out = new StringBuf();
		for (i in 0...values.length) {
			if (i > 0) out.add(sep);
			out.add(text(values[i]));
		}

		return out.toString();
	}

	/**
	 * Parse a finite decimal accepted by the grammar
	 * `[+-]?(digits[.digits?]|.digits)([eE][+-]?digits)?`.
	 * Invalid input returns NaN.
	 */
	public static function toFloat(value:StringLike):Float {
		if (value == null) return Math.NaN;
		var s = trim(value);
		if (!isDecimal(s)) return Math.NaN;
		return Std.parseFloat(s);
	}

	/** True only for trimmed, ASCII-case-insensitive "true" or the token "1". */
	public static inline function toBool(value: StringLike):Bool {
		var s = lower(trim(value));
		return s == "true" || s == "1";
	}

	public static function fromFloat(value:Float):String {
		if (Math.isNaN(value)) return "nan";
		if (!Math.isFinite(value)) return value < 0 ? "-inf" : "inf";
		if (value == 0) return "0";
		return Std.string(value);
	}

	public static inline function fromBool(value:Bool):String {
		return value ? "true" : "false";
	}

	/**
	 * Restricted mini-format: `{0}` / `{1}` … and `{name}` tokens only.
	 * `values` may be a positional array, a single scalar (`{0}`), or an object
	 * of named fields. Unknown tokens are left unchanged (no printf / locale).
	 */
	public static function fmt(template:StringLike, ?values:Dynamic):String {
		var s = text(template);
		var positional:Array<String> = [];
		var named = new Map<String, String>();
		if (values != null) {
			if (Std.isOfType(values, Array)) {
				var arr:Array<Dynamic> = cast values;
				for (v in arr) positional.push(text(v));
			} else if (isNamedBag(values)) {
				for (k in Reflect.fields(values))
					named.set(k, text(Reflect.field(values, k)));
			} else {
				positional.push(text(values));
			}
		}
		var out = new StringBuf();
		var i = 0;
		while (i < s.length) {
			var c = s.charCodeAt(i);
			if (c == 123 /* { */) {
				var close = s.indexOf("}", i + 1);
				if (close > i + 1) {
					var key = s.substr(i + 1, close - i - 1);
					if (isFmtKey(key)) {
						var repl = lookupFmt(key, positional, named);
						if (repl != null) {
							out.add(repl);
							i = close + 1;
							continue;
						}
					}
				}
			}
			out.addChar(c);
			i++;
		}
		return out.toString();
	}

	static inline function text(value:StringLike):String {
		return value == null ? "" : Std.string(value);
	}

	static function isNamedBag(values:Dynamic):Bool {
		if (values == null || Std.isOfType(values, String) || Std.isOfType(values, Array)) return false;
		#if js
		return js.Syntax.typeof(values) == "object";
		#else
		return Reflect.isObject(values);
		#end
	}

	static function isFmtKey(key:String):Bool {
		if (key.length == 0) return false;
		var code = key.charCodeAt(0);
		if (code != null && code >= 48 && code <= 57) {
			for (i in 0...key.length) {
				var c = key.charCodeAt(i);
				if (c == null || c < 48 || c > 57) return false;
			}
			return true;
		}
		if (!((code >= 65 && code <= 90) || (code >= 97 && code <= 122) || code == 95))
			return false;
		for (i in 1...key.length) {
			var c = key.charCodeAt(i);
			if (c == null) return false;
			if (!((c >= 65 && c <= 90) || (c >= 97 && c <= 122) || (c >= 48 && c <= 57) || c == 95))
				return false;
		}
		return true;
	}

	static function lookupFmt(key:String, positional:Array<String>, named:Map<String, String>):Null<String> {
		var code = key.charCodeAt(0);
		if (code != null && code >= 48 && code <= 57) {
			var idx = Std.parseInt(key);
			if (idx != null && idx >= 0 && idx < positional.length) return positional[idx];
			return null;
		}
		return named.exists(key) ? named.get(key) : null;
	}

	static function normalizeIndex(index:Int, length:Int):Int {
		var n = index < 0 ? length + index : index;
		if (n < 0) return 0;
		if (n > length) return length;
		return n;
	}

	static function asciiCase(s:String, lower:Bool):String {
		var out = new StringBuf();
		for (i in 0...s.length) {
			var code = s.charCodeAt(i);
			if (code == null) continue;
			if (lower && code >= 65 && code <= 90) code += 32;
			else if (!lower && code >= 97 && code <= 122) code -= 32;
			out.addChar(code);
		}
		return out.toString();
	}

	static inline function isAsciiWhitespace(code:Null<Int>):Bool {
		return code == 32 || code == 9 || code == 10 || code == 13 || code == 12 || code == 11;
	}

	public static function isDecimal(s: String):Bool {
		if (s.length == 0) return false;
		var i = 0;
		var code = s.charCodeAt(i);
		if (code == 43 || code == 45) i++;

		var digits = 0;
		while (i < s.length && isDigit(s.charCodeAt(i))) {
			i++;
			digits++;
		}
		if (i < s.length && s.charCodeAt(i) == 46) {
			i++;
			while (i < s.length && isDigit(s.charCodeAt(i))) {
				i++;
				digits++;
			}
		}
		if (digits == 0) return false;

		if (i < s.length && (s.charCodeAt(i) == 101 || s.charCodeAt(i) == 69)) {
			i++;
			if (i < s.length && (s.charCodeAt(i) == 43 || s.charCodeAt(i) == 45)) i++;
			var exponentDigits = 0;
			while (i < s.length && isDigit(s.charCodeAt(i))) {
				i++;
				exponentDigits++;
			}
			if (exponentDigits == 0) return false;
		}
		return i == s.length;
	}

	static inline function isDigit(code:Null<Int>):Bool {
		return code != null && code >= 48 && code <= 57;
	}
}
