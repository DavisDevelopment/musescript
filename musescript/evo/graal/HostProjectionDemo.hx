package musescript.evo.graal;

import musescript.evo.HostProjectionDemoCore;

/**
 * Thin launcher into the real MuseGene evo dashboard (`CorpusEvoRun --gui`) with EW host
 * projections wired (`--ew-host lattice|mcmc`). Not a separate toy line-animation viz.
 *
 * Headless smoke still uses `HostProjectionDemoCore` (no Swing).
 *
 * Preferred launch (same jar as corpus evo, or this demo jar which forwards):
 *
 * ```powershell
 * haxe build-corpus-evo.hxml
 * $env:JAVA_HOME = "C:\Users\epiki\graalvm\graalvm-community-25.1.3"
 * $JAVA = Join-Path $env:JAVA_HOME "bin\java.exe"
 * $CP = (Get-Content graal\cp.txt -Raw).Trim()
 * & $JAVA --sun-misc-unsafe-memory-access=allow -cp "$CP;build\jvm\corpus-evo.jar" `
 *   musescript.evo.graal.CorpusEvoRun --gui --ew-host lattice `
 *   --tape corpus/tapes/spy_oos_2022_2026.csv --pop 32 --gens 16 --threads 1
 * ```
 *
 * Or via this entry (forwards into CorpusEvoRun with the same defaults):
 *
 * ```powershell
 * haxe build-host-proj-demo.hxml
 * & $JAVA --sun-misc-unsafe-memory-access=allow -cp "$CP;build\jvm\host-proj-demo.jar" `
 *   musescript.evo.graal.HostProjectionDemo --host lattice
 * ```
 *
 * Flags: `--host lattice|mcmc` (maps to `--ew-host`), `--headless`, plus any CorpusEvoRun flag
 * (`--tape`, `--pop`, `--gens`, …) passed through.
 */
class HostProjectionDemo {
	static function main() {
		var hostKind = argStr("--host", "lattice");
		if (hostKind != "lattice" && hostKind != "mcmc") hostKind = "lattice";
		var headless = argFlag("--headless");

		if (headless) {
			var r = HostProjectionDemoCore.run(hostKind);
			HostProjectionDemoCore.printResult(r);
			Sys.exit(r.ok && Math.isFinite(r.projScore) ? 0 : 1);
			return;
		}

		var tape = argStr("--tape", "corpus/tapes/spy_oos_2022_2026.csv");
		var pop = argStr("--pop", "32");
		var gens = argStr("--gens", "16");
		var threads = argStr("--threads", "1");
		var seed = argStr("--seed", "42");

		// Forward into the real evo GUI — keep user-passed CorpusEvoRun flags, drop demo-only ones.
		var forwarded:Array<String> = [
			"--gui",
			"--ew-host", hostKind,
			"--tape", tape,
			"--pop", pop,
			"--gens", gens,
			"--threads", threads,
			"--seed", seed
		];
		var skipNext = false;
		var consumed = [
			"--host" => true, "--tape" => true, "--pop" => true,
			"--gens" => true, "--threads" => true, "--seed" => true,
			"--ew-host" => true
		];
		var args = Sys.args();
		var i = 0;
		while (i < args.length) {
			var a = args[i];
			if (a == "--headless" || a == "--gui") {
				i++;
				continue;
			}
			if (consumed.exists(a)) {
				i += 2;
				continue;
			}
			forwarded.push(a);
			i++;
		}

		Sys.println('[ew-host] HostProjectionDemo → CorpusEvoRun --gui --ew-host $hostKind (real EvoDashboardWindow)');
		Sys.println('[ew-host] args: ' + forwarded.join(" "));
		CorpusEvoRun.argOverride = forwarded;
		CorpusEvoRun.main();
	}

	static function argFlag(name:String):Bool {
		for (a in Sys.args()) if (a == name) return true;
		return false;
	}

	static function argStr(name:String, dflt:String):String {
		var args = Sys.args();
		var i = 0;
		while (i < args.length - 1) {
			if (args[i] == name) return args[i + 1];
			i++;
		}
		return dflt;
	}
}
