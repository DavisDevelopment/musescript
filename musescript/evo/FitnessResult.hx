package musescript.evo;

class FitnessResult {
	public var ok:Bool;
	public var sharpe:Float;
	public var trades:Int;
	public var finalEquity:Float;
	public var backend:String;
	public var error:Null<String>;

	public function new(ok:Bool, sharpe:Float, trades:Int, finalEquity:Float, backend:String, ?error:String) {
		this.ok = ok;
		this.sharpe = sharpe;
		this.trades = trades;
		this.finalEquity = finalEquity;
		this.backend = backend;
		this.error = error;
	}
}
