package musescript.evo;

import musescript.harness.Bar;
import musescript.ew.EwForecastHost;
import musescript.ew.ForecastCloud;
import musescript.ew.LatticeForecastHost;
import musescript.ew.McmcForecastHost;
import musescript.ew.RegimeForecastHost;
import musescript.ew.auction.AuctionForecastHost;
import musescript.ew.auction.VolumeProfile;
import musescript.indicators.ew.EwPhiParams;
import musescript.indicators.geom.SwingGraph;
import musescript.indicators.geom.SwingGraphStack;
import musescript.indicators.offline.PhiParamsDump;

/**
 * Boundary X adapter: realizes projection fan-reductions for policy / fitness.
 *
 * Claude's `PSPoint`/`PSNoise` samplers stay SeriesNode-driven (Expand / NmaFitness columns).
 * EW co-evolve uses `PSHost` — this provider asks an `EwForecastHost` for a PIT `ForecastCloud`
 * per bar and maps cloud fields → the same reduction vocabulary (`p50`, `spread`, `prob_up`, …).
 *
 * Hard grammar never crosses this boundary; only soft cloud features do.
 *
 * Trading path: `decorateBars` writes referenced `Expand.projRef` names into `Bar.data` so Expand's
 * bare identifiers resolve as causal aux series (no prelude shadowing).
 */
class ProjectionProvider {
	var host:Null<EwForecastHost>;
	var clouds:Null<Array<ForecastCloud>>;
	var boundBars:Null<Array<Bar>>;
	var lastBindKey:Null<String> = null;
	var decorateCount:Int = 0;

	/**
	 * When true, `decorateBars` rebuilds a streaming `SwingGraphStack` + host from the genome's
	 * first `PSHost` decl (CorpusEvoRun `--ew-host`). Fresh stack per bind so PIT causality holds
	 * across prefix triage vs full-tape evals.
	 */
	public var autoBindGenomeHost:Bool = false;

	/** Rate-limited `[ew-host]` decorate / cloud console logs (CorpusEvoRun fusion debug). */
	public var logDecorate:Bool = false;

	/** Log every Nth decorate when `logDecorate` (default 12 — rich but greppable). */
	public var logDecorateEvery:Int = 12;

	/** Soft φ keys Variation / genes may touch — tolerances & guideline weights only. */
	public static var SOFT_PHI_KEYS:Array<String> = [
		"fibHitTol", "timeHitTol", "equalityTol",
		"zigzagBMin", "zigzagBMax", "zigzagCMinVsA",
		"flatBNear", "flatBBeyond", "flatCVsA",
		"truncSoftWeight", "truncProjectShrink",
		"alternationWeight", "channelWeight", "throwOverWeight",
		"depthPriorFourthWeight", "equalityOneFiveWeight", "depthIntoPriorFourth"
	];

	public function new(?host:EwForecastHost) {
		this.host = host;
		this.clouds = null;
		this.boundBars = null;
	}

	/** Factory for CorpusEvoRun `--ew-host`: per-genome host rebuild + optional decorate logs. */
	public static function forEvoHost(?log:Bool = true):ProjectionProvider {
		var p = new ProjectionProvider();
		p.autoBindGenomeHost = true;
		p.logDecorate = log;
		return p;
	}

	public function bindHost(h:EwForecastHost):Void {
		host = h;
		invalidate();
	}

	public inline function getHost():Null<EwForecastHost> return host;

	/** Last genome/tape bind key (tests / `[ew-host]` logs). */
	public inline function debugBindKey():Null<String> return lastBindKey;

	/** Drop cached clouds (call after rebinding host / new tape). */
	public function invalidate():Void {
		clouds = null;
		boundBars = null;
	}

	/**
	 * Stream `bars` through the bound host (`onBar` then `cloudAt`) and cache the clouds.
	 * Causal when the host's graph/stack only advances via `onBar`.
	 */
	public function materialize(bars:Array<Bar>):Array<ForecastCloud> {
		if (host == null)
			throw "ProjectionProvider.materialize: no EwForecastHost bound";
		if (clouds != null && boundBars == bars)
			return clouds;
		var out:Array<ForecastCloud> = [];
		for (i in 0...bars.length) {
			host.onBar(bars[i], i);
			out.push(host.cloudAt(i));
		}
		clouds = out;
		boundBars = bars;
		return out;
	}

	/**
	 * Batch snapshot: `cloudAt(t)` for each bar without `onBar` mutation.
	 * For pre-seeded lattice hosts in tests / offline packs. Prefer `materialize` for streaming
	 * PIT causality (graph advances only with bars).
	 */
	public function snapshot(bars:Array<Bar>):Array<ForecastCloud> {
		if (host == null)
			throw "ProjectionProvider.snapshot: no EwForecastHost bound";
		var out:Array<ForecastCloud> = [];
		for (i in 0...bars.length)
			out.push(host.cloudAt(i));
		clouds = out;
		boundBars = bars;
		return out;
	}

	/** Install a precomputed cloud tape (e.g. single-bar smoke from a seeded lattice). */
	public function bindClouds(cs:Array<ForecastCloud>, ?bars:Array<Bar>):Void {
		clouds = cs;
		boundBars = bars;
	}

	public function getClouds():Null<Array<ForecastCloud>> return clouds;

	/** Per-bar reduction column for a ForecastCloud field name. */
	public function fieldColumn(field:String, bars:Array<Bar>):Array<Float> {
		var cs = materialize(bars);
		return [for (c in cs) cloudField(c, field)];
	}

	/**
	 * Map a cloud to the fan-reduction vocabulary shared with `SProj` / Expand.
	 * Unknown fields → NaN (policy mistype fails soft, never invents structure).
	 */
	public static function cloudField(c:ForecastCloud, field:String):Float {
		return switch (field) {
			case "p50", "mean": c.priceMid;
			case "p05": c.priceLo;
			case "p95": c.priceHi;
			case "spread": c.spread;
			case "prob_up": c.probUp;
			case "inv": c.invalidatePrice;
			case "dist_inv": c.distToInvalidation;
			case "entropy": c.countEntropy;
			case "nest": c.nestScore;
			case "top_mass": c.topMass;
			case "label": c.labelCode;
			default: Math.NaN;
		};
	}

	/**
	 * Write referenced host `SProj` reductions into each bar's `data` map under
	 * `Expand.projRef(name, field)` so Expand trading prelude / when-guards read them as aux
	 * series. Returns a shallow-copied bar array (OHLCV shared; `data` maps are new).
	 * Non-host projections are ignored (they expand to MuseScript expressions).
	 */
	public function decorateBars(bars:Array<Bar>, g:StrategyGenome, ?streaming:Bool = false):Array<Bar> {
		if (g.projections == null || g.projections.length == 0) return bars;
		var refs = hostProjRefs(g);
		if (refs.length == 0) return bars;
		if (autoBindGenomeHost)
			bindHostForGenome(g, bars);
		if (host == null)
			throw "ProjectionProvider.decorateBars: no EwForecastHost bound for PSHost genome";
		// Auto-bound hosts always stream (stack advances only via onBar). Explicit streaming=true
		// same path; otherwise reuse snapshot when a caller pre-bound clouds.
		var cs = (streaming || autoBindGenomeHost)
			? materialize(bars)
			: (clouds != null && clouds.length == bars.length ? clouds : snapshot(bars));
		var out:Array<Bar> = [];
		var colNames:Array<String> = [];
		for (r in refs) colNames.push(Expand.projRef(r.name, r.field));
		for (i in 0...bars.length) {
			var b = bars[i];
			var data:Map<String, Float> = b.data != null ? copyMap(b.data) : new Map();
			var c = i < cs.length ? cs[i] : null;
			for (r in refs) {
				var v = c != null ? cloudField(c, r.field) : Math.NaN;
				data.set(Expand.projRef(r.name, r.field), v);
			}
			out.push({
				open: b.open, high: b.high, low: b.low, close: b.close,
				volume: b.volume, time: b.time, index: b.index, data: data
			});
		}
		if (logDecorate) {
			decorateCount++;
			if (decorateCount % logDecorateEvery == 1)
				logDecorateSnapshot(g, bars, cs, colNames);
		}
		return out;
	}

	/**
	 * Rebuild host from genome's first `PSHost` decl + fresh SwingGraphStack over `bars`.
	 * Bind key includes decl digest + tape endpoints so prefix vs full-tape never share stack state.
	 */
	public function bindHostForGenome(g:StrategyGenome, bars:Array<Bar>):Void {
		var decl = firstPsHostDecl(g);
		if (decl == null) return;
		var t0 = bars.length > 0 ? bars[0].time : 0.0;
		var t1 = bars.length > 0 ? bars[bars.length - 1].time : 0.0;
		var key = declDigest(decl) + ":" + bars.length + ":" + t0 + ":" + t1;
		if (key == lastBindKey && host != null && clouds != null && boundBars == bars)
			return;
		var stack = new SwingGraphStack(0.02, 0.05, 16);
		host = hostForDecl(decl, null, stack);
		lastBindKey = key;
		invalidate();
	}

	public static function firstPsHostDecl(g:StrategyGenome):Null<ProjectionDecl> {
		if (g.projections == null) return null;
		for (p in g.projections) {
			switch (p.sampler) {
				case PSHost(_): return p;
				default:
			}
		}
		return null;
	}

	public static function declDigest(decl:ProjectionDecl):String {
		var kind = switch (decl.sampler) {
			case PSHost(k): k;
			default: "?";
		};
		var phi = phiKeyOf(decl.phiDeltas);
		return decl.name + "|" + kind + "|h" + decl.horizon + "|n" + decl.samples
			+ "|s" + decl.seed + "|" + (phi != null ? phi : "-");
	}

	function logDecorateSnapshot(
		g:StrategyGenome, bars:Array<Bar>, cs:Array<ForecastCloud>, colNames:Array<String>
	):Void {
		var mid = bars.length > 0 ? Std.int(bars.length / 2) : 0;
		var c = mid < cs.length ? cs[mid] : null;
		var p50 = c != null ? fmtLog(c.priceMid) : "n/a";
		var p05 = c != null ? fmtLog(c.priceLo) : "n/a";
		var p95 = c != null ? fmtLog(c.priceHi) : "n/a";
		var inv = c != null ? fmtLog(c.invalidatePrice) : "n/a";
		var ent = c != null ? fmtLog(c.countEntropy) : "n/a";
		var rivals = "[]";
		if (host != null && bars.length > 0) {
			var masses = host.topCounts(mid, 5);
			rivals = "[" + [for (m in masses) m.label + ":" + fmtLog(m.mass)].join(",") + "]";
		}
		var gname = g.name != null ? g.name : "?";
		Sys.println('[ew-host] decorate genome=$gname bars=${bars.length} cols=${colNames.join(",")}'
			+ ' cloud@$mid p50=$p50 band=[$p05,$p95] inv=$inv entropy=$ent rivals=$rivals'
			+ ' bind=${lastBindKey != null ? lastBindKey : "-"}');
	}

	static function fmtLog(x:Float):String {
		if (!Math.isFinite(x)) return "n/a";
		return Std.string(Math.round(x * 1000) / 1000);
	}

	/** Referenced (name, field) pairs whose decl is `PSHost`. */
	public static function hostProjRefs(g:StrategyGenome):Array<{name:String, field:String}> {
		var out:Array<{name:String, field:String}> = [];
		if (g.projections == null) return out;
		var byName = new Map<String, ProjectionDecl>();
		for (p in g.projections) byName.set(p.name, p);
		var seen = new Map<String, Bool>();
		function addSeries(s:SeriesNode):Void {
			switch (s) {
				case SPrice(_):
				case SInd(_, _, _, src): if (src != null) addSeries(src);
				case SProj(n, f):
					var decl = byName.get(n);
					if (decl == null) return;
					switch (decl.sampler) {
						case PSHost(_):
							var k = n + "\t" + f;
							if (!seen.exists(k)) {
								seen.set(k, true);
								out.push({ name: n, field: f });
							}
						default:
					}
			}
		}
		function addScalar(sc:ScalarNode):Void {
			switch (sc) {
				case KConst(_) | KParam(_) | KFeature(_):
				case KSeries(s): addSeries(s);
				case KLookback(s, _): addSeries(s);
				case KArith(_, a, b): addScalar(a); addScalar(b);
				case KHole(inner): addScalar(inner);
			}
		}
		function addBool(b:BoolNode):Void {
			switch (b) {
				case BCross(_, a, bb): addSeries(a); addSeries(bb);
				case BCmp(_, a, bb): addScalar(a); addScalar(bb);
				case BTrend(_, s, _): addSeries(s);
				case BAnd(a, bb) | BOr(a, bb): addBool(a); addBool(bb);
				case BNot(a): addBool(a);
				case BHole(inner): addBool(inner);
			}
		}
		addBool(g.entryLong); addBool(g.entryShort); addBool(g.exitLong); addBool(g.exitShort);
		addScalar(g.size);
		return out;
	}

	/**
	 * Apply soft residual deltas onto a cloned `EwPhiParams`. Unknown keys ignored.
	 * Never invents hard-rule constants — only soft pack fields from `PhiParamsDump`.
	 */
	public static function applyPhiDeltas(
		?base:EwPhiParams, ?deltas:Map<String, Float>
	):EwPhiParams {
		var p = (base != null ? base : EwPhiParams.current()).clone();
		if (deltas == null) return p;
		var m = PhiParamsDump.toMap(p);
		for (k => v in deltas) {
			if (!m.exists(k)) continue;
			var cur = m.get(k);
			// Residual: gene stores additive delta on the handbook / prior value.
			m.set(k, cur + v);
		}
		// Clamp positive-ish soft tolerances so MH soft scores stay well-defined.
		inline function clampPos(key:String, lo:Float, hi:Float):Void {
			if (m.exists(key)) m.set(key, Math.max(lo, Math.min(hi, m.get(key))));
		}
		clampPos("fibHitTol", 0.01, 0.5);
		clampPos("timeHitTol", 0.05, 1.0);
		clampPos("equalityTol", 0.01, 0.5);
		clampPos("zigzagBMin", 0.1, 0.9);
		clampPos("zigzagBMax", 0.5, 1.2);
		clampPos("truncSoftWeight", 0.05, 2.0);
		clampPos("channelWeight", 0.05, 2.0);
		return PhiParamsDump.applyMap(m, p);
	}

	/** Stable cache key from soft deltas (null → null). */
	public static function phiKeyOf(deltas:Null<Map<String, Float>>):Null<String> {
		if (deltas == null) return null;
		var keys = [for (k in deltas.keys()) k];
		if (keys.length == 0) return null;
		keys.sort(Reflect.compare);
		return [for (k in keys) k + "=" + deltas.get(k)].join(";");
	}

	/**
	 * Build a lattice or MCMC host for a `PSHost` decl, optionally with a pre-built graph/stack.
	 * Soft φ deltas from the decl are applied; hard grammar stays inside the lattice.
	 */
	public static function hostForDecl(
		decl:ProjectionDecl, ?graph:SwingGraph, ?stack:SwingGraphStack, ?basePhi:EwPhiParams
	):EwForecastHost {
		var kind = switch (decl.sampler) {
			case PSHost(k): k;
			default: throw "ProjectionProvider.hostForDecl: sampler is not PSHost";
		};
		var phi = applyPhiDeltas(basePhi, decl.phiDeltas);
		var key = phiKeyOf(decl.phiDeltas);
		var samples = decl.samples < 1 ? 1 : decl.samples;
		if (kind == "regime") {
			// Non-EW substrate: streams its own returns via onBar (ignores graph/stack). Soft φ deltas
			// don't apply (regime params are its own); horizon carries through from the decl. CHEAP
			// config — a fresh MH chain runs per queried bar, so population eval needs a small budget
			// (benchmark/elite use the richer default via the direct constructor).
			return new RegimeForecastHost(decl.seed, 2, decl.horizon < 1 ? 20 : decl.horizon,
				100, 300, 100, 40, 0.97);
		}
		if (kind == "auction") {
			// Volume-profile fair-value host (parallel session). Streams bars via onBar; volume-at-price
			// drives balance-vs-discovery — a target the price-capture null can't trivially win.
			return new AuctionForecastHost(VolumeProfile.DEFAULT_WINDOW, VolumeProfile.DEFAULT_BINS,
				VolumeProfile.DEFAULT_VALUE_AREA_PCT, decl.horizon < 1 ? 5 : decl.horizon);
		}
		if (kind == "mcmc") {
			var m = stack != null
				? McmcForecastHost.withStack(stack, phi, 5, samples, decl.seed, key)
				: (graph != null
					? McmcForecastHost.withGraph(graph, phi, 5, samples, decl.seed, key)
					: new McmcForecastHost(phi, 5, samples, decl.seed, key));
			return m;
		}
		// Default / "lattice"
		return stack != null
			? LatticeForecastHost.withStack(stack, phi, 5, key)
			: (graph != null
				? LatticeForecastHost.withGraph(graph, phi, 5, key)
				: new LatticeForecastHost(phi, 5, key));
	}

	/**
	 * Interval coverage in [0,1]: fraction of bars where realized `close[t+H]` lands in
	 * `[priceLo, priceHi]`. PIT — uses only clouds already materialised ≤ t and future close
	 * strictly for scoring. `NaN` when no finite bands.
	 */
	public function bandCoverage(bars:Array<Bar>, horizon:Int):Float {
		var h = horizon < 1 ? 1 : horizon;
		var cs = clouds != null ? clouds : materialize(bars);
		var n = cs.length < bars.length ? cs.length : bars.length;
		var ok = 0;
		var tot = 0;
		var t = 0;
		while (t < n - h) {
			var c = cs[t];
			var y = bars[t + h].close;
			if (finite(c.priceLo) && finite(c.priceHi) && finite(y)) {
				tot++;
				if (y >= c.priceLo && y <= c.priceHi)
					ok++;
			}
			t++;
		}
		return tot == 0 ? Math.NaN : ok / tot;
	}

	/**
	 * Invalidation survivability proxy in [0,1]: when `topMass` is high, realized path should not
	 * breach `invalidatePrice` before horizon. Rewards honest invalidate levels, not grammar hacks.
	 */
	public function invalidateSurvive(bars:Array<Bar>, horizon:Int, massGate:Float = 0.5):Float {
		var h = horizon < 1 ? 1 : horizon;
		var cs = clouds != null ? clouds : materialize(bars);
		var n = cs.length < bars.length ? cs.length : bars.length;
		var ok = 0;
		var tot = 0;
		var t = 0;
		while (t < n - h) {
			var c = cs[t];
			if (!(finite(c.topMass) && c.topMass >= massGate && finite(c.invalidatePrice))) {
				t++;
				continue;
			}
			tot++;
			var breached = false;
			var j = t + 1;
			while (j <= t + h) {
				var lo = bars[j].low;
				var hi = bars[j].high;
				var inv = c.invalidatePrice;
				if (lo <= inv && inv <= hi) {
					breached = true;
					break;
				}
				j++;
			}
			if (!breached)
				ok++;
			t++;
		}
		return tot == 0 ? Math.NaN : ok / tot;
	}

	/** Convenience decl for an EW host-backed projection gene. */
	public static function ewDecl(
		name:String = "ew_0", horizon:Int = 5, hostKind:String = "lattice", seed:Int = 0,
		?phiDeltas:Map<String, Float>, samples:Int = 1
	):ProjectionDecl {
		return {
			name: name,
			kind: PLevel,
			horizon: horizon,
			sampler: PSHost(hostKind),
			samples: samples < 1 ? 1 : samples,
			seed: seed,
			phiDeltas: phiDeltas
		};
	}

	static function copyMap(m:Map<String, Float>):Map<String, Float> {
		var out = new Map<String, Float>();
		for (k => v in m) out.set(k, v);
		return out;
	}

	static inline function finite(x:Float):Bool
		return !Math.isNaN(x) && Math.isFinite(x);
}
