package bevy;

/** A compile-time-specialized channel containing only values of T. */
@:generic
@:noCompletion
class EventChannel<T> implements IEventChannel {

	public var epoch( default, null ) : Int = 0;
	public var current( get, never ) : Array<T>;
	public var currentGenerationChecks( get, never ) : Array<Bool>;
	final buckets : Array<Array<T>> = [[]];
	final generationCheckBuckets : Array<Array<Bool>> = [[]];

	public function new() {}

	inline function get_current() : Array<T> return buckets[0];
	inline function get_currentGenerationChecks() : Array<Bool> return generationCheckBuckets[0];

	public function emit( event : T, tickOffset : Int ) : Void {

		if ( event == null ) throw "Cannot emit a null event";
		if ( tickOffset < 0 ) throw 'Event tick offset must be non-negative, got $tickOffset';
		while ( buckets.length <= tickOffset ) {
			buckets.push( [] );
			generationCheckBuckets.push( [] );
		}
		buckets[tickOffset].push( event );
		generationCheckBuckets[tickOffset].push( tickOffset > 0 );
	}

	public function advanceTick() : Void {

		final expired = buckets.shift();
		expired.resize( 0 );
		buckets.push( expired );
		final expiredChecks = generationCheckBuckets.shift();
		expiredChecks.resize( 0 );
		generationCheckBuckets.push( expiredChecks );
		epoch++;
	}

	public function clear() : Void {

		for ( bucket in buckets ) bucket.resize( 0 );
		for ( bucket in generationCheckBuckets ) bucket.resize( 0 );
		buckets.resize( 1 );
		generationCheckBuckets.resize( 1 );
		epoch++;
	}
}
