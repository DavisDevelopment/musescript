package musescript.examples;

import musescript.ast.Expr;
import musescript.ast.Const;
import musescript.ast.Stmt;
import musescript.ast.Pattern;
import musescript.ast.Decl;
import musescript.harness.LiveHarness;
import musescript.harness.EventLog;
import musescript.interp.MuseInterp;
import musescript.runtime.MuseIter;

/**
 * LiveHarness + MuseInterp.dispatchEvents — EventLog and EventStream are both MuseIter.
 */
class OrderFlowLive {
	static function main() {
		Sys.println("=== MuseScript order-flow via MuseInterp ===");

		var harness = new LiveHarness();
		var events:Array<Dynamic> = [
			{ kind: "Filled", id: "o1", px: 100.0, qty: 50 },
			{ kind: "Filled", id: "o2", px: 102.0, qty: 200 },
			{ kind: "Rejected", id: "o3", reason: "limit" }
		];
		var log = new EventLog(events);

		var handlers:Array<Stmt> = [
			MatchFor("event", EIdent("orderFlow"), [
				{ pattern: PatTag("Filled", []), body: ECall(EIdent("noteFill"), []) },
				{ pattern: PatWild, body: EConst(CNull) }
			])
		];

		var fills = 0;
		var interp = new MuseInterp(harness);
		interp.globals.set("noteFill", function() { fills++; });
		interp.executeProgram({ decls: [], stmts: [OnEvent("orderFlow", handlers)] });
		log.reset();
		interp.dispatchEvents("orderFlow", log);
		Sys.println("EventLog fills: " + fills);

		var liveFills = 0;
		harness.start();
		harness.publishOrders(events);
		harness.stop();
		harness.pump();
		var live = harness.eventStreams.get("orderFlow");
		var interp2 = new MuseInterp(harness);
		interp2.globals.set("noteFill", function() { liveFills++; });
		interp2.executeProgram({ decls: [], stmts: [OnEvent("orderFlow", handlers)] });
		interp2.dispatchEvents("orderFlow", live);
		Sys.println("EventStream fills: " + liveFills);
	}
}
