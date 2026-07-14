package musescript.runtime;

/**
 * Unified sync/async iterable protocol.
 */
enum IterResult<T> {
	Done;
	Value(v:T);
	Await(resume:Void->IterResult<T>);
}
