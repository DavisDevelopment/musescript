package musescript.evo.jenetics;

/**
 * Narrow typed surface for Jenetics 8.3.x (Java 21).
 * Haxe owns genome operators; Jenetics may own Engine/selection when linked on JVM.
 */
#if java
@:native("io.jenetics.Optimize")
extern enum Optimize {
	MAXIMUM;
	MINIMUM;
}

@:native("io.jenetics.engine.EvolutionResult")
extern class EvolutionResult<G, C> {
	function bestFitness():C;
}
#end

/**
 * Documentation + compile-time hooks for the Jenetics integration point.
 * The Haxe `EvolutionEngine` is the reference implementation; Jenetics is the
 * preferred production selector when the JVM classpath includes io.jenetics:jenetics:8.3.0.
 */
class JeneticsNotes {
	public static inline var ARTIFACT = "io.jenetics:jenetics:8.3.0";
	public static inline var REQUIRES_JAVA = 21;
	public static function describe():String {
		return "Use Jenetics Engine for population lifecycle; keep musescript.evo.Variation typed.";
	}
}
