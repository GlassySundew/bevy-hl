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

/** Compiler-process-only component type to dense bridge-ID mapping. */
class ComponentTypeRegistry {

	static final components : Map<String, RegisteredComponent> = [];
	static var nextId : Int = 0;

	public static function register( type : Type, pos : Position ) : RegisteredComponent {

		final name = TypeTools.toString( type );
		final existing = components.get( name );
		if ( existing != null ) return existing;
		final complexType = TypeTools.toComplexType( type );
		if ( complexType == null ) Context.error( 'Unsupported component type $name', pos );
		final component : RegisteredComponent = {
			id : nextId++,
			name : name,
			type : type,
			complexType : complexType,
			sparse : hasSparseMetadata( type )
		};
		components.set( name, component );
		return component;
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
