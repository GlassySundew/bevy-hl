package bevy;

typedef ComponentDefinition = {
	final name : String;
	final sparse : Bool;
}

/** Runtime descriptor array populated by generated component initializers. */
@:noCompletion
class ComponentCatalog {

	static final definitions : Array<Null<ComponentDefinition>> = [];

	public static function register( id : Int, name : String, sparse : Bool ) : Bool {

		while ( definitions.length <= id ) definitions.push( null );
		final existing = definitions[id];
		if ( existing != null && ( existing.name != name || existing.sparse != sparse ) )
			throw 'Conflicting component descriptor for compile-time id $id';
		definitions[id] = { name: name, sparse: sparse };
		return true;
	}

	public static function all() : Array<Null<ComponentDefinition>> return definitions;
}
