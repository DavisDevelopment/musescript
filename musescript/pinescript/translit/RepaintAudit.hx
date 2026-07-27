package musescript.pinescript.translit;

import musescript.types.SourcePos;
import musescript.pinescript.ast.PineExpr;

/**
 * Flags Pine patterns that repaint — i.e. behave differently in realtime vs. on
 * historical bars, the famous silent trap that makes a backtest look better than
 * live. We DON'T reproduce the bug on import; we surface it. This is the "we tell
 * you where your strategy was lying to you" marketing wedge, made concrete.
 *
 * Detected (v0):
 *  - request.security(...) with `lookahead=barmerge.lookahead_on` (classic
 *    future-peeking) or without an explicit historical offset.
 *  - barstate.isrealtime / barstate.islast branches that change signal logic.
 *  Extended over time as the corpus reveals more shapes.
 */
enum RepaintKind {
	SecurityLookahead;
	SecurityNoOffset;
	RealtimeBranch;
}

typedef RepaintFinding = {
	var kind:RepaintKind;
	var ?pos:SourcePos;
	var detail:String;
}

class RepaintAudit {
	public var findings:Array<RepaintFinding> = [];
	public function new() {}

	public function note(kind:RepaintKind, detail:String, ?pos:SourcePos):Void
		findings.push({kind: kind, detail: detail, pos: pos});

	/** Inspect a call expression; record a finding if it matches a repaint shape.
	 *  `qualified` is the resolved callee name (e.g. "request.security"). */
	public function auditCall(qualified:String, args:Array<PineArg>, ?pos:SourcePos):Void {
		if (qualified == "request.security" || qualified == "security") {
			var hasLookaheadOn = false, hasOffset = false;
			for (a in args) {
				if (a.name == "lookahead" && exprMentions(a.value, "lookahead_on")) hasLookaheadOn = true;
				// a historical offset is the guard-against-repaint idiom: security(..)[1]
			}
			if (hasLookaheadOn)
				note(SecurityLookahead,
					"request.security(lookahead=barmerge.lookahead_on) peeks at future data — "
					+ "backtests will look better than live. In Muse, join via PanelFeed with an "
					+ "explicit bar offset instead.", pos);
			else if (!hasOffset)
				note(SecurityNoOffset,
					"request.security(...) without a [1] historical offset repaints on the "
					+ "forming bar. Confirm the intended timing before trusting the backtest.", pos);
		}
	}

	public function auditIdentBranch(qualified:String, ?pos:SourcePos):Void {
		if (qualified == "barstate.isrealtime" || qualified == "barstate.islast")
			note(RealtimeBranch,
				"branch keyed on `" + qualified + "` diverges between historical and realtime "
				+ "execution — a common source of backtest/live mismatch.", pos);
	}

	static function exprMentions(e:PineExpr, needle:String):Bool {
		return switch (e) {
			case PIdent(n): n.indexOf(needle) >= 0;
			case PField(t, f): f.indexOf(needle) >= 0 || exprMentions(t, needle);
			default: false;
		};
	}

	public function describe(f:RepaintFinding):String {
		var where = f.pos != null && f.pos.line != null ? ' (line ${f.pos.line})' : "";
		return "⚠ repaint" + where + ": " + f.detail;
	}
}
