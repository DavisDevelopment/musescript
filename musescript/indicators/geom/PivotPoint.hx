package musescript.indicators.geom;

/**
 * One swing extreme. `direction` is +1.0 (swing high) or -1.0 (swing low).
 * Hot fields stay unboxed Float/Int; status is a cheap Int abstract.
 */
class PivotPoint {
	public var price:Float;
	public var direction:Float;
	public var bar:Int;
	public var status:PivotStatus;

	public function new(price:Float, direction:Float, bar:Int, status:PivotStatus = Confirmed) {
		this.price = price;
		this.direction = direction;
		this.bar = bar;
		this.status = status;
	}

	public function copy():PivotPoint {
		return new PivotPoint(price, direction, bar, status);
	}
}
