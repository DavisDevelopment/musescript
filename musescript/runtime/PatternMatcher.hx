package musescript.runtime;

import musescript.ast.Expr;
import musescript.ast.Const;
import musescript.ast.MatchArm;
import musescript.ast.Pattern;

class PatternMatcher {
	public function new() {
		/* I AM THE ONE WHO MATCHES THE PATTERNS!!!! */
	}

	public function match(value:Dynamic, arms:Array<MatchArm>):MatchResult {
		// boobs
		for (arm in arms) {
			var bindings = new Map<String, Dynamic>();
			var patGuards:Array<Dynamic> = [];
			if (tryPattern(arm.pattern, value, bindings, patGuards)) {
				return {
					matched: true,
					bindings: bindings,
					body: arm.body,
					guard: arm.guard,
					patGuards: patGuards
				};
			}
		}

		// no match, my man
		return { matched: false, bindings: new Map() };
	}

	/**
	 * @param patGuards optional sink for nested `PatGuard` expressions (evaluated by MuseInterp / JS emit)
	 */
	public function tryPattern(
		pat:Pattern,
		value:Dynamic,
		bindings:Map<String, Dynamic>,
		?patGuards:Array<Dynamic>
	):Bool {
		return switch (pat) {
			case PatWild: true;
			case PatLit(c): constEq(c, value);
			case PatBind(name):
				bindings.set(name, value);
				true;
			case PatTyped(name, typeName):
				if (!typeCheck(value, typeName)) return false;
				bindings.set(name, value);
				true;
			case PatObj(fields):
				if (value == null) return false;
				for (f in fields) {
					var fv = Reflect.field(value, f.name);
					if (!tryPattern(f.pat, fv, bindings, patGuards)) return false;
				}
				true;
			case PatArr(items, rest):
				if (!Std.isOfType(value, Array)) return false;
				var arr:Array<Dynamic> = cast value;
				if (rest == null && arr.length != items.length) return false;
				if (rest != null && arr.length < items.length) return false;
				for (i in 0...items.length) {
					if (!tryPattern(items[i], arr[i], bindings, patGuards)) return false;
				}
				if (rest != null) bindings.set(rest, arr.slice(items.length));
				true;
			case PatOr(a, b):
				var tmp = new Map<String, Dynamic>();
				var ga:Array<Dynamic> = [];
				if (tryPattern(a, value, tmp, ga)) {
					for (k => v in tmp) bindings.set(k, v);
					if (patGuards != null) for (g in ga) patGuards.push(g);
					return true;
				}
				tmp = new Map();
				var gb:Array<Dynamic> = [];
				if (tryPattern(b, value, tmp, gb)) {
					for (k => v in tmp) bindings.set(k, v);
					if (patGuards != null) for (g in gb) patGuards.push(g);
					return true;
				}
				false;
			case PatGuard(inner, g):
				if (!tryPattern(inner, value, bindings, patGuards)) return false;
				if (patGuards != null) patGuards.push(g);
				true;
			case PatAs(inner, name):
				if (!tryPattern(inner, value, bindings, patGuards)) return false;
				bindings.set(name, value);
				true;
			case PatTag(tag, args):
				matchTag(tag, args, value, bindings, patGuards);
		};
	}

	function matchTag(
		tag:String,
		args:Array<Pattern>,
		value:Dynamic,
		bindings:Map<String, Dynamic>,
		?patGuards:Array<Dynamic>
	):Bool {
		// are we matching a string-literal?
		if (Std.isOfType(value, String)) {
			// did we match the tag, and are there no args? (string literals can't have args)
			return value == tag && args.length == 0;
		}

		// are we matching a tagged record?
		if (value != null && Reflect.hasField(value, "__tag")) {
			// abort on tag-mismatch or arg-count mismatch
			if (Reflect.field(value, "__tag") != tag) 
				return false;

			// grab them arguments
			var a:Array<Dynamic> = Reflect.field(value, "args");
			if (a == null) 
				a = new Array<Dynamic>();

			// abort on arg-count mismatch
			if (a.length != args.length) 
				return false;

			// match each argument
			for (i in 0...args.length) {
				if (!tryPattern(args[i], a[i], bindings, patGuards)) {
					return false;
				}
			}

			return true;
		}

		// 
		if (value != null && Reflect.hasField(value, "kind")) {
			if (Std.string(Reflect.field(value, "kind")) != tag) 
				return false;
			if (args.length == 0) 
				return true;

			if (args.length == 1) {
				return tryPattern(args[0], value, bindings, patGuards);
			}

			var fields = Reflect.fields(value).filter(f -> f != "kind" && f != "__tag");
			if (fields.length < args.length) 
				return false;

			for (i in 0...args.length) {
				if (!tryPattern(args[i], Reflect.field(value, fields[i]), bindings, patGuards)) {
					return false;
				}
			}

			return true;
		}

		return false;
	}

	inline function constEq(c:Const, value:Dynamic):Bool {
		return switch (c) {
			case CNull: value == null;
			case CBool(b): value == b;
			case CInt(i): value == i;
			case CFloat(f): value == f;
			case CString(s): value == s;
		};
	}

	inline function typeCheck(value:Dynamic, typeName:String):Bool {
		return switch (typeName.toLowerCase()) {
			case "float" | "number": Std.isOfType(value, Float) || Std.isOfType(value, Int);
			case "int" | "integer": Std.isOfType(value, Int);
			case "string": Std.isOfType(value, String);
			case "bool" | "boolean": Std.isOfType(value, Bool);
			case "array": Std.isOfType(value, Array);
			case "series": value != null && Reflect.hasField(value, "get");
			default: true;
		};
	}
}
