package musescript.builtins;

import musescript.harness.DiagPack;
import musescript.harness.DiagPackOpts;
import musescript.harness.DiagPackResult;
import musescript.harness.HarnessContext;

/**
 * `muse.diag` / `diag_*` — post-run ACF / kiss-the-curve diagnostics.
 *
 * Emits through the harness {@link musescript.harness.ChartSink}; pure series
 * helpers reuse {@link musescript.harness.Metrics} + {@link StatsBuiltins.autocorr}.
 * Not intended for WASM per-bar hot paths (host_eval / JS / interp only).
 */
class DiagBuiltins {
	public static function install(vars:Map<String, Dynamic>, harness:HarnessContext):Void {
		vars.set("diag_running_max", DiagPack.runningMax);
		vars.set("diag_drawdown", DiagPack.drawdownSeries);
		vars.set("diag_acf", function(xs:Dynamic, ?maxLag:Dynamic)
			return DiagPack.acf(asFloats(xs), intOr(maxLag, DiagPack.DEFAULT_MAX_LAG)));
		vars.set("diag_rolling_acf", function(xs:Dynamic, ?window:Dynamic, ?lag:Dynamic)
			return DiagPack.rollingAcf(asFloats(xs), intOr(window, 40), intOr(lag, 1)));
		vars.set("diag_kiss", function(?equity:Dynamic)
			return summary(DiagPack.emitKiss(harness.chart, resolveEquity(harness, equity))));
		vars.set("diag_underwater", function(?equity:Dynamic)
			return summary(DiagPack.emitUnderwater(harness.chart, resolveEquity(harness, equity))));
		vars.set("diag_pack", function(?equity:Dynamic, ?maxLag:Dynamic, ?rollingWindow:Dynamic) {
			var opts:DiagPackOpts = {
				maxLag: intOrNull(maxLag),
				rollingWindow: intOrNull(rollingWindow)
			};
			return summary(DiagPack.emit(harness.chart, resolveEquity(harness, equity), opts));
		});
	}

	public static function build(harness:HarnessContext):Dynamic {
		var d:Dynamic = {};
		Reflect.setField(d, "running_max", DiagPack.runningMax);
		Reflect.setField(d, "drawdown", DiagPack.drawdownSeries);
		Reflect.setField(d, "acf", function(xs:Dynamic, ?maxLag:Dynamic)
			return DiagPack.acf(asFloats(xs), intOr(maxLag, DiagPack.DEFAULT_MAX_LAG)));
		Reflect.setField(d, "rolling_acf", function(xs:Dynamic, ?window:Dynamic, ?lag:Dynamic)
			return DiagPack.rollingAcf(asFloats(xs), intOr(window, 40), intOr(lag, 1)));
		Reflect.setField(d, "kiss", function(?equity:Dynamic)
			return summary(DiagPack.emitKiss(harness.chart, resolveEquity(harness, equity))));
		Reflect.setField(d, "underwater", function(?equity:Dynamic)
			return summary(DiagPack.emitUnderwater(harness.chart, resolveEquity(harness, equity))));
		Reflect.setField(d, "pack", function(?equity:Dynamic, ?maxLag:Dynamic, ?rollingWindow:Dynamic) {
			var opts:DiagPackOpts = {
				maxLag: intOrNull(maxLag),
				rollingWindow: intOrNull(rollingWindow)
			};
			return summary(DiagPack.emit(harness.chart, resolveEquity(harness, equity), opts));
		});
		return d;
	}

	static function summary(r:DiagPackResult):Dynamic {
		return DiagPack.toSummary(r, false);
	}

	static function resolveEquity(harness:HarnessContext, equity:Dynamic):Array<Float> {
		if (equity != null) return asFloats(equity);
		return harness.orders.equity.toArray();
	}

	static function asFloats(xs:Dynamic):Array<Float> {
		if (xs == null) return [];
		if (Std.isOfType(xs, Array)) {
			var arr:Array<Dynamic> = cast xs;
			return [for (x in arr) (x : Float)];
		}
		return [];
	}

	static function intOr(v:Dynamic, def:Int):Int {
		if (v == null) return def;
		return Std.int(v);
	}

	static function intOrNull(v:Dynamic):Null<Int> {
		if (v == null) return null;
		return Std.int(v);
	}
}
