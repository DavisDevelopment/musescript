package musescript.tests;

import utest.Test;
import utest.Assert;
import musescript.parse.MuseParser;
import musescript.interp.MuseInterp;
import musescript.harness.HarnessContext;
import musescript.harness.BarFeed;
import musescript.indicators.IndicatorBatch;
import musescript.indicators.prim.Sma;

/**
 * Regression suite for the array-buffer gap found while writing the
 * Capstone (musescript-enums-classes-rollout memory): `arr.push(x)` off a
 * plain (non-`__class`) object lost `this` binding (Reflect.getProperty
 * detaches the function from its receiver, then callValue called it with
 * `this=null`), and `arr[i] = x` had no case in binop("=")'s assignment
 * target switch at all — both silently broken, forcing the Capstone's SMA
 * re-authoring into a fixed-width 3-slot shift register instead of a real
 * buffer. Fixed via: `MuseInterp.callValue` gained an optional `recv` bound
 * to the object for the plain-native-function case (EField call fallback
 * passes it), and `binop("=", ...)`'s target switch gained an `EArray` case
 * mirroring the read side.
 */
class TestArrayBuffer extends Test {
	static function interpWith(source:String):MuseInterp {
		var prog = new MuseParser().parse(source);
		var interp = new MuseInterp(new HarnessContext());
		for (d in prog.decls) interp.registerDeclPublic(d);
		return interp;
	}

	// ── Direct array-mutation checks ───────────────────────────────────────

	public function testArrayPushMutatesTheReceiver() {
		var interp = interpWith("strategy S { onBar { } }");
		var arr:Array<Dynamic> = [];
		interp.globals.set("a", arr);
		interp.evalExpr(new MuseParser().parseExpr("a.push(1)"));
		interp.evalExpr(new MuseParser().parseExpr("a.push(2)"));
		Assert.same([1, 2], arr);
	}

	public function testArrayShiftMutatesTheReceiver() {
		var interp = interpWith("strategy S { onBar { } }");
		var arr:Array<Dynamic> = [10, 20, 30];
		interp.globals.set("a", arr);
		var shifted = interp.evalExpr(new MuseParser().parseExpr("a.shift()"));
		Assert.equals(10, shifted);
		Assert.same([20, 30], arr);
	}

	public function testArrayIndexAssignment() {
		var interp = interpWith("strategy S { onBar { } }");
		var arr:Array<Dynamic> = [1, 2, 3];
		interp.globals.set("a", arr);
		interp.evalExpr(new MuseParser().parseExpr("a[1] = 99"));
		Assert.same([1, 99, 3], arr);
	}

	// ── Real-world case: a genuinely DYNAMIC-period rolling SMA (the thing
	// the Capstone's fixed-width shift register couldn't do), still matching
	// the Haxe port bit-for-bit. ──────────────────────────────────────────

	static final ROLLING_SMA_SRC = 'class RollingSma {\n'
		+ '  values = [];\n'
		+ '  period = 0.0;\n'
		+ '  sum = 0.0;\n'
		+ '  new(p) {\n'
		+ '    period = p\n'
		+ '  }\n'
		+ '  function update(x) {\n'
		+ '    values.push(x)\n'
		+ '    sum = sum + x\n'
		+ '    when values.length > period: {\n'
		+ '      sum = sum - values[0]\n'
		+ '      values.shift()\n'
		+ '    }\n'
		+ '    when values.length < period: { return null }\n'
		+ '    return sum / period\n'
		+ '  }\n'
		+ '}\n';

	public function testDynamicWidthRollingSmaMatchesHaxePort() {
		// period=5 here — DIFFERENT from the Capstone's fixed period=3, and
		// driven entirely by the ctor arg, not baked into the class source —
		// exactly what the fixed-width shift-register workaround couldn't do.
		var bars = BarFeed.synthetic(200, 11).all();
		var closes = [for (b in bars) b.close];

		var haxeResult = IndicatorBatch.run(new Sma(5), closes);

		var interp = interpWith(ROLLING_SMA_SRC);
		var inst = interp.instantiatePublic("RollingSma", [5.0]);
		var museResult:Array<Null<Float>> = [for (x in closes) interp.callInstanceMethodPublic(inst, "update", [x])];

		Assert.equals(haxeResult.length, museResult.length);
		for (i in 0...haxeResult.length) {
			if (haxeResult[i] == null) {
				Assert.isNull(museResult[i]);
			} else {
				Assert.notNull(museResult[i]);
				Assert.floatEquals(haxeResult[i], museResult[i]);
			}
		}
	}

	/** Same class, a DIFFERENT period entirely at runtime — proves the width
	 * genuinely comes from the ctor arg, not something incidentally fixed. */
	public function testDynamicWidthRollingSmaWithDifferentPeriod() {
		var bars = BarFeed.synthetic(200, 11).all();
		var closes = [for (b in bars) b.close];

		var haxeResult = IndicatorBatch.run(new Sma(9), closes);

		var interp = interpWith(ROLLING_SMA_SRC);
		var inst = interp.instantiatePublic("RollingSma", [9.0]);
		var museResult:Array<Null<Float>> = [for (x in closes) interp.callInstanceMethodPublic(inst, "update", [x])];

		for (i in 0...haxeResult.length) {
			if (haxeResult[i] == null) {
				Assert.isNull(museResult[i]);
			} else {
				Assert.floatEquals(haxeResult[i], museResult[i]);
			}
		}
	}
}
