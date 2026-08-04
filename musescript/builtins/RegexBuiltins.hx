package musescript.builtins;

/**
 * Portable `muse.re` / `re_*` — ECMAScript-flavored source, JS RegExp + JVM Pattern.
 *
 * Portable flags: `i` `m` `s`. Flag `u` / unicode properties rejected.
 * ReDoS budgets: max pattern/input length + catastrophic nested-quantifier reject.
 */
class RegexBuiltins {
	public static inline var MAX_PATTERN_LEN = 256;
	public static inline var MAX_INPUT_LEN = 1000000;
	public static inline var MAX_FIND_ALL = 10000;
	public static inline var MAX_SPLIT = 10000;

	public static function install(vars:Map<String, Dynamic>):Void {
		vars.set("re_compile", compile);
		vars.set("re_test", test);
		vars.set("re_match", matchOne);
		vars.set("re_find_all", findAll);
		vars.set("re_replace", replace);
		vars.set("re_split", split);
	}

	public static function build():Dynamic {
		var r:Dynamic = {};
		Reflect.setField(r, "compile", compile);
		Reflect.setField(r, "test", test);
		Reflect.setField(r, "match", matchOne);
		Reflect.setField(r, "find_all", findAll);
		Reflect.setField(r, "replace", replace);
		Reflect.setField(r, "split", split);
		return r;
	}

	public static function compile(pattern:Dynamic, ?flags:Dynamic):RePattern {
		var src = text(pattern);
		var fl = flags == null ? "" : text(flags);
		validatePortable(src, fl);
		return RePattern.make(src, normalizeFlags(fl));
	}

	public static function test(pat:Dynamic, s:Dynamic):Bool {
		var p = asPat(pat);
		var input = text(s);
		budgetInput(input);
		return p.test(input);
	}

	/** First match or `null`. Shape: `{ matched, start, end, groups }`. */
	public static function matchOne(pat:Dynamic, s:Dynamic):Null<Dynamic> {
		var p = asPat(pat);
		var input = text(s);
		budgetInput(input);
		return p.matchOne(input);
	}

	public static function findAll(pat:Dynamic, s:Dynamic, ?limit:Dynamic):Array<Dynamic> {
		var p = asPat(pat);
		var input = text(s);
		budgetInput(input);
		var lim = limit == null ? MAX_FIND_ALL : Std.int(limit);
		if (lim < 0) lim = 0;
		if (lim > MAX_FIND_ALL) lim = MAX_FIND_ALL;
		return p.findAll(input, lim);
	}

	public static function replace(pat:Dynamic, s:Dynamic, repl:Dynamic, ?limit:Dynamic):String {
		var p = asPat(pat);
		var input = text(s);
		budgetInput(input);
		var lim = limit == null ? -1 : Std.int(limit);
		return p.replace(input, text(repl), lim);
	}

	public static function split(pat:Dynamic, s:Dynamic, ?limit:Dynamic):Array<String> {
		var p = asPat(pat);
		var input = text(s);
		budgetInput(input);
		var lim = limit == null ? 0 : Std.int(limit);
		// 0 = unlimited (capped), >0 = max parts
		if (lim < 0) lim = 0;
		if (lim == 0 || lim > MAX_SPLIT) lim = MAX_SPLIT;
		return p.split(input, lim);
	}

	static function asPat(pat:Dynamic):RePattern {
		if (Std.isOfType(pat, RePattern)) return cast pat;
		if (Std.isOfType(pat, String)) return compile(pat, "");
		throw "re_*: expected compiled pattern from muse.re.compile";
	}

	static function validatePortable(src:String, flags:String):Void {
		if (src.length == 0) throw "re_compile: empty pattern";
		if (src.length > MAX_PATTERN_LEN)
			throw 're_compile: pattern exceeds $MAX_PATTERN_LEN chars (ReDoS budget)';
		for (i in 0...flags.length) {
			var c = flags.charAt(i);
			if (c == "i" || c == "m" || c == "s") continue;
			if (c == "u" || c == "g" || c == "y" || c == "v" || c == "d")
				throw 're_compile: flag "$c" not in portable subset';
			throw 're_compile: unknown flag "$c"';
		}
		if (src.indexOf("\\p{") >= 0 || src.indexOf("\\P{") >= 0)
			throw "re_compile: unicode properties are not portable";
		if (src.indexOf("(?<") >= 0)
			throw "re_compile: named groups are not portable";
		assertNotCatastrophic(src);
	}

	/** Reject nested quantifiers: `(a+)+`, `(a*)*`, `(x+)?+`, … */
	static function assertNotCatastrophic(src:String):Void {
		var i = 0;
		while (i < src.length) {
			if (src.charAt(i) == "(" && i + 1 < src.length && src.charAt(i + 1) != "?") {
				var depth = 1;
				var j = i + 1;
				var innerQty = false;
				while (j < src.length && depth > 0) {
					var c = src.charAt(j);
					if (c == "\\" && j + 1 < src.length) {
						j += 2;
						continue;
					}
					if (c == "(") depth++;
					else if (c == ")") {
						depth--;
						if (depth == 0) break;
					} else if (depth == 1 && (c == "+" || c == "*" || c == "{")) {
						innerQty = true;
					}
					j++;
				}
				if (depth == 0 && innerQty && j + 1 < src.length) {
					var q = src.charAt(j + 1);
					if (q == "+" || q == "*" || q == "?" || q == "{")
						throw "re_compile: nested quantifiers rejected (ReDoS budget)";
				}
				i = j + 1;
				continue;
			}
			i++;
		}
	}

	static function normalizeFlags(fl:String):String {
		var hasI = false;
		var hasM = false;
		var hasS = false;
		for (k in 0...fl.length) {
			switch (fl.charAt(k)) {
				case "i": hasI = true;
				case "m": hasM = true;
				case "s": hasS = true;
				default:
			}
		}
		var out = "";
		if (hasI) out += "i";
		if (hasM) out += "m";
		if (hasS) out += "s";
		return out;
	}

	static function budgetInput(s:String):Void {
		if (s.length > MAX_INPUT_LEN)
			throw 're_*: input exceeds $MAX_INPUT_LEN chars (ReDoS budget)';
	}

	static inline function text(v:Dynamic):String {
		return v == null ? "" : Std.string(v);
	}
}

/** Opaque compiled pattern. Cross-target: JS RegExp, JVM Pattern, else EReg. */
class RePattern {
	public var source:String;
	public var flags:String;

	#if js
	var re:js.lib.RegExp;
	#elseif java
	var pattern:java.util.regex.Pattern;
	#else
	var ereg:EReg;
	#end

	function new() {}

	public static function make(source:String, flags:String):RePattern {
		var p = new RePattern();
		p.source = source;
		p.flags = flags;
		#if js
		p.re = new js.lib.RegExp(source, flags + "g");
		#elseif java
		var bits = 0;
		if (flags.indexOf("i") >= 0) bits |= java.util.regex.Pattern.CASE_INSENSITIVE;
		if (flags.indexOf("m") >= 0) bits |= java.util.regex.Pattern.MULTILINE;
		if (flags.indexOf("s") >= 0) bits |= java.util.regex.Pattern.DOTALL;
		p.pattern = java.util.regex.Pattern.compile(source, bits);
		#else
		if (flags.indexOf("s") >= 0)
			throw "re_compile: flag s requires js or java target";
		var eflags = "";
		if (flags.indexOf("i") >= 0) eflags += "i";
		if (flags.indexOf("m") >= 0) eflags += "m";
		p.ereg = new EReg(source, eflags);
		#end
		return p;
	}

	public function test(s:String):Bool {
		return matchOne(s) != null;
	}

	public function matchOne(s:String):Null<Dynamic> {
		var all = findAll(s, 1);
		return all.length == 0 ? null : all[0];
	}

	public function findAll(s:String, limit:Int):Array<Dynamic> {
		var out:Array<Dynamic> = [];
		#if js
		re.lastIndex = 0;
		while (out.length < limit) {
			var m = re.exec(s);
			if (m == null) break;
			out.push(packJs(m));
			if (m[0] != null && (m[0] : String).length == 0) re.lastIndex++;
		}
		#elseif java
		var matcher = pattern.matcher(s);
		var from = 0;
		while (out.length < limit && from <= s.length) {
			if (!matcher.find(from)) break;
			out.push(packJava(matcher));
			var end = matcher.end();
			from = end == matcher.start() ? end + 1 : end;
			if (from > s.length) break;
		}
		#else
		var cursor = 0;
		while (out.length < limit && cursor <= s.length) {
			var slice = s.substr(cursor);
			if (!ereg.match(slice)) break;
			var mp = ereg.matchedPos();
			var start = cursor + mp.pos;
			var end = start + mp.len;
			out.push({
				matched: ereg.matched(0),
				start: start,
				end: end,
				groups: eregGroups(ereg)
			});
			cursor = end == start ? end + 1 : end;
		}
		#end
		return out;
	}

	public function replace(s:String, repl:String, limit:Int):String {
		var hits = findAll(s, limit < 0 ? RegexBuiltins.MAX_FIND_ALL : limit);
		if (hits.length == 0) return s;
		var out = new StringBuf();
		var cursor = 0;
		for (h in hits) {
			var start:Int = h.start;
			var end:Int = h.end;
			out.add(s.substring(cursor, start));
			out.add(expandRepl(repl, h));
			cursor = end;
		}
		out.add(s.substring(cursor));
		return out.toString();
	}

	/** Split into at most `limit` parts (last holds the remainder). */
	public function split(s:String, limit:Int):Array<String> {
		if (limit <= 1) return [s];
		var hits = findAll(s, limit - 1);
		if (hits.length == 0) return [s];
		var out:Array<String> = [];
		var cursor = 0;
		for (h in hits) {
			if (out.length >= limit - 1) break;
			out.push(s.substring(cursor, h.start));
			cursor = h.end;
		}
		out.push(s.substring(cursor));
		return out;
	}

	static function expandRepl(repl:String, hit:Dynamic):String {
		var groups:Array<Dynamic> = cast Reflect.field(hit, "groups");
		var matched:String = Reflect.field(hit, "matched");
		var out = new StringBuf();
		var i = 0;
		while (i < repl.length) {
			var c = repl.charCodeAt(i);
			if (c == 36 && i + 1 < repl.length) {
				var n = repl.charCodeAt(i + 1);
				if (n == 36) {
					out.addChar(36);
					i += 2;
					continue;
				}
				if (n == 48) {
					out.add(matched == null ? "" : matched);
					i += 2;
					continue;
				}
				if (n != null && n >= 49 && n <= 57) {
					var idx = n - 49; // $1 → groups[0]
					if (groups != null && idx >= 0 && idx < groups.length && groups[idx] != null)
						out.add(Std.string(groups[idx]));
					i += 2;
					continue;
				}
			}
			out.addChar(c);
			i++;
		}
		return out.toString();
	}

	#if js
	static function packJs(m:Dynamic):Dynamic {
		var groups:Array<String> = [];
		var len:Int = m.length;
		for (i in 1...len) {
			var g:Dynamic = m[i];
			groups.push(g == null ? null : Std.string(g));
		}
		var matched = m[0] == null ? "" : Std.string(m[0]);
		var index:Int = m.index;
		return {
			matched: matched,
			start: index,
			end: index + matched.length,
			groups: groups
		};
	}
	#end

	#if java
	static function packJava(matcher:java.util.regex.Matcher):Dynamic {
		var groups:Array<String> = [];
		var gc = matcher.groupCount();
		for (i in 1...gc + 1) groups.push(matcher.group(i));
		return {
			matched: matcher.group(),
			start: matcher.start(),
			end: matcher.end(),
			groups: groups
		};
	}
	#end

	#if !(js || java)
	static function eregGroups(ereg:EReg):Array<String> {
		var groups:Array<String> = [];
		var i = 1;
		while (i < 100) {
			try {
				groups.push(ereg.matched(i));
				i++;
			} catch (_:Dynamic) {
				break;
			}
		}
		return groups;
	}
	#end
}
