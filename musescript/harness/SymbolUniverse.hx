package musescript.harness;

class SymbolUniverse {
	public var symbols:Array<String>;
	public function new(?symbols:Array<String>) {
		this.symbols = symbols != null ? symbols : ["AAPL", "MSFT", "GOOG", "AMZN", "META", "NVDA", "TSLA", "JPM", "XOM", "UNH"];
	}
	public function sample(n:Int, ?seed:Int):Array<String> {
		var rng = seed != null ? seed : 42;
		var copy = symbols.copy();
		var i = copy.length;
		while (i > 1) {
			rng = (rng * 1103515245 + 12345) & 0x7fffffff;
			var j = rng % i;
			i--;
			var tmp = copy[i];
			copy[i] = copy[j];
			copy[j] = tmp;
		}
		return copy.slice(0, Std.int(Math.min(n, copy.length)));
	}
}
