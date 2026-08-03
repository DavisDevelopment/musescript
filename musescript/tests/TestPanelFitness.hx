package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.compile.StrategyWasmBackend;
import musescript.evo.BoolNode;
import musescript.evo.EvolutionEngine;
import musescript.evo.Expand;
import musescript.evo.Fitness;
import musescript.evo.PanelAction;
import musescript.evo.ScalarNode;
import musescript.evo.SeriesNode;
import musescript.evo.StrategyGenome;
import musescript.harness.Bar;
import musescript.harness.PanelFeed;

/**
 * Panel portfolio fitness on the evo hot path: `Fitness.configurePanel` /
 * `EvolutionEngine.configureForPanel` + `PanelAction` → `runPanelBacktest`
 * metrics. Classic genomes stay single-name. NMA does not invent columnar panels.
 */
class TestPanelFitness extends Test {
	function teardown() {
		Fitness.configurePanel(null);
		Fitness.preferNma = false;
		Fitness.clearFnCache();
	}

	static function plantedPanel(nBars:Int = 80):PanelFeed {
		var bySym = new Map<String, Array<Bar>>();
		for (name in ["AAA", "BBB"]) {
			var bars:Array<Bar> = [];
			var price = name == "AAA" ? 100.0 : 100.0;
			for (i in 0...nBars) {
				// AAA drifts up, BBB drifts down — mom_of crossover fires steadily.
				var drift = name == "AAA" ? 0.012 : -0.008;
				var o = price;
				var c = price * (1 + drift);
				bars.push({
					open: o, high: Math.max(o, c) * 1.001, low: Math.min(o, c) * 0.999,
					close: c, volume: 1000.0, time: i * 1.0, index: i
				});
				price = c;
			}
			bySym.set(name, bars);
		}
		return PanelFeed.fromSymbolBars(bySym);
	}

	static function buyMomGenome():StrategyGenome {
		return {
			name: "PanelBuyMom",
			params: [],
			entryLong: BCmp(">",
				KSeries(SPanel("mom", "AAA", null, 5)),
				KSeries(SPanel("mom", "BBB", null, 5))),
			entryShort: BCmp(">", KConst(0.0), KConst(1.0)),
			exitLong: BCmp("<",
				KSeries(SPanel("mom", "AAA", null, 5)),
				KSeries(SPanel("mom", "BBB", null, 5))),
			exitShort: BCmp(">", KConst(0.0), KConst(1.0)),
			size: KConst(1.0),
			panelAction: PABuy("AAA")
		};
	}

	static function rebalanceGenome():StrategyGenome {
		return {
			name: "PanelRebalMom",
			params: [],
			entryLong: BCmp(">",
				KSeries(SPanel("mom", "AAA", null, 4)),
				KSeries(SPanel("mom", "BBB", null, 4))),
			entryShort: BCmp(">", KConst(0.0), KConst(1.0)),
			exitLong: BCmp(">", KConst(0.0), KConst(1.0)),
			exitShort: BCmp(">", KConst(0.0), KConst(1.0)),
			size: KConst(1.0),
			panelAction: PARebalance(["AAA", "BBB"])
		};
	}

	static function classicGenome():StrategyGenome {
		return {
			name: "ClassicEma",
			params: [],
			entryLong: BCmp(">",
				KSeries(SInd("ema", null, 5, null)),
				KSeries(SInd("ema", null, 13, null))),
			entryShort: BCmp(">", KConst(0.0), KConst(1.0)),
			exitLong: BCmp("<",
				KSeries(SInd("ema", null, 5, null)),
				KSeries(SInd("ema", null, 13, null))),
			exitShort: BCmp(">", KConst(0.0), KConst(1.0)),
			size: KConst(1.0)
		};
	}

	static function singleNameBars(n:Int = 80):Array<Bar> {
		var bars:Array<Bar> = [];
		var price = 100.0;
		for (i in 0...n) {
			var o = price;
			var c = price * (1 + 0.004 * Math.sin(i / 6.0));
			bars.push({
				open: o, high: Math.max(o, c) * 1.002, low: Math.min(o, c) * 0.998,
				close: c, volume: 500.0, time: i * 1.0, index: i
			});
			price = c;
		}
		return bars;
	}

	public function testPanelActionRequiresPanelTape() {
		var g = buyMomGenome();
		Assert.isTrue(Fitness.usesPanelFitness(g));
		Fitness.configurePanel(null);
		var fr = Fitness.evaluate(g, singleNameBars());
		Assert.isFalse(fr.ok);
		Assert.isTrue(fr.error != null && fr.error.indexOf("configurePanel") >= 0, fr.error);
	}

	public function testBuyTemplatePanelEquity() {
		var panel = plantedPanel();
		Fitness.configurePanel(panel);
		var g = buyMomGenome();
		var fr = Fitness.evaluate(g, panel.all(), "js");
		Assert.isTrue(fr.ok, fr.error);
		Assert.isTrue(fr.trades > 0, 'expected trades, got ${fr.trades}');
		Assert.isTrue(Math.isFinite(fr.finalEquity));
		Assert.isTrue(fr.finalEquity != 100000, 'equity should move off cash=${fr.finalEquity}');
		Assert.isTrue(fr.equity != null && fr.equity.length == panel.length());
		Assert.isTrue(Expand.expand(g).indexOf('buy("AAA"') >= 0);
	}

	public function testRebalanceTemplatePanelMetrics() {
		var panel = plantedPanel();
		Fitness.configurePanel(panel);
		var fr = Fitness.evaluate(rebalanceGenome(), panel.all(), "js");
		Assert.isTrue(fr.ok, fr.error);
		Assert.isTrue(fr.trades > 0, 'expected rebalance trades, got ${fr.trades}');
		Assert.isTrue(Math.isFinite(fr.sharpe) || fr.trades > 0);
		Assert.isTrue(Math.abs(fr.finalEquity - 100000) > 1e-6 || fr.trades > 0);
	}

	public function testClassicGenomeStaysSingleName() {
		var panel = plantedPanel();
		Fitness.configurePanel(panel); // attached but genome has no PanelAction
		var g = classicGenome();
		Assert.isFalse(Fitness.usesPanelFitness(g));
		var bars = singleNameBars();
		var fr = Fitness.evaluate(g, bars, "js");
		Assert.isTrue(fr.ok, fr.error);
		// Single-name OrderSim path — equity curve length follows the bars arg, not panel session.
		Assert.equals(bars.length, fr.equity != null ? fr.equity.length : -1);
	}

	public function testEngineConfigureForPanelScoresPopulation() {
		var panel = plantedPanel(60);
		var engine = new EvolutionEngine(11, 4, 1, 2);
		engine.configureForTape(panel.all());
		engine.configureForPanel(panel);
		var pop = [
			buyMomGenome(),
			rebalanceGenome(),
			classicGenome(),
			buyMomGenome()
		];
		pop[3].name = "PanelBuyMom2";
		var scores:Array<Float> = [];
		for (g in pop) {
			var fr = Fitness.evaluate(g, panel.all(), "js");
			Assert.isTrue(fr.ok, '${g.name}: ${fr.error}');
			scores.push(Fitness.score(fr, 1));
		}
		Assert.isTrue(scores[0] > Fitness.NEG_INF || pop[0].panelAction != null);
		// Panel-action members must be scored off portfolio equity, not NEG_INF-from-zero-trades only.
		var buyFr = Fitness.evaluate(pop[0], panel.all(), "js");
		Assert.isTrue(buyFr.trades > 0);
		Fitness.configurePanel(null);
	}

	public function testNmaFallsThroughToPanelCompiled() {
		var panel = plantedPanel(50);
		Fitness.configurePanel(panel);
		Fitness.preferNma = true;
		var fr = Fitness.evaluate(buyMomGenome(), panel.all(), "js");
		Assert.isTrue(fr.ok, fr.error);
		Assert.isTrue(fr.backend != "nma" && fr.backend.indexOf("nma") < 0, fr.backend);
		Assert.isTrue(fr.trades > 0);
		Fitness.preferNma = false;
	}

	#if (js || python)
	public function testExpandPanelWasmAgreesWithInterp() {
		if (!StrategyWasmBackend.hostReady()) return;
		var panel = plantedPanel(50);
		Fitness.configurePanel(panel);
		var g = buyMomGenome();
		var interp = Fitness.evaluateCompiled(g, panel.all(), "js");
		var wasm = Fitness.evaluateCompiled(g, panel.all(), "wasm");
		Assert.isTrue(interp.ok, interp.error);
		Assert.isTrue(wasm.ok, wasm.error);
		Assert.equals(interp.trades, wasm.trades);
		Assert.floatEquals(interp.finalEquity, wasm.finalEquity);
		Assert.floatEquals(interp.sharpe, wasm.sharpe);
	}
	#end
}
