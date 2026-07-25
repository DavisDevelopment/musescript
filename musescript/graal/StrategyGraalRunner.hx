package musescript.graal;

import java.NativeArray;
import musescript.evo.graal.Polyglot;
import musescript.evo.graal.HostProxies;
import musescript.evo.graal.GraalWasmHost;
import musescript.harness.Bar;
import musescript.harness.HarnessContext;
import musescript.harness.OrderSim;
import musescript.harness.ParamRegistry;
import musescript.harness.Metrics;
import musescript.harness.BacktestResult;
import musescript.compile.StrategyWasmRuntimeWat;
import musescript.compile.StrategyWasmEmitter;
import musescript.interp.MuseInterp;
import musescript.parse.MuseParser;
import musescript.ast.Stmt;

/**
 * Full GraalWasm host for a MuseScript strategy, including `host_eval` (escaped-statement
 * fallback, for anything StrategyWasmEmitter couldn't natively lower to WASM) and F2 frame
 * bridging — the two pieces `musescript.evo.graal.GraalWasmHost.StrategyInstance` never wired up
 * (that one only has get_param/long/short/flat/no-op chart). Reuses its exact HostFn/EnvProxy/
 * Polyglot-extern pattern rather than duplicating it.
 *
 * `escapeRegions`/`framedNames` are re-derived deterministically by re-running
 * `StrategyWasmEmitter` on the SAME source the wasm module was compiled from — a pure function
 * of the parsed program, so no serialization format is needed alongside the .wasm artifact.
 *
 * Single source of truth for order state: BOTH native wasm order calls (long/short/flat host
 * imports) AND escaped-interpreter order calls (an escaped statement can itself contain a
 * long/short/flat call — a whole statement escapes together when it ALSO contains something
 * unsupported, even though order calls alone are natively lowerable) route through the SAME
 * `HarnessContext.orders` (a real `OrderSim`, not a hand-ported duplicate) — a strategy that
 * places orders from both paths can never double-count trades or diverge between two
 * independently-tracked positions.
 */
class StrategyGraalRunner {
	var exports:Value;
	var onBar:Value;
	var configure:Value;
	var strings:Array<String>;
	var escapeRegions:Array<Stmt>;
	var framedNames:Map<String, Int>;

	var harness:HarnessContext;
	var interp:MuseInterp;
	var curBar:Bar;

	var packedN:Int = -1;
	var bases:Array<Int>;
	var defaultParams:Map<String, Float>;

	public function new(module:Value, source:String, strings:Array<String>) {
		this.strings = strings;
		harness = new HarnessContext();

		var prog = new MuseParser().parse(source);
		var emitted = new StrategyWasmEmitter().emitOnBar(prog);
		escapeRegions = emitted != null ? emitted.escapeRegions : [];
		framedNames = emitted != null ? emitted.framedNames : new Map();

		interp = new MuseInterp(harness);
		for (d in prog.decls) interp.registerDeclPublic(d);
		// Snapshot declared @param defaults NOW (registerDeclPublic's ParamDecl case already
		// populated harness.params with them) -- run() rebuilds harness.params fresh from this
		// snapshot + that call's caller-supplied overrides every time, so a reused instance
		// (GraalWasmHost.StrategyInstance's documented reuse-across-runs pattern, which this
		// class follows) never leaks one run's param overrides into the next, while still
		// falling back correctly to the DECLARED default for anything a given run doesn't
		// override -- NOT simply replaced with an empty registry (a real bug caught here: an
		// empty override map silently zeroed every @param, discarding its declared default).
		defaultParams = new Map();
		for (k in harness.params.all().keys()) defaultParams.set(k, (harness.params.all().get(k) : Float));

		var members = new Map<String, Dynamic>();
		members.set("get_param", new HostFn(function(a:NativeArray<Value>):Dynamic {
			var id = a[0].asInt();
			var name = id >= 0 && id < this.strings.length ? this.strings[id] : "";
			var all = harness.params.all();
			return all.exists(name) ? (all.get(name) : Float) : 0.0;
		}));
		members.set("long", new HostFn(function(a:NativeArray<Value>):Dynamic {
			var q = a[0].asDouble();
			harness.orders.long(curBar.close, q, curBar.index);
			return null;
		}));
		members.set("short", new HostFn(function(a:NativeArray<Value>):Dynamic {
			var q = a[0].asDouble();
			harness.orders.short(curBar.close, q, curBar.index);
			return null;
		}));
		members.set("flat", new HostFn(function(a:NativeArray<Value>):Dynamic {
			harness.orders.flat(curBar.close, curBar.index);
			return null;
		}));
		members.set("exp", new HostFn(function(a:NativeArray<Value>):Dynamic return Math.exp(a[0].asDouble())));
		members.set("get_position", new HostFn(function(a:NativeArray<Value>):Dynamic return harness.orders.positionSize()));
		members.set("get_entry_price", new HostFn(function(a:NativeArray<Value>):Dynamic return harness.orders.entryPrice));
		members.set("get_bars_in_trade", new HostFn(function(a:NativeArray<Value>):Dynamic
			return (harness.orders.barsInTrade(curBar.index) : Float)));
		members.set("get_cash", new HostFn(function(a:NativeArray<Value>):Dynamic return harness.orders.cash));
		members.set("get_equity", new HostFn(function(a:NativeArray<Value>):Dynamic return harness.orders.equityAt(curBar.close)));
		members.set("get_unrealized_pnl", new HostFn(function(a:NativeArray<Value>):Dynamic return harness.orders.unrealizedPnl(curBar.close)));
		for (noop in ["plot", "plotshape", "hline", "bgcolor"])
			members.set(noop, new HostFn(function(a:NativeArray<Value>):Dynamic return null));

		// F2 frame bridge -- reads/writes the SAME linear-memory f64 slots the native WAT uses
		// for boundary-crossing names (framedNames), via the exported `memory` object. Bound
		// via a mutable ref cell since `memory` isn't available until AFTER instantiation below,
		// but these closures are captured by the interpreter NOW.
		var memRef:Array<Value> = [null];
		function frameGet(off:Int):Float
			return memRef[0].readBufferDouble(ByteOrder.LITTLE_ENDIAN, haxe.Int64.ofInt(off));
		function frameSet(off:Int, v:Float):Void
			memRef[0].writeBufferDouble(ByteOrder.LITTLE_ENDIAN, haxe.Int64.ofInt(off), v);
		var hasFrame = false;
		for (_ in framedNames.keys()) { hasFrame = true; break; }
		if (hasFrame) interp.bindFramePublic(framedNames, frameGet, frameSet);

		members.set("host_eval", new HostFn(function(a:NativeArray<Value>):Dynamic {
			var regionId = a[0].asInt();
			if (regionId >= 0 && regionId < escapeRegions.length)
				interp.runEscapeStmt(curBar, escapeRegions[regionId]);
			return null;
		}));

		var importRoot = new Map<String, Dynamic>();
		importRoot.set("env", new EnvProxy(members));

		var instance = module.newInstance(GraalWasmHost.objArr([new EnvProxy(importRoot)]));
		exports = instance.getMember("exports");
		onBar = exports.getMember("on_bar");
		configure = exports.getMember("configure_tape");
		memRef[0] = exports.getMember("memory");
	}

	function pack(bars:Array<Bar>):Void {
		var n = bars.length;
		if (n <= 0) n = 1;
		var stateBytes = StrategyWasmRuntimeWat.STATE_BYTES;
		var bytesNeeded = stateBytes + n * 7 * 8;
		exports.getMember("ensure_capacity").execute(GraalWasmHost.objArr([bytesNeeded]));

		var memory = exports.getMember("memory");
		var le = ByteOrder.LITTLE_ENDIAN;
		bases = [for (k in 0...7) stateBytes + k * n * 8];
		for (i in 0...bars.length) {
			var b = bars[i];
			var off = i * 8;
			memory.writeBufferDouble(le, haxe.Int64.ofInt(bases[0] + off), b.open);
			memory.writeBufferDouble(le, haxe.Int64.ofInt(bases[1] + off), b.high);
			memory.writeBufferDouble(le, haxe.Int64.ofInt(bases[2] + off), b.low);
			memory.writeBufferDouble(le, haxe.Int64.ofInt(bases[3] + off), b.close);
			memory.writeBufferDouble(le, haxe.Int64.ofInt(bases[4] + off), b.volume);
			memory.writeBufferDouble(le, haxe.Int64.ofInt(bases[5] + off), b.time);
			memory.writeBufferDouble(le, haxe.Int64.ofInt(bases[6] + off), b.index);
		}
		packedN = n;
	}

	public function run(bars:Array<Bar>, params:Map<String, Float>):BacktestResult {
		// TradeBuiltins' crossover/crossunder/rising/falling call-slot state (prevPairs,
		// barCallSlot) is process-wide static, not per-HarnessContext -- GeneRunner.hx's own
		// runOne() resets it before every backtest for exactly this reason (see its call site).
		// Skipping this would leak one run's cross-detection state into the next whenever
		// multiple backtests run in the same process, corrupting results in ways that don't
		// show up as a crash (found via a batch test: a SECOND, unrelated interpreter run
		// immediately after this one produced a nonsense Int32-max "equity" instead of erroring).
		musescript.builtins.TradeBuiltins.resetCrossState();
		harness.params = new ParamRegistry();
		for (k in defaultParams.keys()) harness.params.set(k, defaultParams.get(k));
		for (k in params.keys()) harness.params.set(k, params.get(k));
		harness.orders = new OrderSim();
		var wantN = Std.int(Math.max(1, bars.length));
		if (packedN != wantN) pack(bars);

		configure.execute(GraalWasmHost.objArr([
			bases[0], bases[1], bases[2], bases[3], bases[4], bases[5], bases[6], packedN
		]));

		var arg:NativeArray<Dynamic> = new NativeArray(1);
		for (i in 0...bars.length) {
			curBar = bars[i];
			arg[0] = i;
			onBar.execute(arg);
			harness.orders.mark(bars[i].close);
		}

		// See GraalWasmHost.hx's identical comment -- materialize ONCE, not per call.
		var eqArr = harness.orders.equity.toArray();
		var rets = Metrics.returnsFromEquity(eqArr);
		return {
			equity: eqArr,
			returns: rets,
			trades: harness.orders.trades,
			sharpe: Metrics.sharpe(rets, 0),
			maxDrawdown: Metrics.maxDrawdown(eqArr),
			winRate: Metrics.winRate(harness.orders.wins, harness.orders.trades),
			finalEquity: harness.orders.equity.length > 0
				? harness.orders.equity[harness.orders.equity.length - 1]
				: harness.orders.cash
		};
	}
}
