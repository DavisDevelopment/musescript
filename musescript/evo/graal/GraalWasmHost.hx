package musescript.evo.graal;

import java.NativeArray;
import musescript.evo.graal.Polyglot;
import musescript.evo.graal.HostProxies;
import musescript.harness.Bar;
import musescript.harness.OrderSim;
import musescript.harness.Metrics;
import musescript.harness.BacktestResult;
import musescript.compile.StrategyWasmRuntimeWat;

/**
 * GraalWasm host for MuseScript strategy modules (memory ABI, preloaded mode).
 * Contexts can share one Engine so Truffle code caches persist across threads.
 * Host imports are side-effects only: get_param / long / short / flat / chart no-ops.
 */
class GraalWasmHost {
	public var engine:Engine;
	public var ctx:Context;
	var ownsEngine:Bool;

	/** Pass a shared Engine to share Truffle code caches across per-thread contexts. */
	public function new(?sharedEngine:Engine, ?options:Map<String, String>) {
		ownsEngine = sharedEngine == null;
		if (ownsEngine) {
			var b = Engine.newBuilder(strArr(["wasm"])).allowExperimentalOptions(true);
			if (options != null)
				for (k in options.keys()) b.option(k, options.get(k));
			engine = b.build();
		} else {
			engine = sharedEngine;
		}
		ctx = Context.newBuilder(strArr(["wasm"])).engine(engine).build();
	}

	public function close():Void {
		ctx.close();
		if (ownsEngine) engine.close();
	}

	public function loadModuleFile(path:String):Value {
		var src = Source.newBuilder("wasm", new JFile(path)).build();
		return ctx.eval(src);
	}

	public function instantiate(module:Value, strings:Array<String>):StrategyInstance {
		return new StrategyInstance(module, strings);
	}

	/** One-shot convenience: instantiate + single preloaded backtest. */
	public function runPreloaded(
		module:Value, strings:Array<String>, bars:Array<Bar>, params:Map<String, Float>
	):BacktestResult {
		return new StrategyInstance(module, strings).run(bars, params);
	}

	public static function strArr(a:Array<String>):NativeArray<String> {
		var out = new NativeArray<String>(a.length);
		for (i in 0...a.length) out[i] = a[i];
		return out;
	}

	public static function objArr(a:Array<Dynamic>):NativeArray<Dynamic> {
		var out = new NativeArray<Dynamic>(a.length);
		for (i in 0...a.length) out[i] = a[i];
		return out;
	}
}

/**
 * Persistent instantiation of one strategy module.
 * The OHLCV tape is packed into linear memory once; each run() swaps in a fresh
 * OrderSim, re-runs configure_tape (which resets bar_count + cross state), and
 * replays the tape. Reusing the instance keeps Truffle profiles monomorphic and
 * removes instantiation + memory-packing cost from the hot path.
 */
class StrategyInstance {
	var exports:Value;
	var onBar:Value;
	var configure:Value;
	var strings:Array<String>;

	var sim:OrderSim;
	var params:Map<String, Float>;
	var curClose:Float;

	var packedN:Int = -1;
	var bases:Array<Int>;
	var featureBase:Int = 0;
	var packedFeatureCount:Int = 0;

	public function new(module:Value, strings:Array<String>) {
		this.strings = strings;
		this.params = new Map();
		this.sim = new OrderSim();
		this.curClose = Math.NaN;

		var members = new Map<String, Dynamic>();
		members.set("get_param", new HostFn(function(a:NativeArray<Value>):Dynamic {
			var id = a[0].asInt();
			var name = id >= 0 && id < this.strings.length ? this.strings[id] : "";
			var v:Float = this.params.exists(name) ? this.params.get(name) : 0.0;
			return v;
		}));
		members.set("long", new HostFn(function(a:NativeArray<Value>):Dynamic {
			var q = a[0].asDouble();
			this.sim.long(this.curClose, Math.isNaN(q) ? null : q);
			return null;
		}));
		members.set("short", new HostFn(function(a:NativeArray<Value>):Dynamic {
			var q = a[0].asDouble();
			this.sim.short(this.curClose, Math.isNaN(q) ? null : q);
			return null;
		}));
		members.set("flat", new HostFn(function(a:NativeArray<Value>):Dynamic {
			this.sim.flat(this.curClose);
			return null;
		}));
		// EMA-family indicators (StrategyWasmEmitter.hx:143) need `exp` for their
		// alpha-decay math -- missing here because this host was only ever exercised
		// against EvoBench's SMA-crossover baseline before the corpus-seeded evolution
		// run pulled in EMA-based genomes (both from the tournament corpus and the
		// `ta` registry's indicator seeds) and hit "env does not contain exp" at
		// instantiate time. get_position/get_entry_price/get_bars_in_trade/get_cash/
		// get_equity/get_unrealized_pnl/host_eval are the OTHER possible env imports
		// (see StrategyWasmEmitter's needImport call sites) but are onPosition-only /
		// class-method-only -- StrategyGenome has no onPosition concept, so genome-
		// expanded source never emits those and they're left unimplemented here.
		members.set("exp", new HostFn(function(a:NativeArray<Value>):Dynamic {
			return Math.exp(a[0].asDouble());
		}));
		for (noop in ["plot", "plotshape", "hline", "bgcolor"])
			members.set(noop, new HostFn(function(a:NativeArray<Value>):Dynamic return null));

		var importRoot = new Map<String, Dynamic>();
		importRoot.set("env", new EnvProxy(members));

		var instance = module.newInstance(GraalWasmHost.objArr([new EnvProxy(importRoot)]));
		exports = instance.getMember("exports");
		onBar = exports.getMember("on_bar");
		configure = exports.getMember("configure_tape");
	}

	function pack(bars:Array<Bar>, ?featureTapes:Array<Array<Float>>):Void {
		var n = bars.length;
		if (n <= 0) n = 1;
		var featureCount = featureTapes != null ? featureTapes.length : 0;
		var stateBytes = StrategyWasmRuntimeWat.STATE_BYTES;
		var bytesNeeded = stateBytes + n * (7 + featureCount) * 8;
		exports.getMember("ensure_capacity").execute(GraalWasmHost.objArr([bytesNeeded]));

		// Re-acquire memory after possible growth.
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
		featureBase = stateBytes + n * 7 * 8;
		packedFeatureCount = featureCount;
		if (featureTapes != null) {
			for (fid in 0...featureTapes.length) {
				var tape = featureTapes[fid];
				for (i in 0...bars.length) {
					var v = i < tape.length ? tape[i] : Math.NaN;
					memory.writeBufferDouble(le, haxe.Int64.ofInt(featureBase + (fid * n + i) * 8), v);
				}
			}
		}
		packedN = n;
	}

	public function run(bars:Array<Bar>, params:Map<String, Float>):BacktestResult {
		return runWithFeatures(bars, params, null);
	}

	public function runWithFeatures(
		bars:Array<Bar>,
		params:Map<String, Float>,
		?featureTapes:Array<Array<Float>>
	):BacktestResult {
		this.params = params;
		this.sim = new OrderSim();
		var wantN = Std.int(Math.max(1, bars.length));
		var wantFeatures = featureTapes != null ? featureTapes.length : 0;
		if (packedN != wantN || packedFeatureCount != wantFeatures || featureTapes != null) pack(bars, featureTapes);

		configure.execute(GraalWasmHost.objArr([
			bases[0], bases[1], bases[2], bases[3], bases[4], bases[5], bases[6], packedN
		]));
		if (exports.hasMember("configure_features"))
			exports.getMember("configure_features").execute(GraalWasmHost.objArr([
				featureTapes != null ? featureBase : 0,
				featureTapes != null ? packedFeatureCount : 0
			]));

		var arg:NativeArray<Dynamic> = new NativeArray(1);
		for (i in 0...bars.length) {
			curClose = bars[i].close;
			arg[0] = i;
			onBar.execute(arg);
			sim.mark(bars[i].close);
		}

		var rets = Metrics.returnsFromEquity(sim.equity);
		return {
			equity: sim.equity,
			returns: rets,
			trades: sim.trades,
			sharpe: Metrics.sharpe(rets),
			maxDrawdown: Metrics.maxDrawdown(sim.equity),
			winRate: Metrics.winRate(sim.wins, sim.trades),
			finalEquity: sim.equity.length > 0 ? sim.equity[sim.equity.length - 1] : sim.cash
		};
	}
}
