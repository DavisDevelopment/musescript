package musescript.scratch;

import musescript.evo.nma.NmaEpoch;
import musescript.evo.nma.NmaEvalContext;
import musescript.evo.nma.NmaEval;
import musescript.evo.nma.EngineIndicatorProvider;
import musescript.evo.nma.NmaSeries;
import musescript.evo.nma.NmaSeries.NmaSInd;

class NestProbe {
	static function main() {
		var CLOSE = [10.0, 11.0, 12.0, 11.0, 13.0, 12.0, 14.0, 15.0, 13.0, 16.0];
		NmaEpoch.resetRegistry();
		var fields = ["close" => CLOSE];
		var ctx = new NmaEvalContext(CLOSE.length, NmaEpoch.of("t", []), fields, null, null,
			new EngineIndicatorProvider(fields));
		var nested = new NmaSInd("ema", "close", 3, new NmaSInd("sma", "close", 2, null));
		try {
			var col = NmaEval.evalSeries(nested, ctx);
			Sys.println("len=" + col.length);
			for (i in 0...col.length) Sys.println("  " + i + "=" + col.at(i));
		} catch (e:Dynamic) {
			Sys.println("ERR=" + Std.string(e));
		}
	}
}
