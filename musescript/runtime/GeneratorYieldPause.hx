package musescript.runtime;

/**
 * Stepped-mode control flow: evalBody returns without finishing the generator body.
 * Thrown by pushYield / delegateTo when pauseAfterYield is true and collecting.
 */
class GeneratorYieldPause {
	public function new() {}
}
