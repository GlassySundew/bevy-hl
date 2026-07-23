package bevy;

import bevy.Native.NativeWorld;
#if macro
import haxe.macro.Expr;
import bevy.macro.WorldMacro;
import bevy.macro.EventMacro;
import bevy.macro.ResourceMacro;
#end

class World {

	public final activeSystems : SystemList;
	public final resources : ResourceStore;
	public final updateErrors : Array<SystemExecutionError> = [];

	@:noCompletion
	public final eventBus : EventBus;

	public var hasUpdateErrors( get, never ) : Bool;
	public var activeEntities( get, never ) : Array<Entity>;
	public var lastUpdate : Float = haxe.Timer.stamp();

	@:noCompletion
	public var nativeHandle( default, null ) : NativeWorld;

	final registeredComponentStorages : Array<Null<DynamicComponentStorage>> = [];

	var closed : Bool = false;

	public function new() {

		nativeHandle = Native.world_new();
		if ( nativeHandle == null )
			throw "Could not create Bevy world";
		synchronizeComponentCatalog();
		eventBus = new EventBus();
		resources = new ResourceStore();
		activeSystems = new SystemList( this, "ActiveSystems" );
		activeSystems.__activate__();
	}

	inline function get_hasUpdateErrors() : Bool return updateErrors.length > 0;
	inline function get_activeEntities() : Array<Entity> return entities();

	public function update( ?dt : Float ) : Void {

		ensureOpen();
		final now = haxe.Timer.stamp();
		final elapsed = dt == null ? now - lastUpdate : dt;
		lastUpdate = now;
		updateErrors.resize( 0 );
		try activeSystems.__update__( Math.max( 0, elapsed ) ) catch( error : haxe.Exception ) {
			eventBus.advanceTick();
			throw error;
		}
		eventBus.advanceTick();
	}

	@:allow( bevy.SystemList )
	function __reportSystemError__(
		systemList : SystemList,
		system : System,
		error : haxe.Exception,
		deltaTime : Float,
		step : Float
	) : Void {

		updateErrors.push( {
			systemName : Std.string( system ),
			systemListName : systemList.name,
			error : error,
			deltaTime : deltaTime,
			step : step
		} );
	}

	public #if !macro macro #else static #end function send<T>(
		ethis : ExprOf<World>,
		event : ExprOf<T>,
		?tickOffset : ExprOf<Int>
	) : ExprOf<T> {

		return EventMacro.send( ethis, event, tickOffset );
	}

	public #if !macro macro #else static #end function insertResource<T>(
		ethis : ExprOf<World>, resourceType : ExprOf<Class<T>>, value : ExprOf<T>
	) : ExprOf<T> {

		return ResourceMacro.insert( ethis, resourceType, value );
	}

	/** Returns a resource, throwing a descriptive error when it is absent. */
	public #if !macro macro #else static #end function resource<T>(
		ethis : ExprOf<World>, resourceType : ExprOf<Class<T>>
	) : ExprOf<T> {

		return ResourceMacro.get( ethis, resourceType, true );
	}

	public #if !macro macro #else static #end function tryResource<T>(
		ethis : ExprOf<World>, resourceType : ExprOf<Class<T>>
	) : ExprOf<Null<T>> {

		return ResourceMacro.get( ethis, resourceType, false );
	}

	public #if !macro macro #else static #end function hasResource<T>(
		ethis : ExprOf<World>, resourceType : ExprOf<Class<T>>
	) : ExprOf<Bool> {

		return ResourceMacro.has( ethis, resourceType );
	}

	public #if !macro macro #else static #end function removeResource<T>(
		ethis : ExprOf<World>, resourceType : ExprOf<Class<T>>
	) : ExprOf<Null<T>> {

		return ResourceMacro.remove( ethis, resourceType );
	}

	/** Echoes-compatible resource aliases. */
	public #if !macro macro #else static #end function setService<T>(
		ethis : ExprOf<World>, resourceType : ExprOf<Class<T>>, value : ExprOf<T>
	) : ExprOf<T> {

		return ResourceMacro.insert( ethis, resourceType, value );
	}

	public #if !macro macro #else static #end function getService<T>(
		ethis : ExprOf<World>, resourceType : ExprOf<Class<T>>
	) : ExprOf<T> {

		return ResourceMacro.get( ethis, resourceType, true );
	}

	public function close() : Void {

		if ( !closed ) {

			var lifecycleError : Null<haxe.Exception> = null;
			try activeSystems.removeAll( SystemStopReason.WorldClosing )
			catch( error : haxe.Exception )
				lifecycleError = error;
			try activeSystems.__deactivate__( SystemStopReason.WorldClosing )
			catch( error : haxe.Exception ) {
				if ( lifecycleError == null ) lifecycleError = error;
			}
			eventBus.clear();
			resources.clear();
			Native.world_close( nativeHandle );
			closed = true;
			if ( lifecycleError != null ) throw lifecycleError;
		}
	}

	public inline function spawn() : Entity {

		ensureOpen();
		return new Entity( Native.spawn( nativeHandle ) );
	}

	public inline function entityExists( entity : Entity ) : Bool {

		return !closed && Native.entity_exists( nativeHandle, entity.handle );
	}

	/** Validates both liveness and the captured native Bevy generation. */
	public inline function isHandleValid(
		handle : Null<EntityHandle>
	) : Bool {

		return handle != null && handle.ent != null
			&& Native.entity_generation( nativeHandle, handle.ent.handle ) == handle.gen;
	}

	/** Validates both liveness and the captured native Bevy generation. */
	public inline function isEntityValid(
		entity : Null<Entity>,
		gen : Null<Int>
	) : Bool {

		return entity != null && gen != null
			&& Native.entity_generation( nativeHandle, entity.handle ) == gen;
	}

	public inline function getGen( entity : Entity ) : Int {

		ensureOpen();
		return Native.entity_generation( nativeHandle, entity.handle );
	}

	public inline function makeHandle( entity : Entity ) : EntityHandle {

		return { ent : entity, gen : getGen( entity ) };
	}

	public inline function despawn( entity : Entity ) : Bool {

		ensureOpen();
		return Native.despawn( nativeHandle, entity.handle );
	}

	/** Returns a fresh snapshot of every currently live entity in this world. */
	public function entities() : Array<Entity> {

		#if macro
		return [];
		#else
		ensureOpen();
		final emptyRequired = new hl.NativeArray<Int>( 0 );
		final emptyExcluded = new hl.NativeArray<Int>( 0 );
		final query = Native.query_new( nativeHandle, emptyRequired, emptyExcluded );
		if ( query == null )
			throw "Could not create Bevy entity inspection query";
		final result = new Array<Entity>();
		final length = Native.query_len( query );
		for ( index in 0...length )
			result.push( new Entity( Native.query_entity_at( query, index ) ) );
		Native.query_close( query );
		return result;
		#end
	}

	/** Returns registered component views currently present on an entity. */
	public function componentsOf( entity : Entity ) : Array<DynamicComponentStorage> {

		ensureOpen();
		synchronizeComponentCatalog();
		if ( !entityExists( entity ) ) return [];
		final result = new Array<DynamicComponentStorage>();
		for ( storage in registeredComponentStorages )
			if ( storage != null && storage.exists( entity ) ) result.push( storage );
		return result;
	}

	@:noCompletion public inline function insertDynamic(
		entity : Entity,
		component : Int,
		value : Dynamic
	) : Void {

		ensureOpen();
		if ( !Native.component_insert( nativeHandle, entity.handle, component, value ) )
			throw 'Could not insert component $component into $entity';
	}

	@:noCompletion public inline function getDynamic(
		entity : Entity,
		component : Int
	) : Dynamic {

		ensureOpen();
		return Native.component_get( nativeHandle, entity.handle, component );
	}

	@:noCompletion public inline function hasDynamic(
		entity : Entity,
		component : Int
	) : Bool {

		ensureOpen();
		return Native.component_has( nativeHandle, entity.handle, component );
	}

	@:noCompletion public inline function removeDynamic( entity : Entity, component : Int ) : Bool {

		ensureOpen();
		return Native.component_remove( nativeHandle, entity.handle, component );
	}

	/** Registers every component descriptor generated for this binary. */
	@:noCompletion public function synchronizeComponentCatalog() : Void {

		ensureOpen();
		for ( id => definition in ComponentCatalog.all() )
			if ( definition != null && registeredComponentId( id ) < 0 )
				registerComponent( id, definition.name, definition.sparse );
	}

	/** Registers a macro-assigned component ID once in this native world. */
	@:noCompletion public function registerComponent(
		compileId : Int,
		name : String,
		sparse : Bool
	) : Int {

		ensureOpen();
		if ( compileId < 0 ) throw 'Invalid component id $compileId for $name';
		final existing = compileId < registeredComponentStorages.length
			? registeredComponentStorages[compileId]
			: null;
		if ( existing != null ) {
			if ( existing.componentType != name || existing.sparse != sparse )
				throw 'Component id $compileId is already registered as ${existing.componentType}';
			return existing.storageId;
		}
		final registered = Native.component_register(
			nativeHandle, compileId, name, sparse
		);
		if ( registered != compileId )
			throw 'Could not register component $name at bridge id $compileId';
		final storage = new DynamicComponentStorage( this, registered, name, sparse );
		while ( registeredComponentStorages.length <= compileId )
			registeredComponentStorages.push( null );
		registeredComponentStorages[compileId] = storage;
		return registered;
	}

	/** Returns a cached native ID, or -1 when this world has not registered it. */
	@:noCompletion public function registeredComponentId( compileId : Int ) : Int {

		final storage = compileId >= 0 && compileId < registeredComponentStorages.length
			? registeredComponentStorages[compileId]
			: null;
		return storage == null ? -1 : storage.storageId;
	}

	/** Validates a macro-assigned ID before native component access. */
	@:noCompletion public function ensureComponentRegistered( component : Int ) : Void {

		ensureOpen();
		if ( component < 0 ) throw 'Invalid component id $component';
		if ( registeredComponentId( component ) < 0 ) {
			final definition = ComponentCatalog.get( component );
			if ( definition != null )
				registerComponent( component, definition.name, definition.sparse );
		}
		if ( registeredComponentId( component ) < 0 )
			throw 'Component id $component is not registered in this world';
	}

	public #if !macro macro #else static #end function add<T>(
		ethis : ExprOf<World>,
		entity : ExprOf<Entity>,
		component : ExprOf<T>
	) : ExprOf<T> {

		return WorldMacro.add( ethis, entity, component );
	}

	public #if !macro macro #else static #end function get<T>(
		ethis : ExprOf<World>,
		entity : ExprOf<Entity>,
		componentType : ExprOf<Class<T>>
	) : ExprOf<Null<T>> {

		return WorldMacro.get( ethis, entity, componentType );
	}

	public #if !macro macro #else static #end function has<T>(
		ethis : ExprOf<World>,
		entity : ExprOf<Entity>,
		componentType : ExprOf<Class<T>>
	) : ExprOf<Bool> {

		return WorldMacro.has( ethis, entity, componentType );
	}

	public #if !macro macro #else static #end function remove<T>(
		ethis : ExprOf<World>,
		entity : ExprOf<Entity>,
		componentType : ExprOf<Class<T>>
	) : ExprOf<Bool> {

		return WorldMacro.remove( ethis, entity, componentType );
	}

	/**
	 * Iterates a snapshot matching every required type and none of the excluded
	 * types. Component values follow the entity argument in required-list order.
	 *
	 *     world.each([Position, Velocity], (entity, position, velocity) -> ...);
	 *     world.each([Position], callback, [Sleeping]);
	 */
	public #if !macro macro #else static #end function each(
		ethis : ExprOf<World>,
		required : Expr,
		callback : Expr,
		?excluded : Expr
	) : ExprOf<Void> {

		return WorldMacro.each( ethis, required, callback, excluded );
	}

	/** Creates a reusable specification backed by fresh Bevy snapshots. */
	public #if !macro macro #else static #end function getQuery(
		ethis : ExprOf<World>,
		required : Expr,
		?excluded : Expr
	) : ExprOf<QueryBase> {

		return WorldMacro.query( ethis, required, excluded );
	}

	/** Short alias for getQuery(). */
	public #if !macro macro #else static #end function query(
		ethis : ExprOf<World>,
		required : Expr,
		?excluded : Expr
	) : ExprOf<QueryBase> {

		return WorldMacro.query( ethis, required, excluded );
	}

	inline function ensureOpen() : Void {

		if ( closed )
			throw "Bevy world is closed";
	}
}

typedef SystemExecutionError = {
	var systemName : String;
	var systemListName : String;
	var error : haxe.Exception;
	var deltaTime : Float;
	var step : Float;
};
