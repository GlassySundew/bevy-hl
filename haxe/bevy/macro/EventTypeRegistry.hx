package bevy.macro;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import haxe.macro.TypeTools;

/** Compiler-process-only mapping from canonical event types to dense IDs. */
class EventTypeRegistry {

	static final ids : Map<String, Int> = [];

	public static function register( type : Type, pos : Position ) : Int {

		final key = TypeTools.toString( type );
		final existing = ids.get( key );
		if ( existing != null ) return existing;

		final complex = TypeTools.toComplexType( type );
		if ( complex == null ) Context.error( 'Cannot create an event channel for $key', pos );
		final id = Lambda.count( ids );
		ids.set( key, id );
		defineDescriptor( id, key, complex, pos );
		return id;
	}

	static function defineDescriptor(
		id : Int,
		typeName : String,
		eventType : ComplexType,
		pos : Position
	) : Void {

		final channelPath : TypePath = {
			pack: ["bevy"],
			name: "EventChannel",
			params: [TPType( eventType )]
		};
		final newChannel : Expr = { expr: ENew( channelPath, [] ), pos: pos };
		final initializer = macro bevy.EventCatalog.registerFactory(
			$v{id},
			function() : bevy.IEventChannel return $newChannel
		);
		Context.defineType( {
			pack: ["bevy", "generated"],
			name: 'EventType_$id',
			pos: pos,
			meta: [
				{name: ":keep", pos: pos},
				{name: ":keepInit", pos: pos}
			],
			kind: TDClass(),
			fields: [{
				name: "registered",
				access: [AStatic, AFinal],
				kind: FVar( macro:Bool, initializer ),
				pos: pos,
				meta: [{name: ":keep", pos: pos}]
			}],
			params: [],
			doc: 'Generated typed event channel descriptor for $typeName.'
		} );
	}
}
#end
