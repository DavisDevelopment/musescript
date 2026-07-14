package musescript.examples;

import musescript.ast.MuseProgram;
import musescript.ast.Decl;
import musescript.ast.Stmt;
import musescript.ast.Expr;
import musescript.ast.Const;
import musescript.ast.MatchArm;
import musescript.ast.FnKind;
import musescript.ast.OrderKind;
import musescript.ast.ParamOpts;
import musescript.ast.Pattern;
import musescript.harness.LiveHarness;
import musescript.harness.EventLog;
import musescript.harness.EventStream;
import musescript.runtime.PatternMatcher;
import musescript.runtime.IterDriver;
import musescript.runtime.MuseIters;

/**
 * Example 04 — order-flow replay via EventLog (sync MuseIter).
 * Same matching works against live EventStream.
 */
class OrderFlow {
	static function main() {
		Sys.println("=== MuseScript 04-order-flow ===");

		var log = new EventLog([
			{ kind: "Filled", id: "o1", px: 100.0, qty: 50 },
			{ kind: "PartialFill", id: "o2", px: 101.0, filled: 10, remaining: 40 },
			{ kind: "Filled", id: "o3", px: 102.0, qty: 200 },
			{ kind: "Rejected", id: "o4", reason: "limit" },
			{ kind: "Cancelled", id: "o5" }
		]);

		var arms:Array<MatchArm> = [
			{ pattern: PatTag("Filled", []), body: EConst(CString("filled")) },
			{ pattern: PatTag("Rejected", []), body: EConst(CString("rejected")) },
			{ pattern: PatWild, body: EConst(CString("other")) }
		];

		var matcher = new PatternMatcher();
		var fills = 0;
		var rejects = 0;
		log.reset();
		IterDriver.each(log, function(ev) {
			var r = matcher.match(ev, arms);
			var kind = r.matched ? switch (r.body) {
				case EConst(CString(s)): s;
				default: "?";
			} : "no";
			if (kind == "filled") fills++;
			if (kind == "rejected") rejects++;
			Sys.println("kind=" + Reflect.field(ev, "kind") + " -> " + kind);
		});

		// Live stream adapter: push same events into EventStream, drain via MuseIter
		var live = new EventStream("orderFlow");
		for (e in log.events) live.push(e);
		live.end();
		var liveFills = 0;
		IterDriver.each(live, function(ev) {
			var r = matcher.match(ev, arms);
			if (r.body.match(EConst(CString("filled")))) liveFills++;
		});

		Sys.println("replay fills: " + fills + " rejects: " + rejects);
		Sys.println("live-stream fills: " + liveFills);
		Sys.println("EventLog and EventStream both MuseIter — same consumer");
	}
}
