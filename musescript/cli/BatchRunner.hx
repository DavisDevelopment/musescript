package musescript.cli;

/**
 * Warm batch-eval runner — Phase 1 of CURSOR_BATCH_RUNNER_SPEC.md.
 *
 * Collapses N cold Node spawns into one process: NDJSON jobs on stdin, one NDJSON
 * result line per job on stdout (streamed as each completes). Caches compiled
 * strategies by source hash and parsed tapes by path.
 *
 * Job line:
 *   {"id":"spy-eval3m","source":"<stitched .ms>","tape":"path/to/SPY.csv",
 *    "execution":"next-open","costBps":10,"seed":42}
 *
 * Result line (same metrics shape as gene-runner single-shot):
 *   {"id":"spy-eval3m","ok":true,"sharpe":0.42,"maxDrawdown":0.11,"trades":4,...}
 *
 * Usage:
 *   node build/js/batch-runner.js < jobs.ndjson
 *   # equivalent:
 *   node build/js/gene-runner.js --jobs - < jobs.ndjson
 *
 * Existing gene-runner single-shot / --batch (one tape × many genomes) CLI is unchanged.
 */
class BatchRunner {
	static function main() {
		#if kestrel
		musescript.kestrel.KestrelBootstrap.register();
		#end
		if (Sys.getEnv("MUSE_NATIVE_PARSER") == "1")
			musescript.parse.MuseParser.native = true;

		var a = Sys.args();
		var target = "js";
		var execution = "next-open";
		var costBps = 10.0;
		var seed = 42;
		var i = 0;
		while (i < a.length) {
			switch (a[i]) {
				case "--target" if (i + 1 < a.length):
					target = a[i + 1];
					i += 2;
				case "--execution" if (i + 1 < a.length):
					execution = a[i + 1];
					i += 2;
				case "--cost-bps" if (i + 1 < a.length):
					var c = Std.parseFloat(a[i + 1]);
					if (!Math.isNaN(c)) costBps = c;
					i += 2;
				case "--seed" if (i + 1 < a.length):
					var s = Std.parseInt(a[i + 1]);
					if (s != null) seed = s;
					i += 2;
				case "--help" | "-h":
					Sys.println("batch-runner.js — warm multi-tape MuseScript backtests");
					Sys.println("  NDJSON jobs on stdin; NDJSON results on stdout (one per job).");
					Sys.println("  Flags: --target js|interp  --execution next-open|same-close");
					Sys.println("         --cost-bps N  --seed N");
					Sys.println("  See examples/flagship-musescript-module/harness/BATCH_RUNNER.md");
					return;
				default:
					i += 1;
			}
		}

		var text = readStdin();
		var fatal = GeneRunner.runJobsManifest(text, {
			target: target,
			strict: false,
			defaultExecution: execution,
			defaultCostBps: costBps,
			defaultSeed: seed,
			startCapital: 100000,
			equityFloor: 0,
			useVm: false,
			synthN: 400
		});
		if (fatal) Sys.exit(1);
	}

	static function readStdin():String {
		try {
			return js.Syntax.code("require('fs').readFileSync(0, 'utf8')");
		} catch (_:Dynamic) {
			return "";
		}
	}
}
