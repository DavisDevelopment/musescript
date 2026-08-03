package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.evo.BoolNode;
import musescript.evo.EvolutionEngine;
import musescript.evo.Fitness;
import musescript.evo.PanelAction;
import musescript.evo.ScalarNode;
import musescript.evo.SeriesNode;
import musescript.evo.StrategyGenome;
import musescript.harness.Bar;
import musescript.harness.PanelFeed;
import musescript.harness.PanelLoader;
import musescript.runtime.MuseRuntime;

/**
 * Offline panel loaders + CLI-facing wiring: JSON / long CSV → PanelFeed,
 * MuseRuntime.panelFromBySym, configureForPanel fitness path.
 */
class TestPanelLoader extends Test {
	function teardown() {
		Fitness.configurePanel(null);
		Fitness.clearFnCache();
	}

	static function sampleBySymJson():String {
		var aaa:Array<Dynamic> = [];
		var bbb:Array<Dynamic> = [];
		var priceA = 100.0, priceB = 100.0;
		for (i in 0...40) {
			var cA = priceA * 1.01;
			var cB = priceB * 0.995;
			aaa.push({ open: priceA, high: cA * 1.001, low: priceA * 0.999, close: cA, volume: 1000, time: i });
			bbb.push({ open: priceB, high: Math.max(priceB, cB) * 1.001, low: Math.min(priceB, cB) * 0.999, close: cB, volume: 1000, time: i });
			priceA = cA;
			priceB = cB;
		}
		return haxe.Json.stringify({ AAA: aaa, BBB: bbb });
	}

	static function sampleLongCsv():String {
		var buf = new StringBuf();
		buf.add("symbol,date,open,high,low,close,volume\n");
		var priceA = 50.0, priceB = 80.0;
		for (i in 0...30) {
			var cA = priceA * 1.008;
			var cB = priceB * 0.997;
			buf.add('AAA,2020-01-${StringTools.lpad(Std.string(i + 1), "0", 2)},$priceA,${cA * 1.001},${priceA * 0.999},$cA,100\n');
			buf.add('BBB,2020-01-${StringTools.lpad(Std.string(i + 1), "0", 2)},$priceB,${Math.max(priceB, cB)},${Math.min(priceB, cB)},$cB,100\n');
			priceA = cA;
			priceB = cB;
		}
		return buf.toString();
	}

	public function testFromJsonBuildsPanel() {
		var panel = PanelLoader.fromJson(sampleBySymJson());
		Assert.equals(2, panel.symbols.length);
		Assert.isTrue(panel.symbols.indexOf("AAA") >= 0);
		Assert.isTrue(panel.symbols.indexOf("BBB") >= 0);
		Assert.equals(40, panel.length());
		Assert.isTrue(Math.isFinite(panel.closes[0].get("AAA")));
	}

	public function testFromLongCsvBuildsPanel() {
		var panel = PanelLoader.fromLongCsv(sampleLongCsv());
		Assert.equals(2, panel.symbols.length);
		Assert.equals(30, panel.length());
		Assert.isTrue(panel.closes[10].exists("AAA"));
		Assert.isTrue(panel.closes[10].exists("BBB"));
	}

	public function testToBySymDynRoundTrip() {
		var map = PanelLoader.fromJsonMap(sampleBySymJson());
		var dyn = PanelLoader.toBySymDyn(map);
		var panel = MuseRuntime.panelFromBySym(dyn);
		Assert.isTrue(panel != null);
		Assert.equals(2, panel.symbols.length);
		Assert.equals(40, panel.length());
	}

	public function testRunPanelViaLoadedDyn() {
		var dyn = PanelLoader.toBySymDyn(PanelLoader.fromJsonMap(sampleBySymJson()));
		var src = "
strategy MomScan {
  onBar {
    scores = dict_new()
    for (sym in symbols()) {
      when sym_available(sym): dict_set(scores, sym, mom_of(sym, 5))
    }
    for (sym in scan_top(scores, 1)) {
      when pos(sym) == 0: buy(sym, 1)
    }
  }
}
";
		var res:Dynamic = MuseRuntime.runPanel(src, dyn, {
			tier: "js",
			fillNextOpen: true,
			costBps: 0,
			instrument: false,
			seed: 7
		});
		Assert.isTrue(Reflect.field(res, "ok") == true, Std.string(Reflect.field(res, "error")));
		Assert.isTrue(Reflect.field(res, "panel") == true);
		Assert.isTrue((Reflect.field(res, "trades") : Int) > 0);
	}

	public function testConfigureForPanelWithLoadedFeed() {
		var panel = PanelLoader.fromJson(sampleBySymJson());
		var engine = new EvolutionEngine(3, 2, 1, 2);
		engine.configureForTape(panel.all());
		engine.configureForPanel(panel);
		Assert.isTrue(Fitness.panelFeed != null);
		Assert.equals(panel.symbols.length, Fitness.panelFeed.symbols.length);

		var g:StrategyGenome = {
			name: "PanelBuy",
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
		var fr = Fitness.evaluate(g, panel.all(), "js");
		Assert.isTrue(fr.ok, fr.error);
		Assert.isTrue(fr.trades > 0);
		Fitness.configurePanel(null);
	}

	public function testBadJsonRejected() {
		var threw = false;
		try {
			PanelLoader.fromJson("[]");
		} catch (e:Dynamic) {
			threw = true;
			Assert.isTrue(Std.string(e).indexOf("PanelLoader") >= 0);
		}
		Assert.isTrue(threw);
	}

	public function testLongCsvWithoutSymbolRejected() {
		var threw = false;
		try {
			PanelLoader.fromLongCsv("open,high,low,close,volume\n1,2,0.5,1.5,10\n");
		} catch (e:Dynamic) {
			threw = true;
			Assert.isTrue(Std.string(e).toLowerCase().indexOf("symbol") >= 0);
		}
		Assert.isTrue(threw);
	}
}
