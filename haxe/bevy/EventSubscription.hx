package bevy;

/** Per-system read cursor over a shared typed event channel. */
@:generic
@:noCompletion
class EventSubscription<T> implements IEventSubscription {

	public var active( default, null ) : Bool = false;
	final channel : EventChannel<T>;
	final callback : T -> Bool -> Void;
	var epoch : Int = -1;
	var cursor : Int = 0;

	public function new( channel : EventChannel<T>, callback : T -> Bool -> Void ) {

		this.channel = channel;
		this.callback = callback;
	}

	public function activate() : Void {

		active = true;
		if ( epoch != channel.epoch ) {
			epoch = channel.epoch;
			cursor = 0;
		}
	}

	public function deactivate() : Void {

		active = false;
		clear();
	}

	public function drain() : Void {

		if ( !active ) return;
		if ( epoch != channel.epoch ) {
			epoch = channel.epoch;
			cursor = 0;
		}
		final events = channel.current;
		final generationChecks = channel.currentGenerationChecks;
		final end = events.length;
		while ( cursor < end ) {
			final index = cursor++;
			callback( events[index], generationChecks[index] );
		}
	}

	public function clear() : Void {

		epoch = channel.epoch;
		cursor = channel.current.length;
	}
}
