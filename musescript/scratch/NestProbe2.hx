package musescript.scratch;

import musescript.evo.BoolNode;
import musescript.evo.ScalarNode;
import musescript.evo.SeriesNode;
import musescript.evo.StrategyGenome;
import musescript.evo.Fitness;
import musescript.evo.Expand;
import musescript.harness.Bar;

class NestProbe2 {
	static function main() {
		var CLOSE = [10.0, 11.0, 12.0, 11.0, 13.0, 12.0, 14.0, 15.0, 13.0, 16.0];
		var bars = new Array<Bar>();
		var prev = CLOSE[0];
		for (i in 0...CLOSE.length) {
			var c = CLOSE[i];
			bars.push({
				open: prev, high: Math.max(prev, c) + 0.1, low: Math.min(prev, c) - 0.1,
				close: c, volume: 1000, time: i, index: i
			});
			prev = c;
		}
		var g:StrategyGenome = {
			entryLong: BCmp(">", KSeries(SInd("ema", "close", 3, SInd("sma", "close", 2, null))), KConst(0.0)),
			entryShort: BCmp(">", KConst(0.0), KConst(1.0)),
			exitLong: BCmp(">", KConst(0.0), KConst(1.0)),
			exitShort: BCmp(">", KConst(0.0), KConst(1.0)),
			size: KConst(1.0), params: [], name: "n"
		};
		Sys.println(Expand.expand(g));
		Fitness.preferNma = false;
		var fr = Fitness.evaluate(g, bars, "js", false);
		Sys.println('compiled ok=${fr.ok} backend=${fr.backend} trades=${fr.trades} eq=${fr.finalEquity}');
		Fitness.preferNma = true;
		var fr2 = Fitness.evaluate(g, bars, "js", false);
		Sys.println('nma ok=${fr2.ok} backend=${fr2.backend} trades=${fr2.trades} err=${fr2.error}');
	}
}
