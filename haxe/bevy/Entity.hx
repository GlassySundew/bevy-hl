package bevy;

#if macro
import haxe.macro.Expr;
import bevy.macro.WorldMacro;
#end

/** Opaque, generational Bevy entity identifier. */
abstract Entity( Int ) from Int to Int {

	public var handle( get, never ) : Int;
	inline function get_handle() : Int {

		return this;
	}

	/** Echoes migration alias. Bridge handles are opaque, not dense IDs. */
	public var id( get, never ) : Int;
	inline function get_id() : Int {

		return this;
	}

	public inline function new( handle : Int ) {

		this = handle;
	}

	public #if !macro macro #else static #end function exists(
		ethis : ExprOf<Entity>, world : ExprOf<World>, ?componentType : Expr
	) : ExprOf<Bool> {

		if ( componentType == null || switch componentType.expr {
			case EConst( CIdent( "null" ) ): true;
			default: false;
		} ) return macro $world.entityExists( $ethis );
		return WorldMacro.has( world, ethis, componentType );
	}

	public #if !macro macro #else static #end function add(
		ethis : ExprOf<Entity>, world : ExprOf<World>, components : Array<Expr>
	) : ExprOf<Entity> {

		final entity = macro __bevyEntity;
		final targetWorld = macro __bevyWorld;
		final operations = [for ( component in components ) WorldMacro.add( targetWorld, entity, component )];
		return macro {
			final __bevyEntity:bevy.Entity = $ethis;
			final __bevyWorld:bevy.World = $world;
			$b{operations};
			__bevyEntity;
		};
	}

	public #if !macro macro #else static #end function addIfMissing(
		ethis : ExprOf<Entity>, world : ExprOf<World>, components : Array<Expr>
	) : ExprOf<Entity> {

		final entity = macro __bevyEntity;
		final targetWorld = macro __bevyWorld;
		final operations = [for ( component in components ) WorldMacro.addIfMissing( targetWorld, entity, component )];
		return macro {
			final __bevyEntity:bevy.Entity = $ethis;
			final __bevyWorld:bevy.World = $world;
			$b{operations};
			__bevyEntity;
		};
	}

	public #if !macro macro #else static #end function get<T>(
		ethis : ExprOf<Entity>, world : ExprOf<World>, componentType : ExprOf<Class<T>>
	) : ExprOf<Null<T>> {

		return WorldMacro.get( world, ethis, componentType );
	}

	public #if !macro macro #else static #end function remove(
		ethis : ExprOf<Entity>, world : ExprOf<World>, componentTypes : Array<Expr>
	) : ExprOf<Entity> {

		final entity = macro __bevyEntity;
		final targetWorld = macro __bevyWorld;
		final operations = [for ( componentType in componentTypes ) WorldMacro.remove( targetWorld, entity, componentType )];
		return macro {
			final __bevyEntity:bevy.Entity = $ethis;
			final __bevyWorld:bevy.World = $world;
			$b{operations};
			__bevyEntity;
		};
	}
	public inline function despawn( world : World ) : Bool {

		return world.despawn( cast this );
	}

	public inline function isDestroyed( world : World ) : Bool {

		return !world.entityExists( cast this );
	}

	public function toString() : String {

		return 'Entity($this)';
	}
}
