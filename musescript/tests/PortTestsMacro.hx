package musescript.tests;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
#end

/**
 * Compile-time collector for delegated indicator-port test classes. Scans
 * `musescript/tests/ports/` and emits `runner.addCase(new Foo())` for every
 * utest.Test subclass there — so a delegated port batch drops its
 * `tests/ports/TestPortXxx.hx` file and is registered automatically, with NO
 * edit to TestMain.hx. That removes the last shared-file edit from the port
 * workflow (indicators already self-register via IndicatorRegistryMacro), so
 * any number of batches can be ported in parallel with zero merge conflicts.
 * See musescript/indicators/PORTING.md.
 */
class PortTestsMacro {
	public static macro function addAll(runner:Expr):Expr {
		var adds:Array<Expr> = [];
		#if macro
		var dir = resolvePortsDir();
		if (dir != null) {
			var files = sys.FileSystem.readDirectory(dir);
			files.sort(Reflect.compare);
			for (f in files) {
				if (!StringTools.endsWith(f, ".hx")) continue;
				var typeName = f.substr(0, f.length - 3);
				var path = "musescript.tests.ports." + typeName;
				var t = try Context.getType(path) catch (e:Dynamic) null;
				if (t == null) continue;
				switch (t) {
					case TInst(_, _):
						var tpath:TypePath = { pack: ["musescript", "tests", "ports"], name: typeName };
						var inst:Expr = { expr: ENew(tpath, []), pos: Context.currentPos() };
						adds.push(macro $e{runner}.addCase($e{inst}));
					default:
				}
			}
		}
		#end
		return macro $b{adds};
	}

	#if macro
	static function resolvePortsDir():Null<String> {
		var rel = "musescript/tests/ports";
		for (cp in Context.getClassPath()) {
			var candidate = (cp == "" ? "" : cp) + rel;
			if (sys.FileSystem.exists(candidate) && sys.FileSystem.isDirectory(candidate))
				return candidate;
		}
		if (sys.FileSystem.exists(rel) && sys.FileSystem.isDirectory(rel)) return rel;
		return null;
	}
	#end
}
