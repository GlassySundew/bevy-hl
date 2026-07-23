package bevy;

typedef ComponentDefinition = {
	final name : String;
	final sparse : Bool;
}

/** Runtime component descriptors restored from resources attached to typed modules. */
@:noCompletion
class ComponentCatalog {

	static inline final RESOURCE_PREFIX = "bevy.component.dense.";
	static final definitions : Array<Null<ComponentDefinition>> = [];
	static var resourcesLoaded : Bool = false;

	public static function register( id : Int, name : String, sparse : Bool ) : Bool {

		while ( definitions.length <= id ) definitions.push( null );
		final existing = definitions[id];
		if ( existing != null && ( existing.name != name || existing.sparse != sparse ) )
			throw 'Conflicting component descriptor for compile-time id $id';
		definitions[id] = { name: name, sparse: sparse };
		return true;
	}

	static function loadResources() : Void {

		if ( resourcesLoaded ) return;
		resourcesLoaded = true;
		for ( resourceName in haxe.Resource.listNames() ) {
			if ( !StringTools.startsWith( resourceName, RESOURCE_PREFIX ) ) continue;
			final suffix = resourceName.substr( RESOURCE_PREFIX.length );
			final separator = suffix.indexOf( "." );
			final id = Std.parseInt(
				separator < 0 ? suffix : suffix.substr( 0, separator )
			);
			final bytes = haxe.Resource.getBytes( resourceName );
			if ( id == null || bytes == null || bytes.length == 0 )
				throw 'Invalid Bevy component resource $resourceName';
			final payload = bytes.toString();
			register( id, payload.substr( 1 ), payload.charAt( 0 ) == "1" );
		}
	}

	public static function get( id : Int ) : Null<ComponentDefinition> {

		loadResources();
		return id >= 0 && id < definitions.length ? definitions[id] : null;
	}

	public static function all() : Array<Null<ComponentDefinition>> {

		loadResources();
		return definitions;
	}
}
