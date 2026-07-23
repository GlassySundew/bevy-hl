package bevy;

/** Per-world storage for Haxe resources, with keys supplied by compile-time macros. */
class ResourceStore {

	final values : Map<String, Dynamic> = [];

	public function new() {}

	@:noCompletion
	public function insertDynamic( typeName : String, value : Dynamic ) : Dynamic {

		values.set( typeName, value );
		return value;
	}

	@:noCompletion
	public inline function getDynamic( typeName : String ) : Dynamic {

		return values.get( typeName );
	}

	@:noCompletion
	public inline function hasDynamic( typeName : String ) : Bool {

		return values.exists( typeName );
	}

	@:noCompletion
	public function requireDynamic( typeName : String ) : Dynamic {

		if ( !values.exists( typeName ) )
			throw 'Required resource $typeName is not present in this Bevy world';
		return values.get( typeName );
	}

	@:noCompletion
	public function removeDynamic( typeName : String ) : Dynamic {

		if ( !values.exists( typeName ) )
			return null;
		final value = values.get( typeName );
		values.remove( typeName );
		return value;
	}

	public inline function clear() : Void {

		values.clear();
	}
}
