package musescript.compile;

import musescript.ast.MuseProgram;
import musescript.BarStrategyFn;
import musescript.harness.HarnessContext;
import musescript.harness.BarFeed;
import musescript.interp.MuseInterp;

/**
 * Compile MuseProgram to a runnable strategy via on-bar Haxe source emission.
 *
 * Emits real Haxe for the JsEmitter-supported on-bar subset (see HaxeEmitter).
 * Execution uses MuseInterp until an AOT compile/load path is wired.
 */
class HaxeBackend {
	public static function compile(prog:MuseProgram):BarStrategyFn {
		var src = new HaxeEmitter().emitOnBar(prog);
		return function(ctx:Dynamic):Dynamic {
			var harness:HarnessContext =
				Std.isOfType(ctx, HarnessContext) ? cast ctx : new HarnessContext();
			var feed:BarFeed = Reflect.hasField(ctx, "feed")
				? Reflect.field(ctx, "feed")
				: BarFeed.synthetic(200, 1);

			var seed = new MuseInterp(harness);
			for (d in prog.decls) seed.registerDeclPublic(d);

			if (src == null)
				trace('HaxeBackend: on-bar emit unsupported for this program — MuseInterp fallback');

			return new MuseInterp(harness).runBacktest(prog, feed);
		};
	}

	/** Expose last emitted Haxe on-bar source for benchmarks / AOT integration */
	public static function emitSource(prog:MuseProgram):Null<String> {
		return new HaxeEmitter().emitOnBar(prog);
	}
}
