package musescript.evo;

import musescript.harness.Bar;
import musescript.ew.EwForecastHost;
import musescript.ew.ForecastCloud;

/**
 * Boundary X adapter: realizes projection fan-reductions for policy / fitness.
 *
 * Claude's `PSPoint`/`PSNoise` samplers stay SeriesNode-driven (Expand / NmaFitness columns).
 * EW co-evolve uses `PSHost` — this provider asks an `EwForecastHost` for a PIT `ForecastCloud`
 * per bar and maps cloud fields → the same reduction vocabulary (`p50`, `spread`, `prob_up`, …).
 *
 * Hard grammar never crosses this boundary; only soft cloud features do.
 */
class ProjectionProvider {
	var host:Null<EwForecastHost>;
	var clouds:Null<Array<ForecastCloud>>;
	var boundBars:Null<Array<Bar>>;

	public function new(?host:EwForecastHost) {
		this.host = host;
		this.clouds = null;
		this.boundBars = null;
	}

	public function bindHost(h:EwForecastHost):Void {
		host = h;
		invalidate();
	}

	public inline function getHost():Null<EwForecastHost> return host;

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
				// Breach if price range crosses invalidate (either side).
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
		name:String = "ew_0", horizon:Int = 5, hostKind:String = "lattice", seed:Int = 0
	):ProjectionDecl {
		return {
			name: name,
			kind: PLevel,
			horizon: horizon,
			sampler: PSHost(hostKind),
			samples: 1,
			seed: seed
		};
	}

	static inline function finite(x:Float):Bool
		return !Math.isNaN(x) && Math.isFinite(x);
}
