package musescript.evo;

import musescript.harness.Bar;
import musescript.ew.EwForecastHost;
import musescript.ew.ForecastCloud;
import musescript.indicators.geom.PivotPoint;
import musescript.indicators.geom.SwingGraph;

/**
 * Shared demo logic for EW host ↔ evo projection integration (CLI + JVM GUI).
 * Synthetic impulse tape → LatticeForecastHost / McmcForecastHost → decorateBars →
 * Expand/Fitness + projScore. Hard rules stay inside the host.
 */
class HostProjectionDemoCore {
	public static function bullImpulse():Array<PivotPoint> {
		return [
			piv(100, -1, 0),
			piv(110, 1, 10),
			piv(105, -1, 20),
			piv(120, 1, 30),
			piv(112, -1, 40),
			piv(125, 1, 50)
		];
	}

	static function piv(price:Float, dir:Float, bar:Int):PivotPoint {
		return new PivotPoint(price, dir, bar);
	}

	public static function syntheticBars(n:Int = 80):Array<Bar> {
		var bars:Array<Bar> = [];
		for (i in 0...n) {
			var px = 100.0 + i * 0.3;
			bars.push({
				open: px, high: px + 1, low: px - 1, close: px,
				volume: 1000, time: i * 60.0, index: i
			});
		}
		if (n > 50) {
			bars[50].close = 125;
			bars[50].high = 126;
			bars[50].low = 124;
			bars[50].open = 124;
		}
		return bars;
	}

	public static function demoGenome(hostKind:String = "lattice"):StrategyGenome {
		return {
			entryLong: BCmp(">", KSeries(SProj("ew_0", "p50")), KSeries(SPrice("close"))),
			entryShort: BCmp(">", KConst(0.0), KConst(1.0)),
			exitLong: BCmp("<", KSeries(SProj("ew_0", "spread")), KConst(1000.0)),
			exitShort: BCmp(">", KConst(0.0), KConst(1.0)),
			size: KConst(1.0),
			params: [],
			name: "EW_HOST_DEMO",
			lineage: [],
			seedOrigin: null,
			projections: [
				ProjectionProvider.ewDecl(
					"ew_0", 5, hostKind, 1,
					["fibHitTol" => 0.01],
					hostKind == "mcmc" ? 8 : 1
				)
			]
		};
	}

	public static function seededGraph():SwingGraph {
		var g = new SwingGraph(0.02, 16);
		g.seedConfirmed(bullImpulse(), 51);
		return g;
	}

	public static function makeHost(kind:String, graph:SwingGraph):EwForecastHost {
		var decl = ProjectionProvider.ewDecl("ew_0", 5, kind, 1, ["fibHitTol" => 0.01], kind == "mcmc" ? 8 : 1);
		return ProjectionProvider.hostForDecl(decl, graph);
	}

	/** One-shot demo: clouds + decorated eval + projScore. */
	public static function run(hostKind:String = "lattice"):HostProjDemoResult {
		var bars = syntheticBars(80);
		var graph = seededGraph();
		var host = makeHost(hostKind, graph);
		var provider = new ProjectionProvider(host);
		var clouds = provider.snapshot(bars);
		var g = demoGenome(hostKind);
		var src = Expand.expand(g);

		var prev = Fitness.projectionProvider;
		Fitness.projectionProvider = provider;
		var fr = Fitness.evaluate(g, bars, "js");
		Fitness.attachProjectionScore(fr, g, bars, provider);
		Fitness.projectionProvider = prev;

		var c50 = clouds[50];
		return {
			hostKind: hostKind,
			source: src,
			ok: fr.ok,
			error: fr.error,
			sharpe: fr.sharpe,
			trades: fr.trades,
			projScore: fr.projScore,
			cloudMid: c50.priceMid,
			cloudLo: c50.priceLo,
			cloudHi: c50.priceHi,
			cloudSpread: c50.spread,
			cloudInv: c50.invalidatePrice,
			cloudEntropy: c50.countEntropy,
			bars: bars,
			clouds: clouds
		};
	}

	public static function printResult(r:HostProjDemoResult):Void {
		Sys.println('hostKind=${r.hostKind}');
		Sys.println('cloud@50 mid=${r.cloudMid} band=[${r.cloudLo},${r.cloudHi}] spread=${r.cloudSpread}');
		Sys.println('invalidate=${r.cloudInv} entropy=${r.cloudEntropy}');
		Sys.println('eval ok=${r.ok} sharpe=${r.sharpe} trades=${r.trades} projScore=${r.projScore}');
		if (!r.ok) Sys.println('error: ${r.error}');
		Sys.println("--- expanded ---");
		Sys.println(r.source);
	}
}

typedef HostProjDemoResult = {
	var hostKind:String;
	var source:String;
	var ok:Bool;
	var error:Null<String>;
	var sharpe:Float;
	var trades:Int;
	var projScore:Float;
	var cloudMid:Float;
	var cloudLo:Float;
	var cloudHi:Float;
	var cloudSpread:Float;
	var cloudInv:Float;
	var cloudEntropy:Float;
	var bars:Array<Bar>;
	var clouds:Array<ForecastCloud>;
}
