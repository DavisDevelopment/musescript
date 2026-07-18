package musescript.ast;

/**
 * Statement-level order verbs (`long()` / `short()` / `flat()` / `close()`).
 *
 * Deliberately NOT the full order-type algebra. Real order semantics —
 * limit/market/stop kinds × time-in-force × brackets/OCO × sizing rules —
 * compose as RULES, not enum variants, and belong on the execution-sim side
 * (OrderBook/PortfolioSim + an order-spec object argument), keeping the AST
 * verb surface stable while execution realism grows underneath. That work is
 * scoped in ROADMAP.md ("Execution realism"). Until it lands, these four
 * verbs fill at close with per-side bps costs — an honest simple model, not
 * a placeholder waiting to silently change meaning.
 */
enum OrderKind {
	Long;
	Short;
	Flat;
	Close;
}
