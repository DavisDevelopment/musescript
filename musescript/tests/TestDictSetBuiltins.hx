package musescript.tests;

import musescript.builtins.DictBuiltins;
import musescript.builtins.SetBuiltins;
import musescript.builtins.TradeBuiltins;
import musescript.harness.HarnessContext;
import musescript.interp.MuseInterp;
import musescript.MuseScript;
import utest.Assert;
import utest.Test;

class TestDictSetBuiltins extends Test {
	public function testDictRoundTrip() {
		var d = DictBuiltins.dictNew();
		DictBuiltins.dictSet(d, "a", 1.5);
		DictBuiltins.dictSet(d, "b", "x");
		Assert.isTrue(DictBuiltins.dictHas(d, "a"));
		Assert.equals(1.5, DictBuiltins.dictGet(d, "a"));
		Assert.equals("x", DictBuiltins.dictGet(d, "b"));
		Assert.equals(42, DictBuiltins.dictGet(d, "missing", 42));
		Assert.equals(2, DictBuiltins.dictSize(d));
		Assert.equals(2, DictBuiltins.dictKeys(d).length);
		Assert.equals(2, DictBuiltins.dictValues(d).length);
		Assert.isTrue(DictBuiltins.dictDelete(d, "a"));
		Assert.isFalse(DictBuiltins.dictHas(d, "a"));
		Assert.equals(1, DictBuiltins.dictSize(d));
	}

	public function testSetAlgebra() {
		var a = SetBuiltins.setNew();
		SetBuiltins.setAdd(a, 1);
		SetBuiltins.setAdd(a, 2);
		var b = SetBuiltins.setNew();
		SetBuiltins.setAdd(b, 2);
		SetBuiltins.setAdd(b, 3);
		Assert.isTrue(SetBuiltins.setHas(a, 1));
		Assert.equals(2, SetBuiltins.setSize(a));
		Assert.equals(3, SetBuiltins.setSize(SetBuiltins.setUnion(a, b)));
		Assert.equals(1, SetBuiltins.setSize(SetBuiltins.setIntersect(a, b)));
		Assert.equals(1, SetBuiltins.setSize(SetBuiltins.setDifference(a, b)));
		Assert.isTrue(SetBuiltins.setRemove(a, 1));
		Assert.isFalse(SetBuiltins.setHas(a, 1));
		var vec = SetBuiltins.setToVector(b);
		Assert.equals(2, vec.length);
		Assert.equals(1.0, SetBuiltins.setJaccard(b, b));
		Assert.isTrue(SetBuiltins.setJaccard(a, b) < 1.0);
		Assert.equals(1.0, SetBuiltins.setJaccard(SetBuiltins.setNew(), SetBuiltins.setNew()));
	}

	public function testDictSetViaInterp() {
		var harness = new HarnessContext();
		var interp = new MuseInterp(harness);
		var d:Dynamic = interp.callValue(interp.globals.get("dict_new"), []);
		interp.callValue(interp.globals.get("dict_set"), [d, "k", 9]);
		Assert.equals(9, interp.callValue(interp.globals.get("dict_get"), [d, "k"]));
		Assert.equals(1, interp.callValue(interp.globals.get("dict_size"), [d]));
		var s:Dynamic = interp.callValue(interp.globals.get("set_new"), []);
		interp.callValue(interp.globals.get("set_add"), [s, 3]);
		Assert.isTrue(interp.callValue(interp.globals.get("set_has"), [s, 3]));
	}

	public function testDictSetInstalledOnTradeBuiltins() {
		var vars:Map<String, Dynamic> = new Map();
		TradeBuiltins.install(vars, new HarnessContext());
		Assert.isTrue(Reflect.isFunction(vars.get("dict_new")));
		Assert.isTrue(Reflect.isFunction(vars.get("set_union")));
		var dict = vars.get("dict_new")();
		vars.get("dict_set")(dict, "z", 7);
		Assert.equals(7, vars.get("dict_get")(dict, "z"));
	}

	public function testDictSetSignaturesPresent() {
		Assert.notNull(musescript.types.BuiltinSigs.get("dict_new"));
		Assert.notNull(musescript.types.BuiltinSigs.get("set_union"));
		Assert.isTrue(Type.enumEq(
			musescript.types.BuiltinSigs.get("dict_new").ret,
			musescript.types.MuseType.TDict
		));
		Assert.isTrue(Type.enumEq(
			musescript.types.BuiltinSigs.get("set_new").ret,
			musescript.types.MuseType.TSet
		));
		Assert.isTrue(Type.enumEq(
			musescript.types.BuiltinSigs.get("dict_values").ret,
			musescript.types.MuseType.TUnknown
		));
	}

	public function testTypedDictUsage() {
		var errs = MuseScript.check('{
			@strategy("x")
			@on(bar) {
				var d = dict_new();
				dict_set(d, "k", 1);
				if (dict_has(d, "k") && dict_size(d) > 0) long();
			}
		}');
		Assert.isFalse(hasErr(errs, "expected"));
		Assert.isFalse(hasErr(errs, "field"));
	}

	function hasErr(errs:Array<String>, needle:String):Bool {
		for (e in errs) if (e.indexOf("error:") == 0 && e.indexOf(needle) >= 0) return true;
		return false;
	}
}
