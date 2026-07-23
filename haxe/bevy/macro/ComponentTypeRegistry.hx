package bevy.macro;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import haxe.macro.TypeTools;

typedef RegisteredComponent = {
	final id : Int;
	final name : String;
	final type : Type;
	final complexType : ComplexType;
	final sparse : Bool;
}

/** Dense component IDs recovered from resources when compiler modules are reused. */
class ComponentTypeRegistry {

	static inline final RESOURCE_PREFIX = "bevy.component.dense.";

	public static function register( type : Type, pos : Position ) : RegisteredComponent {

		final name = TypeTools.toString( type );
		final resources = Context.getResources();
		var recoveredId : Null<Int> = null;
		final occupied : Map<Int, String> = [];
		for ( resource => bytes in resources ) {
			if ( !StringTools.startsWith( resource, RESOURCE_PREFIX ) ) continue;
			final id = resourceId( resource );
			final registeredName = descriptorName( bytes );
			if ( id == null || registeredName == null )
				Context.error( 'Invalid Bevy component resource $resource', pos );
			final occupiedName = occupied.get( id );
			if ( occupiedName != null && occupiedName != registeredName )
				Context.error(
					'Component ID $id is shared by $occupiedName and $registeredName',
					pos
				);
			occupied.set( id, registeredName );
			if ( registeredName == name ) {
				if ( recoveredId != null && recoveredId != id )
					Context.error( 'Component $name has IDs $recoveredId and $id', pos );
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
		return createAndBind( type, name, assignedId, pos );
	}

	static function createAndBind(
		type : Type,
		name : String,
		id : Int,
		pos : Position
	) : RegisteredComponent {

		final complexType = TypeTools.toComplexType( type );
		if ( complexType == null ) Context.error( 'Unsupported component type $name', pos );
		final component : RegisteredComponent = {
			id : id,
			name : name,
			type : type,
			complexType : complexType,
			sparse : hasSparseMetadata( type )
		};
		bindDescriptorResource( component );
		return component;
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

	static function descriptorName( bytes : Null<haxe.io.Bytes> ) : Null<String>
		return bytes == null || bytes.length == 0 ? null : bytes.toString().substr( 1 );

	static function bindDescriptorResource( component : RegisteredComponent ) : Void {

		Context.addResource(
			resourceName( component.id ),
			haxe.io.Bytes.ofString( ( component.sparse ? "1" : "0" ) + component.name )
		);
	}

	static function hasSparseMetadata( type : Type ) : Bool {

		return switch ( type ) {
			case TInst( ref, _ ):
				ref.get().meta.has( ":bevySparseSet" );
			case TEnum( ref, _ ):
				ref.get().meta.has( ":bevySparseSet" );
			case TAbstract( ref, _ ):
				ref.get().meta.has( ":bevySparseSet" );
			case TType( ref, _ ):
				ref.get().meta.has( ":bevySparseSet" )
				|| hasSparseMetadata( Context.follow( type ) );
			default: false;
		}
	}
}
#end
