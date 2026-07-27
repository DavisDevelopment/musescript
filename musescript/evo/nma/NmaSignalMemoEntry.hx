package musescript.evo.nma;

import musescript.harness.Fill;

/**
 * Cached `OrderSim` outcome for one signal signature (`NmaSignalMemo`).
 *
 * «μία σφραγίς, ἓν τέλος.»
 */
class NmaSignalMemoEntry {
	public final trades:Int;
	public final sharpe:Float;
	public final finalEquity:Float;
	public final bankrupt:Bool;
	public final fills:Null<Array<Fill>>;
	public final equity:Null<Array<Float>>;

	public function new(trades:Int, sharpe:Float, finalEquity:Float, bankrupt:Bool,
			fills:Null<Array<Fill>>, equity:Null<Array<Float>>) {
		this.trades = trades;
		this.sharpe = sharpe;
		this.finalEquity = finalEquity;
		this.bankrupt = bankrupt;
		this.fills = fills;
		this.equity = equity;
	}
}
