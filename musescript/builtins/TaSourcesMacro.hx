package musescript.builtins;

#if macro
import haxe.macro.Context;
import haxe.macro.Type;
#end
import haxe.macro.Expr;

/**
 * Compile-time generator for the `ta` toolbelt's per-indicator MuseScript
 * sources (companion to IndicatorRegistryMacro, same directory-scan
 * technique — see musescript/indicators/PORTING.md for why everything in the
 * port workflow is macro-collected rather than hand-listed).
 *
 * For every class in `musescript/indicators/lib/` exposing a
 * `static function spec():IndicatorSpec`, this macro reads the spec's
 * literal `name` / `args` / `ret` fields straight out of the TYPED AST (all
 * ports write them as literals — enforced by convention and by the runtime
 * fallback below never being the common path), pairs them with the class's
 * own doc comment and file name, renders a canonical MuseScript demo
 * strategy via `TaSourceRender` (the ONE renderer shared with the runtime),
 * and bakes the result into the binary as a plain array literal:
 * `{name, sig, source, doc, file}` per indicator.
 *
 * A class whose spec resists literal extraction (computed name, aliased
 * enum, …) is simply skipped here — `TaSources.ensure()` renders it at
 * runtime from the live `IndicatorRegistry` spec with the SAME renderer, so
 * coverage is total either way and the two paths cannot drift.
 */
class TaSourcesMacro {
	static inline var LIB_DIR = "musescript/indicators/lib";
	static inline var LIB_PACK = "musescript.indicators.lib.";

	public static macro function collect():Expr {
		var entries:Array<Expr> = [];
		#if macro
		var dir = resolveLibDir();
		if (dir == null) {
			Context.warning("TaSourcesMacro: lib/ dir not found on classpath; ta sources will be runtime-rendered", Context.currentPos());
			return macro [];
		}
		var files = sys.FileSystem.readDirectory(dir);
		files.sort(Reflect.compare);
		for (f in files) {
			if (!StringTools.endsWith(f, ".hx")) continue;
			var typeName = f.substr(0, f.length - 3);
			var t = try Context.getType(LIB_PACK + typeName) catch (e:Dynamic) null;
			if (t == null) continue;
			switch (t) {
				case TInst(clsRef, _):
					var cls = clsRef.get();
					var specField:Null<ClassField> = null;
					var nativeField:Null<ClassField> = null;
					for (s in cls.statics.get()) {
						if (s.name == "spec") specField = s;
						if (s.name == "nativeSource") nativeField = s;
					}
					if (specField == null) continue;

					var extracted = try extractSpec(specField) catch (e:Dynamic) null;
					if (extracted == null) {
						Context.warning('TaSourcesMacro: could not extract literal spec from $typeName (will render at runtime)', Context.currentPos());
						continue;
					}

					// Optional: a hand-authored `static function nativeSource():String` returning
					// a single string-literal MuseScript reimplementation. Absent on most ports
					// today (opt-in, see TaSourceEntry.nativeSource's doc comment) -- a present but
					// non-literal body (e.g. computed) is left null rather than guessed at.
					var nativeSrc:Null<String> = nativeField != null ? (try stringConst(unwrapReturn(nativeField.expr())) catch (e:Dynamic) null) : null;

					var doc = TaSourceRender.docTitle(cls.doc != null ? cleanDoc(cls.doc) : "");
					var sig = TaSourceRender.sig(extracted.name, extracted.argKinds, extracted.retFields);
					var src = TaSourceRender.source(extracted.name, extracted.argKinds, extracted.retFields, doc, f);
					entries.push(macro {
						name: $v{extracted.name},
						sig: $v{sig},
						source: $v{src},
						doc: $v{doc},
						file: $v{f},
						argKinds: $v{extracted.argKinds},
						nativeSource: $v{nativeSrc}
					});
				default:
			}
		}
		#end
		return macro $a{entries};
	}

	#if macro
	/** Literal name/args/ret pulled from the typed body of `spec()`. */
	static function extractSpec(f:ClassField):Null<{name:String, argKinds:Array<String>, retFields:Null<Array<String>>}> {
		var te = f.expr();
		if (te == null) return null;
		var obj = findSpecObject(te);
		if (obj == null) return null;

		var name:Null<String> = null;
		var argKinds:Null<Array<String>> = null;
		var retFields:Null<Array<String>> = null;
		var sawRet = false;

		for (fld in obj) {
			switch (fld.name) {
				case "name":
					name = stringConst(fld.expr);
				case "args":
					switch (unwrap(fld.expr).expr) {
						case TArrayDecl(items):
							argKinds = [];
							for (it in items) {
								var k = enumCtor(it);
								if (k == null) return null;
								argKinds.push(k.name);
							}
						default: return null;
					}
				case "ret":
					sawRet = true;
					var k = enumCtor(fld.expr);
					if (k == null) return null;
					retFields = k.name == "TObject" ? objectRetFields(k.params) : null;
					if (k.name == "TObject" && retFields == null) return null;
				default:
			}
		}
		if (name == null || argKinds == null || !sawRet) return null;
		return { name: name, argKinds: argKinds, retFields: retFields };
	}

	/** First object literal in the function body carrying a literal `name` field — the spec. */
	static function findSpecObject(te:TypedExpr):Null<Array<{name:String, expr:TypedExpr}>> {
		var found:Null<Array<{name:String, expr:TypedExpr}>> = null;
		function walk(e:TypedExpr):Void {
			if (found != null || e == null) return;
			switch (e.expr) {
				case TObjectDecl(fields):
					var hasName = false, hasArgs = false;
					for (fl in fields) {
						if (fl.name == "name" && stringConst(fl.expr) != null) hasName = true;
						if (fl.name == "args") hasArgs = true;
					}
					if (hasName && hasArgs) {
						found = [for (fl in fields) { name: fl.name, expr: fl.expr }];
						return;
					}
				default:
			}
			haxe.macro.TypedExprTools.iter(e, walk);
		}
		walk(te);
		return found;
	}

	static function unwrap(e:TypedExpr):TypedExpr {
		return switch (e.expr) {
			case TParenthesis(inner) | TCast(inner, _) | TMeta(_, inner): unwrap(inner);
			default: e;
		};
	}

	/** `function nativeSource():String { return "..."; }` (or a bare-expression arrow body) →
	 * the returned expr, so `stringConst` can try to read it as a literal. */
	static function unwrapReturn(te:TypedExpr):TypedExpr {
		return switch (unwrap(te).expr) {
			case TFunction(tf): unwrapReturn(tf.expr);
			case TBlock(es) if (es.length > 0): unwrapReturn(es[es.length - 1]);
			case TReturn(inner) if (inner != null): unwrap(inner);
			default: te;
		};
	}

	static function stringConst(e:TypedExpr):Null<String> {
		return switch (unwrap(e).expr) {
			case TConst(TString(s)): s;
			default: null;
		};
	}

	/** Enum constructor read (`TSeries`) or call (`TObject([...])`) → name + params. */
	static function enumCtor(e:TypedExpr):Null<{name:String, params:Array<TypedExpr>}> {
		var u = unwrap(e);
		return switch (u.expr) {
			case TField(_, FEnum(_, ef)): { name: ef.name, params: [] };
			case TCall(callee, params):
				switch (unwrap(callee).expr) {
					case TField(_, FEnum(_, ef)): { name: ef.name, params: params };
					default: null;
				}
			default: null;
		};
	}

	/** TObject([{name: "k", ty: ...}, ...]) → ["k", ...]. */
	static function objectRetFields(params:Array<TypedExpr>):Null<Array<String>> {
		if (params.length != 1) return null;
		return switch (unwrap(params[0]).expr) {
			case TArrayDecl(items):
				var names:Array<String> = [];
				for (it in items) switch (unwrap(it).expr) {
					case TObjectDecl(fields):
						var n:Null<String> = null;
						for (fl in fields) if (fl.name == "name") n = stringConst(fl.expr);
						if (n == null) return null;
						names.push(n);
					default: return null;
				}
				names;
			default: null;
		};
	}

	/** Same doc normalization BuiltinDocsMacro uses: strip fencing, one line. */
	static function cleanDoc(raw:String):String {
		var out = [];
		for (line in raw.split("\n")) {
			var t = StringTools.trim(line);
			if (StringTools.startsWith(t, "/**")) t = StringTools.trim(t.substr(3));
			if (StringTools.startsWith(t, "*")) t = StringTools.trim(t.substr(1));
			if (StringTools.endsWith(t, "*/")) t = StringTools.trim(t.substr(0, t.length - 2));
			if (t != "") out.push(t);
		}
		return out.join(" ");
	}

	static function resolveLibDir():Null<String> {
		for (cp in Context.getClassPath()) {
			var candidate = (cp == "" ? "" : cp) + LIB_DIR;
			if (sys.FileSystem.exists(candidate) && sys.FileSystem.isDirectory(candidate))
				return candidate;
		}
		if (sys.FileSystem.exists(LIB_DIR) && sys.FileSystem.isDirectory(LIB_DIR)) return LIB_DIR;
		return null;
	}
	#end
}
