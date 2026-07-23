package bevy;

#if macro
import haxe.macro.Expr;
import bevy.macro.WorldMacro;
import bevy.macro.EventMacro;
#end

#if !macro
@:autoBuild( bevy.macro.SystemBuilder.build() )
#end
class System {

	public final world : World;
	public var active( default, null ) : Bool = false;
	public var lifecycleState( default, null ) : SystemLifecycleState = Inactive;
	public final lifetime : SystemLifetime;
	public final deferredQueue : Array<Void -> Void> = [];
	public var parent( default, null ) : SystemList;
	public var priority( default, set ) : Int;
	public var dt( default, null ) : Float = 0;
	public var resourceTypes( get, never ) : Array<String>;
	@:noCompletion final __eventSubscriptions : Array<IEventSubscription> = [];
	@:noCompletion final __lifecycleSubscriptions : Array<SystemLifecycleSubscription> = [];
	var eventHandlersConfigured : Bool = false;

	public function new( world : World, ?priority : Int ) {

		this.world = world;
		lifetime = new SystemLifetime();
		this.priority = priority == null ? __getDefaultPriority__() : priority;
	}

	function set_priority( value : Int ) : Int {

		priority = value;
		if ( parent != null )
			parent.recalculateOrder( this );

		return value;
	}

	inline function get_resourceTypes() : Array<String> return __resourceTypeNames__();

	@:allow( bevy.SystemList )
	@:allow( bevy.World )
	function __activate__() : Void {

		if ( !active ) {

			lifecycleState = Activating;
			lifetime.begin();
			try {
				__injectResources__();
				__initializeQueries__();

				if ( !eventHandlersConfigured ) {

					eventHandlersConfigured = true;
					__registerEventHandlers__();
				}
				for ( subscription in __eventSubscriptions )
					subscription.activate();
				onActivate();
				active = true;
				lifecycleState = Active;
				__dispatchLifecycle__( Started );
			} catch ( exception : haxe.Exception ) {
				__finishDeactivation__( ActivationFailed( exception ), false );
				throw exception;
			}
		}
	}

	@:allow( bevy.SystemList )
	@:allow( bevy.World )
	function __deactivate__( ?reason : SystemStopReason = Removed ) : Void {

		if ( active ) {

			final failure = __finishDeactivation__( reason, true );
			if ( failure != null )
				throw failure;
		}
	}

	function __finishDeactivation__( reason : SystemStopReason, callLegacyHook : Bool ) : Null<haxe.Exception> {

		lifecycleState = Deactivating;
		active = false;
		var firstError : Null<haxe.Exception> = null;
		for ( subscription in __eventSubscriptions )
			subscription.deactivate();
		try onStop( reason ) catch ( error : haxe.Exception )
			firstError = error;
		if ( callLegacyHook ) {
			try onDeactivate() catch ( error : haxe.Exception ) {
				if ( firstError == null ) firstError = error;
			}
		}
		final cleanupError = lifetime.close();
		if ( firstError == null ) firstError = cleanupError;
		lifecycleState = Inactive;
		final observerError = __dispatchLifecycle__( Stopped( reason ) );
		if ( firstError == null ) firstError = observerError;
		return firstError;
	}

	@:allow( bevy.SystemList )
	@:allow( bevy.World )
	function __update__( dt : Float ) : Void {

		this.dt = dt;
		for ( subscription in __eventSubscriptions )
			subscription.drain();
	}

	function __registerEventHandlers__() : Void {}
	function __injectResources__() : Void {}
	function __initializeQueries__() : Void {}
	function __resourceTypeNames__() : Array<String> return [];

	function __flushDeferred__() : Void {

		while ( deferredQueue.length > 0 ) {
			final callback = deferredQueue.shift();
			if ( callback != null ) callback();
		}
	}

	@:noCompletion
	function __addEventSubscription__( subscription : IEventSubscription ) : Void {

		__eventSubscriptions.push( subscription );
	}

	function __getDefaultPriority__() : Int {

		return 0;
	}

	public dynamic function onActivate() : Void {}
	/** Reason-aware deactivation hook. Prefer this over the legacy onDeactivate(). */
	public dynamic function onStop( reason : SystemStopReason ) : Void {}
	/** Legacy zero-argument hook retained for migration. */
	public dynamic function onDeactivate() : Void {}

	/** Observes lifecycle transitions. The returned subscription must be retained to unsubscribe. */
	public function observeLifecycle( callback : SystemLifecycleEvent -> Void ) : SystemLifecycleSubscription {

		final subscription = new SystemLifecycleSubscription( this, callback );
		__lifecycleSubscriptions.push( subscription );
		return subscription;
	}

	@:allow( bevy.SystemLifecycleSubscription )
	function __removeLifecycleSubscription__( subscription : SystemLifecycleSubscription ) : Void {

		__lifecycleSubscriptions.remove( subscription );
	}

	function __dispatchLifecycle__( event : SystemLifecycleEvent ) : Null<haxe.Exception> {

		var firstError : Null<haxe.Exception> = null;
		for ( subscription in __lifecycleSubscriptions.copy() ) {
			if ( !subscription.subscribed ) continue;
			try subscription.callback( event ) catch ( error : haxe.Exception ) {
				if ( firstError == null ) firstError = error;
			}
		}
		return firstError;
	}

	/** Convenience helpers kept close to Echoes system code for migration. */
	function createEntity() : Entity {

		return world.spawn();
	}

	function destroyEntity( entity : Entity ) : Entity {

		world.despawn( entity );
		return entity;
	}

	/** Echoes migration helper delegated to this system's world. */
	function isHandleValid(
		handle : Null<EntityHandle>
	) : Bool {

		return world.isHandleValid( handle );
	}

	function getGen( entity : Entity ) : Int return world.getGen( entity );

	function makeHandle( entity : Entity ) : EntityHandle return world.makeHandle( entity );

	private #if !macro macro #else static #end function addComponent(
		ethis : ExprOf<System>,
		entity : ExprOf<Entity>,
		components : Array<Expr>
	) : ExprOf<Entity> {

		final target = macro __bevyEntity;
		final operations = [for ( component in components ) WorldMacro.add( macro $ethis.world, target, component )];
		return macro {
			final __bevyEntity:bevy.Entity = $entity;
			$b{operations};
			__bevyEntity;
		};
	}

	private #if !macro macro #else static #end function getComponent<T>(
		ethis : ExprOf<System>,
		entity : ExprOf<Entity>,
		componentType : ExprOf<Class<T>>
	) : ExprOf<Null<T>> {

		return WorldMacro.get( macro $ethis.world, entity, componentType );
	}

	private #if !macro macro #else static #end function hasComponent<T>(
		ethis : ExprOf<System>,
		entity : ExprOf<Entity>,
		componentType : ExprOf<Class<T>>
	) : ExprOf<Bool> {

		return WorldMacro.has( macro $ethis.world, entity, componentType );
	}

	private #if !macro macro #else static #end function removeComponent(
		ethis : ExprOf<System>,
		entity : ExprOf<Entity>,
		componentTypes : Array<Expr>
	) : ExprOf<Entity> {

		final target = macro __bevyEntity;
		final operations = [for ( componentType in componentTypes ) WorldMacro.remove( macro $ethis.world, target, componentType )];
		return macro {
			final __bevyEntity:bevy.Entity = $entity;
			$b{operations};
			__bevyEntity;
		};
	}

	private #if !macro macro #else static #end function emitEvent<T>(
		ethis : ExprOf<System>,
		event : ExprOf<T>,
		?tickOffset : ExprOf<Int>
	) : ExprOf<T> {

		return EventMacro.send( macro $ethis.world, event, tickOffset );
	}

	public inline function activate() : Void {

		world.activeSystems.add( this );
	}

	public function deactivate() : Void {

		if ( parent != null )
			parent.remove( this );
	}

	public function toString() : String {

		return Type.getClassName( Type.getClass( this ) );
	}
}
