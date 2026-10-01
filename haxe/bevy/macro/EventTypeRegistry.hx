package bevy.macro;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr.Position;
import haxe.macro.Type;
import haxe.macro.TypeTools;

/** Dense event IDs recovered from resources when compiler modules are reused. */
class EventTypeRegistry {

	static inline final RESOURCE_PREFIX = "bevy.event.dense.";

	public static function register( type : Type, pos : Position ) : Int {

		final key = TypeTools.toString( type );
		if ( Context.defined( "display" ) )
			return DisplayTypeId.fromName( key );

		final resources = Context.getResources();
		var recoveredId : Null<Int> = null;
		final occupied : Map<Int, String> = [];
		for ( resource => bytes in resources ) {
			if ( !StringTools.startsWith( resource, RESOURCE_PREFIX ) ) continue;
			final id = resourceId( resource );
			final registeredName = bytes == null ? null : bytes.toString();
			if ( id == null || registeredName == null || registeredName.length == 0 )
				Context.error( 'Invalid Bevy event resource $resource', pos );
			final occupiedName = occupied.get( id );
			if ( occupiedName != null && occupiedName != registeredName )
				Context.error(
					'Event ID $id is shared by $occupiedName and $registeredName',
					pos
				);
			occupied.set( id, registeredName );
			if ( registeredName == key ) {
				if ( recoveredId != null && recoveredId != id )
					Context.error( 'Event $key has IDs $recoveredId and $id', pos );
				recoveredId = id;
			}
		}

		var assignedId : Int;
		if ( recoveredId != null ) {
			assignedId = recoveredId;
		} else {
			assignedId = 0;
			while ( occupied.exists( assignedId ) ) assignedId++;
		}
		Context.addResource(
			resourceName( assignedId ),
			haxe.io.Bytes.ofString( key )
		);
		return assignedId;
	}

	static function resourceId( resource : String ) : Null<Int> {

		final suffix = resource.substr( RESOURCE_PREFIX.length );
		final separator = suffix.indexOf( "." );
		return Std.parseInt( separator < 0 ? suffix : suffix.substr( 0, separator ) );
	}

	static function resourceName( id : Int ) : String {

		final module = Context.getLocalModule();
		final moduleId = haxe.crypto.Crc32.make( haxe.io.Bytes.ofString( module ) );
		return RESOURCE_PREFIX + id + "." + StringTools.hex( moduleId, 8 );
	}
}
#end
