package musescript.evo;

import musescript.harness.Bar;
#if js
import js.lib.Atomics;
#end

/**
 * Node `worker_threads` fitness fan-out — the V8 twin of JVM `AttrPool` / fb workers for the
 * population score barrier (`scoreMs`) and attribution oracle batches mid-`step`.
 *
 * Design (JIT guide §37):
 *  - Persistent workers, each with its own V8 isolate (no shared mutable NMA statics).
 *  - Tape(s) + Fitness knobs arrive once via `workerData` (structured-clone at spawn).
 *  - **Resident genome store:** each unique structural key gets a dense int id; JSON wire runs
 *    only on first sighting (`put`). Score jobs send id lists through a SharedArrayBuffer
 *    `Int32Array` — no per-gen full-pop serialize. Haxe enums still cannot structured-clone.
 *  - Scores return through a SharedArrayBuffer `Float64Array` + `Atomics.wait`/`notify` so the
 *    bench stays a synchronous Haxe `main`.
 *  - Structural-key dedup (CorpusEvoRun's clone collapse) runs before fan-out.
 *  - `--threads 1` never spins workers — inline sequential path.
 *  - Optional attr tape: `scoreAll(..., useAttrTape=true)` for `AttrPool` ablation batches (short
 *    `--attr-bars` slice) without standing up a second pool.
 *
 * Determinism: each unique genome's score is independent, so same `--seed` + same pop yields the
 * same fitness vector regardless of `--threads`. `popMemoHits` is partition-dependent (per-isolate
 * memo) and is **not** bit-stable across thread counts. Dirty-spine is refused when workers > 1.
 *
 * «πολλοὶ θύρσοι· ἓν μέλος, οὐ μία μνήμη.»
 */
class NmaNodeEvalPool {
	public static var current:Null<NmaNodeEvalPool> = null;

	/**
	 * Bucket F2: multi-worker JSON wire cannot round-trip Haxe enums inside `ProjectionDecl`
	 * (PSHost / PSPoint / …). Host genomes must NEVER be silently stripped of projections.
	 * Returns true when a genome is safe for the worker JSON path.
	 */
	public static function isWorkerJsonSafe(g:StrategyGenome):Bool {
		return g.projections == null || g.projections.length == 0;
	}

	/** Throw if any genome would lose projections on the worker path. */
	public static function assertWorkerJsonSafe(gs:Array<StrategyGenome>):Void {
		for (g in gs) {
			if (!isWorkerJsonSafe(g)) {
				var n = g.name != null ? g.name : "?";
				throw 'NmaNodeEvalPool: genome "$n" declares projections — worker JSON cannot round-trip'
					+ ' enum samplers; refuse silent strip (use --threads 1 / --ew-host single-thread)';
			}
		}
	}

	public final workers:Int;
	/** Last scoreAll main-thread put/JSON wire time (ms); 0 when inline or cache-hot. */
	public var lastSerMs:Float = 0;
	/** Last scoreAll Atomics.wait time after posts (ms); 0 when inline. */
	public var lastWaitMs:Float = 0;
	/** Uniques scored in the last scoreAll (after structural-key dedup). */
	public var lastUnique:Int = 0;
	/** Genomes JSON-put in the last scoreAll (0 = fully resident). */
	public var lastPutCount:Int = 0;

	#if (js && nodejs)
	var workerHandles:Array<Dynamic>;
	var scoresSab:js.lib.SharedArrayBuffer;
	var scoresView:js.lib.Float64Array;
	var idsSab:js.lib.SharedArrayBuffer;
	var idsView:js.lib.Int32Array;
	var syncSab:js.lib.SharedArrayBuffer;
	var syncView:js.lib.Int32Array;
	var capacity:Int;
	var idCap:Int;
	var scriptPath:String;
	var bars:Array<Bar>;
	var attrBars:Array<Bar>;
	/** structuralKey → dense resident id (main-side mirror of worker stores). */
	var keyToId:Map<String, Int>;
	var nextGenomeId:Int;
	/** Cached JSON fragment per id (avoids re-walking enum trees on rare re-put). */
	var idWireJson:Map<Int, String>;
	#end

	function new(workers:Int) {
		this.workers = workers < 1 ? 1 : workers;
		#if (js && nodejs)
		workerHandles = [];
		capacity = 0;
		idCap = 0;
		scoresSab = new js.lib.SharedArrayBuffer(8);
		scoresView = new js.lib.Float64Array(scoresSab);
		idsSab = new js.lib.SharedArrayBuffer(4);
		idsView = new js.lib.Int32Array(idsSab);
		syncSab = new js.lib.SharedArrayBuffer(6 * 4);
		syncView = new js.lib.Int32Array(syncSab);
		scriptPath = "";
		bars = [];
		attrBars = [];
		keyToId = new Map();
		nextGenomeId = 0;
		idWireJson = new Map();
		#end
	}

	/** True when this JS isolate was spawned as an NMA eval worker. */
	public static function isWorkerThread():Bool {
		#if (js && nodejs)
		try {
			var wt:Dynamic = js.Lib.require("worker_threads");
			return wt.isMainThread != true && wt.workerData != null && wt.workerData.role == "nma-eval";
		} catch (_:Dynamic) {
			return false;
		}
		#else
		return false;
		#end
	}

	/** Worker-isolate entry — arm Fitness, then serve put/score jobs until stop. */
	public static function runWorker():Void {
		#if (js && nodejs)
		var wt:Dynamic = js.Lib.require("worker_threads");
		var data:Dynamic = wt.workerData;
		var bars:Array<Bar> = cast data.bars;
		var attrBars:Array<Bar> = data.attrBars != null ? cast data.attrBars : bars;
		applyFitnessOpts(data.opts);
		Fitness.preferNma = true;
		Fitness.nmaDirtySpine = false;
		Fitness.nmaWorking = null;
		Fitness.beginNmaPopMemo();

		// Dense id → genome; grows monotonically for the life of the worker.
		var store:Array<StrategyGenome> = [];

		var port:Dynamic = wt.parentPort;
		port.on("message", function(msg:Dynamic) {
			if (msg == null) return;
			if (msg.t == "stop") {
				try port.close() catch (_:Dynamic) {}
				return;
			}
			try {
				if (msg.t == "put") {
					var items:Array<Dynamic> = cast js.Syntax.code("JSON.parse({0})", msg.genomesJson);
					var p = 0;
					while (p < items.length) {
						var item = items[p];
						var id:Int = item.id;
						while (store.length <= id) store.push(null);
						store[id] = cast item.g;
						p++;
					}
					var putSync = new js.lib.Int32Array(msg.syncSab);
					Atomics.add(putSync, 1, 1);
					Atomics.notify(putSync, 1, 1);
					return;
				}
				if (msg.t == "scoreEphemeral") {
					var scoresE = new js.lib.Float64Array(msg.scoresSab);
					var syncE = new js.lib.Int32Array(msg.syncSab);
					var gsE:Array<Dynamic> = cast js.Syntax.code("JSON.parse({0})", msg.genomesJson);
					var baseE:Int = msg.base;
					var tapeE:Array<Bar> = msg.useAttr == true ? attrBars : bars;
					if (msg.beginMemo == true)
						Fitness.beginNmaPopMemo();
					var okE = Fitness.nmaOkCount;
					var fallE = Fitness.nmaFallCount;
					var hitsE = Fitness.nmaPopMemoHits;
					var ie = 0;
					while (ie < gsE.length) {
						var gE:StrategyGenome = cast gsE[ie];
						var frE = Fitness.evaluate(gE, tapeE, "js", false);
						scoresE[baseE + ie] = Fitness.score(frE);
						ie++;
					}
					Atomics.add(syncE, 2, Fitness.nmaOkCount - okE);
					Atomics.add(syncE, 3, Fitness.nmaFallCount - fallE);
					Atomics.add(syncE, 4, Fitness.nmaPopMemoHits - hitsE);
					Atomics.add(syncE, 0, 1);
					Atomics.notify(syncE, 0, 1);
					return;
				}
				if (msg.t != "score") return;

				var scores = new js.lib.Float64Array(msg.scoresSab);
				var ids = new js.lib.Int32Array(msg.idsSab);
				var sync = new js.lib.Int32Array(msg.syncSab);
				var base:Int = msg.base;
				var count:Int = msg.count;
				var tape:Array<Bar> = msg.useAttr == true ? attrBars : bars;
				// Inline put: fresh genomes for this sticky owner arrive with the score job
				// (avoids a separate put RTT + double-wait).
				if (msg.genomesJson != null) {
					var items:Array<Dynamic> = cast js.Syntax.code("JSON.parse({0})", msg.genomesJson);
					var p = 0;
					while (p < items.length) {
						var item = items[p];
						var id:Int = item.id;
						while (store.length <= id) store.push(null);
						store[id] = cast item.g;
						p++;
					}
				}
				if (msg.beginMemo == true)
					Fitness.beginNmaPopMemo();

				var ok0 = Fitness.nmaOkCount;
				var fall0 = Fitness.nmaFallCount;
				var hits0 = Fitness.nmaPopMemoHits;
				var i = 0;
				while (i < count) {
					var g = store[ids[base + i]];
					var fr = Fitness.evaluate(g, tape, "js", false);
					scores[base + i] = Fitness.score(fr);
					i++;
				}
				Atomics.add(sync, 2, Fitness.nmaOkCount - ok0);
				Atomics.add(sync, 3, Fitness.nmaFallCount - fall0);
				Atomics.add(sync, 4, Fitness.nmaPopMemoHits - hits0);
				Atomics.add(sync, 0, 1);
				Atomics.notify(sync, 0, 1);
			} catch (e:Dynamic) {
				// Always ack so the main isolate cannot Atomics.wait forever on a thrown eval.
				try {
					js.Syntax.code("console.error('[nma-eval-worker]', {0})", e);
					if (msg.t == "put" && msg.syncSab != null) {
						var ps = new js.lib.Int32Array(msg.syncSab);
						Atomics.add(ps, 1, 1);
						Atomics.notify(ps, 1, 1);
					} else if (msg.syncSab != null) {
						var ss = new js.lib.Int32Array(msg.syncSab);
						Atomics.add(ss, 0, 1);
						Atomics.notify(ss, 0, 1);
					}
				} catch (_:Dynamic) {}
			}
		});

		var ready = new js.lib.Int32Array(data.readySab);
		Atomics.store(ready, 0, 1);
		Atomics.notify(ready, 0, 1);
		#end
	}

	/**
	 * Spin `workers` persistent isolates. `opts` mirrors NmaNodeBench Fitness knobs.
	 * Pass `workers <= 1` to get a pool that never touches worker_threads (inline scoreAll).
	 * `attrBars` (optional) is the short attribution tape; defaults to `bars`.
	 */
	public static function create(workers:Int, bars:Array<Bar>, opts:FitnessOpts, ?attrBars:Array<Bar>):NmaNodeEvalPool {
		var n = workers < 1 ? 1 : workers;
		var pool = new NmaNodeEvalPool(n);
		#if (js && nodejs)
		pool.bars = bars;
		pool.attrBars = attrBars != null ? attrBars : bars;
		if (n <= 1) return pool;

		var wt:Dynamic = js.Lib.require("worker_threads");
		pool.scriptPath = js.Syntax.code("__filename");
		var plainBars = wireBars(bars);
		var plainAttr = attrBars != null && attrBars != bars ? wireBars(attrBars) : plainBars;
		var readySab = new js.lib.SharedArrayBuffer(4);
		var ready = new js.lib.Int32Array(readySab);

		var w = 0;
		while (w < n) {
			Atomics.store(ready, 0, 0);
			var handle:Dynamic = js.Syntax.code("new {0}.Worker({1}, {2})", wt, pool.scriptPath, {
				workerData: {
					role: "nma-eval",
					bars: plainBars,
					attrBars: plainAttr,
					opts: opts,
					readySab: readySab
				}
			});
			pool.workerHandles.push(handle);
			while (Atomics.load(ready, 0) == 0)
				Atomics.wait(ready, 0, 0);
			w++;
		}
		#end
		return pool;
	}

	public function stop():Void {
		#if (js && nodejs)
		for (w in workerHandles) {
			try w.postMessage({t: "stop"}) catch (_:Dynamic) {}
			try w.terminate() catch (_:Dynamic) {}
		}
		workerHandles = [];
		keyToId = new Map();
		idWireJson = new Map();
		nextGenomeId = 0;
		#end
		if (current == this) current = null;
	}

	/**
	 * Score every genome on the pool's tape. Clones (same `Canonical.structuralKey`) share one
	 * eval. When `beginMemo` is true each worker resets its generation-scoped pop memo.
	 * `useAttrTape` selects the short attribution slice (for `AttrPool` mid-step batches).
	 */
	public function scoreAll(gs:Array<StrategyGenome>, beginMemo:Bool = true, useAttrTape:Bool = false):Array<Float> {
		var n = gs.length;
		var out = new Array<Float>();
		out.resize(n);
		if (n == 0) {
			lastUnique = 0;
			lastPutCount = 0;
			return out;
		}

		// CorpusEvoRun's clone collapse: one eval per structural key, scatter to slots.
		var keyToIndices = new Map<String, Array<Int>>();
		var order:Array<String> = [];
		var uniques:Array<StrategyGenome> = [];
		var i = 0;
		while (i < n) {
			var key = Canonical.structuralKey(gs[i]);
			var bucket = keyToIndices.get(key);
			if (bucket == null) {
				bucket = [];
				keyToIndices.set(key, bucket);
				order.push(key);
				uniques.push(gs[i]);
			}
			bucket.push(i);
			i++;
		}
		lastUnique = uniques.length;

		var uniqueScores = scoreUniques(uniques, beginMemo, useAttrTape);
		var u = 0;
		while (u < order.length) {
			var score = uniqueScores[u];
			for (idx in keyToIndices.get(order[u]))
				out[idx] = score;
			u++;
		}
		return out;
	}

	/**
	 * One-shot parallel score without touching the resident store — for AttrPool ablation
	 * batches (genomes that will not be re-scored). JSON-wires the chunk into the score
	 * message (same tax as the pre-resident path, but only for the batch, not the whole pop).
	 */
	public function scoreEphemeral(gs:Array<StrategyGenome>, useAttrTape:Bool = true):Array<Float> {
		var n = gs.length;
		var out = new Array<Float>();
		out.resize(n);
		if (n == 0) return out;

		#if (js && nodejs)
		if (workers <= 1 || workerHandles.length == 0) {
			var tape = useAttrTape ? attrBars : bars;
			var i = 0;
			while (i < n) {
				var fr = Fitness.evaluate(gs[i], tape, "js", false);
				out[i] = Fitness.score(fr);
				i++;
			}
			return out;
		}
		assertWorkerJsonSafe(gs);

		ensureCapacity(n);
		Atomics.store(syncView, 0, 0);
		Atomics.store(syncView, 2, 0);
		Atomics.store(syncView, 3, 0);
		Atomics.store(syncView, 4, 0);

		var chunk = Std.int(Math.max(1, Math.ceil(n / workers)));
		var job = 0;
		var start = 0;
		var tSer0 = haxe.Timer.stamp();
		while (start < n) {
			var end = Std.int(Math.min(n, start + chunk));
			var wired:Array<Dynamic> = [];
			wired.resize(end - start);
			var j = 0;
			while (j < end - start) {
				var g = gs[start + j];
				wired[j] = {
					entryLong: g.entryLong,
					entryShort: g.entryShort,
					exitLong: g.exitLong,
					exitShort: g.exitShort,
					size: g.size,
					params: g.params,
					name: g.name,
					lineage: g.lineage,
					seedOrigin: g.seedOrigin
				};
				j++;
			}
			var genomesJson:String = js.Syntax.code("JSON.stringify({0})", wired);
			workerHandles[job].postMessage({
				t: "scoreEphemeral",
				base: start,
				genomesJson: genomesJson,
				beginMemo: false,
				useAttr: useAttrTape,
				scoresSab: scoresSab,
				syncSab: syncSab
			});
			job++;
			start = end;
		}
		lastSerMs = (haxe.Timer.stamp() - tSer0) * 1000;
		lastPutCount = n;
		var tWait0 = haxe.Timer.stamp();
		var got = Atomics.load(syncView, 0);
		while (got < job) {
			Atomics.wait(syncView, 0, got);
			got = Atomics.load(syncView, 0);
		}
		lastWaitMs = (haxe.Timer.stamp() - tWait0) * 1000;

		var k = 0;
		while (k < n) {
			out[k] = scoresView[k];
			k++;
		}
		Fitness.nmaOkCount += Atomics.load(syncView, 2);
		Fitness.nmaFallCount += Atomics.load(syncView, 3);
		Fitness.nmaPopMemoHits += Atomics.load(syncView, 4);
		return out;
		#else
		throw "NmaNodeEvalPool is Node/js only";
		#end
	}

	function scoreUniques(gs:Array<StrategyGenome>, beginMemo:Bool, useAttrTape:Bool):Array<Float> {
		var n = gs.length;
		var out = new Array<Float>();
		out.resize(n);
		if (n == 0) {
			lastPutCount = 0;
			return out;
		}

		#if (js && nodejs)
		if (workers <= 1 || workerHandles.length == 0) {
			lastSerMs = 0;
			lastWaitMs = 0;
			lastPutCount = 0;
			if (beginMemo) Fitness.beginNmaPopMemo();
			var tape = useAttrTape ? attrBars : bars;
			var i = 0;
			while (i < n) {
				var fr = Fitness.evaluate(gs[i], tape, "js", false);
				out[i] = Fitness.score(fr);
				i++;
			}
			return out;
		}
		assertWorkerJsonSafe(gs);

		var tSer0 = haxe.Timer.stamp();
		var planned = planResident(gs);
		var ids = planned.ids;
		lastPutCount = planned.putCount;
		lastSerMs = (haxe.Timer.stamp() - tSer0) * 1000;

		ensureCapacity(n);
		ensureIdCapacity(n);

		// Partition by sticky owner (id % workers) so each isolate only scores genomes it holds.
		var buckets:Array<Array<Int>> = [for (_ in 0...workers) []];
		var k = 0;
		while (k < n) {
			buckets[ids[k] % workers].push(k);
			k++;
		}

		Atomics.store(syncView, 0, 0);
		Atomics.store(syncView, 2, 0);
		Atomics.store(syncView, 3, 0);
		Atomics.store(syncView, 4, 0);

		var job = 0;
		var w = 0;
		while (w < workers) {
			var slots = buckets[w];
			if (slots.length == 0) {
				w++;
				continue;
			}
			var base = 0;
			var prev = 0;
			while (prev < w) {
				base += buckets[prev].length;
				prev++;
			}
			var s = 0;
			while (s < slots.length) {
				idsView[base + s] = ids[slots[s]];
				s++;
			}
			var freshJson:Null<String> = null;
			if (planned.freshByOwner[w].length > 0)
				freshJson = "[" + planned.freshByOwner[w].join(",") + "]";
			workerHandles[w].postMessage({
				t: "score",
				base: base,
				count: slots.length,
				beginMemo: beginMemo,
				useAttr: useAttrTape,
				genomesJson: freshJson,
				idsSab: idsSab,
				scoresSab: scoresSab,
				syncSab: syncSab
			});
			job++;
			w++;
		}
		var tWait0 = haxe.Timer.stamp();
		var gotScore = Atomics.load(syncView, 0);
		while (gotScore < job) {
			Atomics.wait(syncView, 0, gotScore);
			gotScore = Atomics.load(syncView, 0);
		}
		lastWaitMs = (haxe.Timer.stamp() - tWait0) * 1000;

		// Scatter worker-local score runs back to unique order.
		w = 0;
		while (w < workers) {
			var slots = buckets[w];
			var base = 0;
			var prev = 0;
			while (prev < w) {
				base += buckets[prev].length;
				prev++;
			}
			var s = 0;
			while (s < slots.length) {
				out[slots[s]] = scoresView[base + s];
				s++;
			}
			w++;
		}

		if (beginMemo) {
			Fitness.nmaOkCount = 0;
			Fitness.nmaFallCount = 0;
			Fitness.nmaPopMemoHits = 0;
		}
		Fitness.nmaOkCount += Atomics.load(syncView, 2);
		Fitness.nmaFallCount += Atomics.load(syncView, 3);
		Fitness.nmaPopMemoHits += Atomics.load(syncView, 4);
		return out;
		#else
		throw "NmaNodeEvalPool is Node/js only";
		#end
	}

	#if (js && nodejs)
	/**
	 * Assign dense ids; build per-owner JSON fragments for genomes not yet marked resident
	 * on the main side. Fragments ride with the score message (no separate put barrier).
	 */
	function planResident(gs:Array<StrategyGenome>):{ids:Array<Int>, putCount:Int, freshByOwner:Array<Array<String>>} {
		var n = gs.length;
		var ids = new Array<Int>();
		ids.resize(n);
		var freshByOwner:Array<Array<String>> = [for (_ in 0...workerHandles.length) []];
		var putCount = 0;
		var i = 0;
		while (i < n) {
			var g = gs[i];
			var key = Canonical.structuralKey(g);
			var id = keyToId.get(key);
			if (id == null) {
				id = nextGenomeId++;
				keyToId.set(key, id);
				var frag = idWireJson.get(id);
				if (frag == null) {
					var wired:Dynamic = {
						id: id,
						g: {
							entryLong: g.entryLong,
							entryShort: g.entryShort,
							exitLong: g.exitLong,
							exitShort: g.exitShort,
							size: g.size,
							params: g.params,
							name: g.name,
							lineage: g.lineage,
							seedOrigin: g.seedOrigin
						}
					};
					frag = js.Syntax.code("JSON.stringify({0})", wired);
					idWireJson.set(id, frag);
				}
				freshByOwner[id % workerHandles.length].push(frag);
				putCount++;
			}
			ids[i] = id;
			i++;
		}
		return {ids: ids, putCount: putCount, freshByOwner: freshByOwner};
	}

	function ensureCapacity(n:Int):Void {
		if (n <= capacity) return;
		capacity = n;
		scoresSab = new js.lib.SharedArrayBuffer(n * 8);
		scoresView = new js.lib.Float64Array(scoresSab);
	}

	function ensureIdCapacity(n:Int):Void {
		if (n <= idCap) return;
		idCap = n;
		idsSab = new js.lib.SharedArrayBuffer(n * 4);
		idsView = new js.lib.Int32Array(idsSab);
	}

	static function wireBars(bars:Array<Bar>):Array<Dynamic> {
		var out:Array<Dynamic> = [];
		out.resize(bars.length);
		var i = 0;
		while (i < bars.length) {
			var b = bars[i];
			out[i] = {
				open: b.open,
				high: b.high,
				low: b.low,
				close: b.close,
				volume: b.volume,
				time: b.time,
				index: b.index
			};
			i++;
		}
		return out;
	}

	static function applyFitnessOpts(opts:Dynamic):Void {
		if (opts == null) return;
		Fitness.nmaPopMemoEnabled = opts.popMemo != false;
		Fitness.nmaCostBps = opts.costBps != null ? opts.costBps : 0;
		Fitness.nmaInitialCash = opts.initialCash != null ? opts.initialCash : 100000;
		Fitness.nmaEquityFloor = opts.equityFloor != null ? opts.equityFloor : 0;
		Fitness.attrBandit = opts.attrBandit != false;
		Fitness.creditCuts = opts.creditCuts != false;
		if (opts.periodsPerYear != null && Math.isFinite(opts.periodsPerYear) && opts.periodsPerYear > 0)
			Fitness.setPeriodsPerYear(opts.periodsPerYear);
		else
			Fitness.resetPeriodsPerYear();
	}
	#end
}
