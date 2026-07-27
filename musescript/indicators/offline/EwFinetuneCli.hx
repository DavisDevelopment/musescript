package musescript.indicators.offline;

import musescript.harness.Bar;
import musescript.harness.OhlcvCsv;
import musescript.indicators.ew.EwPhiParams;

/**
 * Offline CLI: export EW finetune features, load finetuned φ pack.
 * NEVER invoked from indicator update().
 *
 *   node build/js/ew-finetune.js export --out features.json [--csv bars.csv] [--horizon 10]
 *   node build/js/ew-finetune.js export-synthetic --out features.json
 *   node build/js/ew-finetune.js load --in finetuned_phi.json
 */
class EwFinetuneCli {
	static function main() {
		var args = Sys.args();
		if (args.length == 0) {
			usage();
			Sys.exit(1);
		}
		var cmd = args[0];
		switch (cmd) {
			case "export":
				runExport(args);
			case "export-synthetic":
				runExportSynthetic(args);
			case "load":
				runLoad(args);
			default:
				Sys.println('unknown command: $cmd');
				usage();
				Sys.exit(1);
		}
	}

	static function usage():Void {
		Sys.println("EwFinetuneCli — offline EwPhiParams export / load");
		Sys.println("  export [--out PATH] [--csv PATH] [--horizon N] [--threshold F]");
		Sys.println("  export-synthetic [--out PATH] [--horizon N]");
		Sys.println("  load --in PATH");
	}

	static function runExport(args:Array<String>):Void {
		var outPath = arg(args, "--out", "build/ew_finetune_features.json");
		var csvPath = arg(args, "--csv", "");
		var horizon = Std.parseInt(arg(args, "--horizon", "10"));
		var threshold = Std.parseFloat(arg(args, "--threshold", "0.02"));
		var bars:Array<Bar> = csvPath != "" ? OhlcvCsv.parse(sys.io.File.getContent(csvPath)) : EwFinetuneExport.syntheticBars();
		var ex = new EwFinetuneExport();
		ex.exportFromBars(bars, { swingThreshold: threshold, horizon: horizon });
		var closes = [for (b in bars) b.close];
		ex.fillForwardReturns(closes, horizon);
		ex.saveJson(outPath);
		Sys.println('exported ${ex.rows.length} rows → $outPath');
	}

	static function runExportSynthetic(args:Array<String>):Void {
		var outPath = arg(args, "--out", "build/ew_finetune_features.json");
		var horizon = Std.parseInt(arg(args, "--horizon", "5"));
		var ex = EwFinetuneExport.exportSynthetic(outPath);
		var closes = [for (b in EwFinetuneExport.syntheticBars()) b.close];
		ex.fillForwardReturns(closes, horizon);
		ex.saveJson(outPath);
		Sys.println('exported ${ex.rows.length} synthetic rows → $outPath');
	}

	static function runLoad(args:Array<String>):Void {
		var inPath = arg(args, "--in", "");
		if (inPath == "") {
			Sys.println("--in required");
			Sys.exit(1);
		}
		var p = EwPhiParams.loadFromJsonFile(inPath);
		EwPhiParams.setCurrent(p);
		Sys.println('loaded finetuned pack from $inPath (fibHitTol=${p.fibHitTol})');
	}

	static function arg(args:Array<String>, key:String, defaultVal:String):String {
		var i = args.indexOf(key);
		if (i >= 0 && i + 1 < args.length) return args[i + 1];
		return defaultVal;
	}
}
