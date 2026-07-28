package musescript.ew;

import musescript.evo.HostProjectionDemoCore;

/**
 * Headless CLI demo: bars → host cloud → Expand/Fitness + projScore.
 *
 * ```powershell
 * haxe build-host-proj-cli.hxml
 * node build/js/host-proj-cli.js --host lattice
 * node build/js/host-proj-cli.js --host mcmc
 * ```
 */
class HostProjectionCli {
	static function main() {
		var hostKind = "lattice";
		var args = Sys.args();
		var i = 0;
		while (i < args.length) {
			if (args[i] == "--host" && i + 1 < args.length) {
				hostKind = args[i + 1];
				i += 2;
				continue;
			}
			i++;
		}
		if (hostKind != "lattice" && hostKind != "mcmc") hostKind = "lattice";
		var r = HostProjectionDemoCore.run(hostKind);
		HostProjectionDemoCore.printResult(r);
		Sys.exit(r.ok && Math.isFinite(r.projScore) ? 0 : 1);
	}
}
