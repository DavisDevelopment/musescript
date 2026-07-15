package musescript.kestrel;

import musescript.evo.Expand;

/** Kestrel genome -> MuseScript source. */
class KestrelExpand {
	public static function expand(g:KestrelGenome):String {
		var lines = ['strategy ${g.name} {'];
		for (p in g.params)
			lines.push('  param ${p.name} = ${num(p.defaultValue)};');

		for (f in g.featureBindings)
			lines.push('  indicator ${f.name}: Feature = ${feature(f.expr)};');

		lines.push("  onBar {");
		var size = Expand.scalar(g.size, g.params);
		lines.push('    when ${Expand.bool(g.entryLong, g.params)}: long($size);');
		lines.push('    when ${Expand.bool(g.entryShort, g.params)}: short($size);');
		lines.push('    when (${Expand.bool(g.exitLong, g.params)}) || (${Expand.bool(g.exitShort, g.params)}): flat();');
		lines.push("  }");
		lines.push("}");
		return lines.join("\n");
	}

	public static function feature(e:FeatureExpr):String {
		return switch (e) {
			case FConst(v): num(v);
			case FField(name): name;
			case FIndicator(name, src, window): '$name(${feature(src)}, $window)';
			case FLookback(src, n): '${feature(src)}[$n]';
			case FArith(op, a, b):
				var as = feature(a);
				var bs = feature(b);
				if (op == "min" || op == "max") '$op($as, $bs)' else '($as $op $bs)';
			case FZScore(src, scope):
				switch (scope) {
					case ZTime(window): 'zscore(${feature(src)}, $window)';
					case ZCrossSection: 'xscore(${feature(src)})';
					case ZGlobal: 'gscore(${feature(src)})';
				}
			case FModelScore(modelId): 'model_score("$modelId")';
			case FTreeValue(treeId): 'tree_value("$treeId")';
			case FTreeBit(treeId, bit): 'tree_bit("$treeId", $bit)';
			case FGraphMetric(queryId, metric): 'graph_metric("$queryId", "$metric")';
		};
	}

	static function num(x:Float):String {
		if (x == Std.int(x)) return Std.string(Std.int(x));
		return Std.string(x);
	}
}
