package musescript.builtins;

/**
 * Portable, reflection-free string operations shared by interpreted and
 * compiled-JS strategies.
 *
 * Case conversion is deliberately ASCII-only. Other characters are preserved
 * verbatim so behavior does not depend on a host's Unicode tables or locale.
 */
class StringBuiltins {
	public static function len(value:Dynamic):Int {
		return text(value).length;
	}

	public static function slice(value:Dynamic, start:Int, ?end:Int):String {
		var s = text(value);
		var from = normalizeIndex(start, s.length);
		var to = end == null ? s.length : normalizeIndex(end, s.length);
		if (to < from) to = from;
		return s.substr(from, to - from);
	}

	public static function contains(value:Dynamic, needle:Dynamic):Bool {
		return text(value).indexOf(text(needle)) >= 0;
	}

	public static function concat(a:Dynamic, b:Dynamic):String {
		return text(a) + text(b);
	}

	/** Remove leading and trailing ASCII whitespace (space, tab, CR/LF, FF, VT). */
	public static function trim(value:Dynamic):String {
		var s = text(value);
		var start = 0;
		var end = s.length;
		while (start < end && isAsciiWhitespace(s.charCodeAt(start))) start++;
		while (end > start && isAsciiWhitespace(s.charCodeAt(end - 1))) end--;
		return s.substr(start, end - start);
	}

	public static function lower(value:Dynamic):String {
		return asciiCase(text(value), true);
	}

	public static function upper(value:Dynamic):String {
		return asciiCase(text(value), false);
	}

	public static function startsWith(value:Dynamic, prefix:Dynamic):Bool {
		var s = text(value);
		var p = text(prefix);
		return p.length <= s.length && s.substr(0, p.length) == p;
	}

	public static function endsWith(value:Dynamic, suffix:Dynamic):Bool {
		var s = text(value);
		var p = text(suffix);
		return p.length <= s.length && s.substr(s.length - p.length, p.length) == p;
	}

	/**
	 * Find a literal needle at or after start. Negative start values are relative
	 * to the end; the resulting position is clamped to the string bounds.
	 */
	public static function indexOf(value:Dynamic, needle:Dynamic, ?start:Int = 0):Int {
		var s = text(value);
		return s.indexOf(text(needle), normalizeIndex(start, s.length));
	}

	/**
	 * Replace every non-overlapping literal occurrence, left to right.
	 * An empty needle leaves the source unchanged.
	 */
	public static function replace(value:Dynamic, needle:Dynamic, replacement:Dynamic):String {
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
	public static function split(value:Dynamic, separator:Dynamic):Array<String> {
		var s = text(value);
		var sep = text(separator);
		if (sep.length == 0) {
			var units:Array<String> = [];
			for (i in 0...s.length) units.push(s.substr(i, 1));
			return units;
		}
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

	public static function join(values:Array<Dynamic>, separator:Dynamic):String {
		if (values == null || values.length == 0) return "";
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
	public static function toFloat(value:Dynamic):Float {
		if (value == null) return Math.NaN;
		var s = trim(value);
		if (!isDecimal(s)) return Math.NaN;
		return Std.parseFloat(s);
	}

	/** True only for trimmed, ASCII-case-insensitive "true" or the token "1". */
	public static function toBool(value:Dynamic):Bool {
		var s = lower(trim(value));
		return s == "true" || s == "1";
	}

	public static function fromFloat(value:Float):String {
		if (Math.isNaN(value)) return "nan";
		if (!Math.isFinite(value)) return value < 0 ? "-inf" : "inf";
		if (value == 0) return "0";
		return Std.string(value);
	}

	public static function fromBool(value:Bool):String {
		return value ? "true" : "false";
	}

	static inline function text(value:Dynamic):String {
		return value == null ? "" : Std.string(value);
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

	static function isDecimal(s:String):Bool {
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
