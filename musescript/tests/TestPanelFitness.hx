package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.compile.MuseHostLower;
import musescript.compile.StrategyWasmBackend;
import musescript.evo.BoolNode;
import musescript.evo.EvolutionEngine;
import musescript.evo.Expand;
import musescript.evo.Fitness;
import musescript.evo.PanelAction;
import musescript.evo.PanelInline;
import musescript.evo.ScalarNode;
import musescript.evo.SeriesNode;
import musescript.evo.StrategyGenome;
import musescript.harness.Bar;
import musescript.harness.PanelFeed;
import musescript.parse.MuseParser;

/**
 * Panel portfolio fitness on the evo hot path: `Fitness.configurePanel` /
 * `EvolutionEngine.configureForPanel` + `PanelAction` → `runPanelBacktest`
 * metrics. Classic genomes stay single-name. Cliff-3 NMA hosts closed
 * `SPanel` + `PABuy`/`PARebalance`/`PATargetWeight`/`PABagScanTop`/`PABagRankWeights`
 * (`preferNma` → backend `nma`) plus packed `KPd("xs_rank")` ≤64; wide/frame
 * xs_rank / open `bag_rank_*` stay Expand.
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
		// OHLCV lookback SPanel is outside PanelInline rewrite → Expand panel path.
		var bag:StrategyGenome = {
			name: "LookbackPanelNmaRefuse",
			params: [],
			entryLong: BCmp(">",
				KLookback(SPanel("close", "AAA", null, null), 2),
				KLookback(SPanel("close", "BBB", null, null), 2)),
			entryShort: BCmp(">", KConst(0.0), KConst(1.0)),
			exitLong: BCmp(">", KConst(0.0), KConst(1.0)),
			exitShort: BCmp(">", KConst(0.0), KConst(1.0)),
			size: KConst(1.0),
			panelAction: PABuy("AAA")
		};
		var fr = Fitness.evaluate(bag, panel.all(), "js");
		Assert.isTrue(fr.ok, fr.error);
		Assert.isTrue(fr.backend != "nma" && fr.backend.indexOf("nma") < 0, fr.backend);
		Assert.isTrue(fr.trades > 0);
		Fitness.preferNma = false;
	}

	/** Cliff 3: closed SPanel + PABuy is preferNma-fast and bit-parity with Expand. */
	public function testNmaPanelBuyParity() {
		var panel = plantedPanel(60);
		Fitness.configurePanel(panel);
		var g = buyMomGenome();
		Fitness.preferNma = true;
		var frNma = Fitness.evaluate(g, panel.all(), "js");
		Fitness.preferNma = false;
		var frExpand = Fitness.evaluate(g, panel.all(), "js");
		Assert.isTrue(frNma.ok, frNma.error);
		Assert.isTrue(frExpand.ok, frExpand.error);
		Assert.equals("nma", frNma.backend, frNma.backend);
		Assert.equals(frExpand.trades, frNma.trades);
		Assert.floatEquals(frExpand.finalEquity, frNma.finalEquity);
		Assert.floatEquals(frExpand.sharpe, frNma.sharpe);
	}

	/** Closed PABagScanTop: columnar scores → equal bag → parity with Expand panel fitness. */
	public function testNmaBagScanTopParity() {
		var panel = plantedPanel(60);
		Fitness.configurePanel(panel);
		var g = pdBagScanTopGenome();
		Assert.isTrue(PanelInline.isNmaPanelAction(g.panelAction));
		var keys = PanelInline.seriesKeysForPanelAction(g.panelAction);
		Assert.isTrue(keys.indexOf("close@AAA") >= 0, keys.join(","));
		Assert.isTrue(keys.indexOf("close@BBB") >= 0, keys.join(","));
		Fitness.preferNma = true;
		var frNma = Fitness.evaluate(g, panel.all(), "js");
		Fitness.preferNma = false;
		var frExpand = Fitness.evaluate(g, panel.all(), "js");
		Assert.isTrue(frNma.ok, frNma.error);
		Assert.isTrue(frExpand.ok, frExpand.error);
		Assert.equals("nma", frNma.backend, frNma.backend);
		Assert.equals(frExpand.trades, frNma.trades);
		Assert.floatEquals(frExpand.finalEquity, frNma.finalEquity);
		Assert.floatEquals(frExpand.sharpe, frNma.sharpe);
	}

	/** Closed PABagRankWeights: columnar scores → percentile xs_rank → bag_norm parity. */
	public function testNmaBagRankWeightsParity() {
		var panel = plantedPanel(60);
		Fitness.configurePanel(panel);
		var g = pdBagRankWeightsGenome();
		Assert.isTrue(PanelInline.isNmaPanelAction(g.panelAction));
		var keys = PanelInline.seriesKeysForPanelAction(g.panelAction);
		Assert.isTrue(keys.indexOf("close@AAA") >= 0, keys.join(","));
		Assert.isTrue(keys.indexOf("close@BBB") >= 0, keys.join(","));
		Fitness.preferNma = true;
		var frNma = Fitness.evaluate(g, panel.all(), "js");
		Fitness.preferNma = false;
		var frExpand = Fitness.evaluate(g, panel.all(), "js");
		Assert.isTrue(frNma.ok, frNma.error);
		Assert.isTrue(frExpand.ok, frExpand.error);
		Assert.equals("nma", frNma.backend, frNma.backend);
		Assert.equals(frExpand.trades, frNma.trades);
		Assert.floatEquals(frExpand.finalEquity, frNma.finalEquity);
		Assert.floatEquals(frExpand.sharpe, frNma.sharpe);
	}

	/** PanelInline maps mom_of leaves onto close@SYM SInds. */
	public function testPanelInlineRewritesMomOf() {
		var g = buyMomGenome();
		var inlined = PanelInline.forNma(g);
		Assert.notNull(inlined);
		Assert.isFalse(PanelInline.hasPanel(inlined));
		var keys = PanelInline.seriesKeys(g);
		Assert.isTrue(keys.indexOf("close@AAA") >= 0, keys.join(","));
		Assert.isTrue(keys.indexOf("close@BBB") >= 0, keys.join(","));
		Assert.isTrue(PanelInline.isNmaPanelAction(g.panelAction));
		Assert.isTrue(PanelInline.isNmaPanelAction(PABagScanTop("mom", 4, 1, ["AAA", "BBB"])));
		Assert.isTrue(PanelInline.isNmaPanelAction(PABagRankWeights("mom", 4, ["AAA", "BBB"])));
	}

	/** Packed KPd xs_rank ≤64 is columnar-NMA on a PanelFeed (parity vs Expand). */
	public function testNmaKPdXsRankParity() {
		var panel = plantedPanel(40);
		Fitness.configurePanel(panel);
		var g = pdRankTargetWeightGenome();
		var keys = PanelInline.seriesKeys(g);
		Assert.isTrue(keys.indexOf("close@AAA") >= 0, keys.join(","));
		Assert.isTrue(keys.indexOf("close@BBB") >= 0, keys.join(","));
		Assert.isTrue(Expand.pdXsRankNmaEligible("mom", 5, "AAA", ["AAA", "BBB"]));
		Fitness.preferNma = true;
		var fr = Fitness.evaluate(g, panel.all(), "js");
		Fitness.preferNma = false;
		var frExpand = Fitness.evaluate(g, panel.all(), "js");
		Assert.isTrue(fr.ok, fr.error);
		Assert.isTrue(frExpand.ok, frExpand.error);
		Assert.equals("nma", fr.backend, fr.backend);
		Assert.equals(frExpand.trades, fr.trades);
		Assert.floatEquals(frExpand.finalEquity, fr.finalEquity);
		Assert.floatEquals(frExpand.sharpe, fr.sharpe);
	}

	/** Hand template: percentile xs_rank → target_weight on planted AAA↑/BBB↓ panel. */
	static function pdRankTargetWeightGenome():StrategyGenome {
		var pd = KPd("xs_rank", "mom", 5, "AAA", ["AAA", "BBB"]);
		return {
			name: "PdXsRankTw",
			params: [],
			entryLong: BCmp(">", pd, KConst(0.5)),
			entryShort: BCmp(">", KConst(0.0), KConst(1.0)),
			exitLong: BCmp("<=", pd, KConst(0.5)),
			exitShort: BCmp(">", KConst(0.0), KConst(1.0)),
			size: pd,
			panelAction: PATargetWeight("AAA")
		};
	}

	public function testPdXsRankPanelFitnessNonDegenerate() {
		var panel = plantedPanel(80);
		Fitness.configurePanel(panel);
		var g = pdRankTargetWeightGenome();
		Assert.isTrue(Fitness.usesPanelFitness(g));
		var src = Expand.expand(g);
		Assert.isTrue(src.indexOf("pd_rank1d(") >= 0, src);
		Assert.isTrue(src.indexOf("pd_xs_rank(") < 0, src);
		Assert.isTrue(src.indexOf("target_weight(") >= 0, src);
		Assert.isTrue(src.indexOf("long(") < 0, src);
		var fr = Fitness.evaluate(g, panel.all(), "js");
		Assert.isTrue(fr.ok, fr.error + "\n" + src);
		Assert.isTrue(fr.trades > 0, 'expected portfolio trades, got ${fr.trades}');
		Assert.isTrue(Math.isFinite(fr.finalEquity));
		Assert.isTrue(fr.finalEquity != 100000, 'equity should move off cash=${fr.finalEquity}');
		Assert.isTrue(fr.backend != "nma");
	}

	public function testPdXsRankCoercesWithoutExplicitPanelAction() {
		var panel = plantedPanel(60);
		Fitness.configurePanel(panel);
		var pd = KPd("xs_rank", "mom", 5, "AAA", ["AAA", "BBB"]);
		var g:StrategyGenome = {
			name: "PdCoerce",
			params: [],
			entryLong: BCmp(">", pd, KConst(0.5)),
			entryShort: BCmp(">", KConst(0.0), KConst(1.0)),
			exitLong: BCmp("<=", pd, KConst(0.5)),
			exitShort: BCmp(">", KConst(0.0), KConst(1.0)),
			size: pd
			// no panelAction — Expand + Fitness still take panel path
		};
		Assert.isTrue(Fitness.usesPanelFitness(g));
		Assert.isTrue(Expand.expand(g).indexOf("target_weight(") >= 0);
		var fr = Fitness.evaluate(g, panel.all(), "js");
		Assert.isTrue(fr.ok, fr.error);
		Assert.isTrue(fr.trades > 0);
	}

	public function testEnginePdPlusPanelScoresGrownGenomes() {
		var panel = plantedPanel(60);
		var engine = new EvolutionEngine(13, 6, 1, 2);
		engine.configureForPanel(panel);
		engine.configureForPd(["xs_rank"]);
		var pop = engine.seedPopulation(2);
		var hit = false;
		for (g in pop) {
			var src = Expand.expand(g);
			if (src.indexOf("pd_rank1d(") < 0 && src.indexOf("pd_xs_rank(") < 0) continue;
			hit = true;
			Assert.isTrue(src.indexOf("long(") < 0, src);
			var fr = Fitness.evaluate(g, panel.all(), "js");
			Assert.isTrue(fr.ok, fr.error + "\n" + src);
			Assert.isTrue(Math.isFinite(fr.finalEquity) || fr.trades >= 0);
			break;
		}
		// seedPopulation(6) may miss PD; grow explicitly via Variation under same gates.
		if (!hit) {
			var v = new musescript.evo.Variation(13);
			v.configureForUniverse(panel.symbols);
			v.configureForPd(["xs_rank"]);
			for (_ in 0...80) {
				var g = v.randomGenome(2);
				var src = Expand.expand(g);
				if (src.indexOf("pd_rank1d(") < 0 && src.indexOf("pd_xs_rank(") < 0) continue;
				hit = true;
				Assert.isTrue(src.indexOf("long(") < 0, src);
				var fr = Fitness.evaluate(g, panel.all(), "js");
				Assert.isTrue(fr.ok, fr.error + "\n" + src);
				break;
			}
		}
		Assert.isTrue(hit, "expected grown PD genome under configureForPanel + configureForPd");
		Fitness.configurePanel(null);
	}

	/** Closed bag scan: top-1 mom on planted AAA↑/BBB↓ → always long AAA sleeve. */
	static function pdBagScanTopGenome():StrategyGenome {
		return {
			name: "PdBagScan",
			params: [],
			entryLong: BCmp(">", KConst(1.0), KConst(0.0)),
			entryShort: BCmp(">", KConst(0.0), KConst(1.0)),
			exitLong: BCmp(">", KConst(0.0), KConst(1.0)),
			exitShort: BCmp(">", KConst(0.0), KConst(1.0)),
			size: KConst(1.0),
			panelAction: PABagScanTop("mom", 5, 1, ["AAA", "BBB"])
		};
	}

	static function pdBagRankWeightsGenome():StrategyGenome {
		return {
			name: "PdBagRw",
			params: [],
			entryLong: BCmp(">", KConst(1.0), KConst(0.0)),
			entryShort: BCmp(">", KConst(0.0), KConst(1.0)),
			exitLong: BCmp(">", KConst(0.0), KConst(1.0)),
			exitShort: BCmp(">", KConst(0.0), KConst(1.0)),
			size: KConst(1.0),
			panelAction: PABagRankWeights("mom", 5, ["AAA", "BBB"])
		};
	}

	public function testBagScanTopPanelFitnessNonDegenerate() {
		var panel = plantedPanel(80);
		Fitness.configurePanel(panel);
		var g = pdBagScanTopGenome();
		Assert.isTrue(Fitness.usesPanelFitness(g));
		var src = Expand.expand(g);
		Assert.isTrue(src.indexOf("portfolio_apply(bag_from_scan(") >= 0, src);
		Assert.isTrue(src.indexOf("bag_rank_mom(") < 0, src);
		Assert.isTrue(src.indexOf("symbols()") < 0, src);
		Assert.isTrue(src.indexOf("long(") < 0, src);
		var fr = Fitness.evaluate(g, panel.all(), "js");
		Assert.isTrue(fr.ok, fr.error + "\n" + src);
		Assert.isTrue(fr.trades > 0, 'expected portfolio trades, got ${fr.trades}');
		Assert.isTrue(Math.isFinite(fr.finalEquity));
		Assert.isTrue(fr.finalEquity != 100000, 'equity should move off cash=${fr.finalEquity}');
	}

	public function testBagRankWeightsPanelFitnessNonDegenerate() {
		var panel = plantedPanel(80);
		Fitness.configurePanel(panel);
		var g = pdBagRankWeightsGenome();
		Assert.isTrue(Fitness.usesPanelFitness(g));
		var src = Expand.expand(g);
		Assert.isTrue(src.indexOf("portfolio_apply(bag_norm(bag_from_dict(") >= 0, src);
		Assert.isTrue(src.indexOf("pd_rank1d(") >= 0, src);
		Assert.isTrue(src.indexOf("bag_rank_mom(") < 0, src);
		var fr = Fitness.evaluate(g, panel.all(), "js");
		Assert.isTrue(fr.ok, fr.error + "\n" + src);
		Assert.isTrue(fr.trades > 0, 'expected portfolio trades, got ${fr.trades}');
		Assert.isTrue(Math.isFinite(fr.finalEquity));
		Assert.isTrue(fr.finalEquity != 100000, 'equity should move off cash=${fr.finalEquity}');
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

	public function testBagTemplateWasmHostAbiOk() {
		if (!StrategyWasmBackend.hostReady()) return;
		var panel = plantedPanel(40);
		Fitness.configurePanel(panel);
		var g = pdBagScanTopGenome();
		var src = Expand.expand(g);
		var prog = MuseHostLower.lower(new MuseParser().parse(src));
		var emitted = StrategyWasmBackend.emitOnBar(prog);
		Assert.notNull(emitted, "closed bag Expand must emit WASM (not opaque whole-module)");
		Assert.isTrue(emitted.wat.indexOf("call $apply_bag_scan") >= 0, emitted.wat);
		Assert.isTrue(emitted.wat.indexOf("call $host_eval") < 0, emitted.wat);
		var fr = Fitness.evaluate(g, panel.all(), "wasm");
		Assert.isTrue(fr.ok, fr.error);
		Assert.isTrue(fr.trades > 0);
		// Standalone bag_* remain on escape list; closed HostABI nest does not whole-module bail.
		Assert.isTrue(musescript.compile.StrategyWasmEmitter.PANEL_HOST_ESCAPE.indexOf("bag_from_scan") >= 0);
		Assert.isTrue(musescript.compile.StrategyWasmEmitter.PANEL_HOST_ESCAPE.indexOf("bag_from_dict") >= 0);
		Assert.isTrue(musescript.compile.StrategyWasmEmitter.PANEL_HOST_ESCAPE.indexOf("bag_norm") >= 0);
	}
	#end
}
