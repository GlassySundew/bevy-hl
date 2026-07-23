package bevy;

/** Cleanup scope recreated for every system activation. */
class SystemLifetime {

	public var open( default, null ) : Bool = false;

	final cleanup : Array<Void -> Void> = [];

	@:allow( bevy.System )
	public function new() {}

	/** Registers cleanup to run in reverse order when this activation ends. */
	public function defer( callback : Void -> Void ) : Void {

		if ( !open )
			throw "System lifetime cleanup can only be registered while its system is activating or active";
		cleanup.push( callback );
	}

	/** Registers a value and its cleanup while returning the value unchanged. */
	public function own<T>( value : T, disposer : T -> Void ) : T {

		defer( () -> disposer( value ) );
		return value;
	}

	@:noCompletion
	@:allow( bevy.System )
	function begin() : Void {

		cleanup.resize( 0 );
		open = true;
	}

	/** Runs every cleanup even if one fails and returns the first failure. */
	@:allow( bevy.System )
	function close() : Null<haxe.Exception> {

		if ( !open )
			return null;
		open = false;
		var firstError : Null<haxe.Exception> = null;
		while ( cleanup.length > 0 ) {

			final callback = cleanup.pop();
			try callback() catch ( error : haxe.Exception ) {
				if ( firstError == null )
					firstError = error;
			}
		}
		return firstError;
	}
}
