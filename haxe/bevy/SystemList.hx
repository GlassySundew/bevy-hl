package bevy;

/** Ordered, nestable group of systems driven by its own clock. */
@:bevySkipSystemBuild
class SystemList extends System {

	public final clock : Clock;
	public var name : String;
	public var length( get, never ) : Int;
	public var paused( get, set ) : Bool;

	final systems : Array<System> = [];

	public function new( world : World, ?name : String = "SystemList", ?clock : Clock, ?priority : Int = 0 ) {

		super( world, priority );
		this.name = name;
		this.clock = clock == null ? new Clock() : clock;
	}

	public static function atRate(
		world : World,
		ticksPerSecond : Float,
		?name : String = "SystemList",
		?priority : Int = 0
	) : SystemList {

		final clock = new Clock();
		clock.setRate( ticksPerSecond );
		return new SystemList( world, name, clock, priority );
	}

	inline function get_length() : Int {

		return systems.length;
	}

	inline function get_paused() : Bool {

		return clock.paused;
	}

	inline function set_paused( value : Bool ) : Bool {

		return clock.paused = value;
	}

	override function __activate__() : Void {

		if ( !active ) {

			final activated : Array<System> = [];
			try {
				for ( system in systems ) {
					system.__activate__();
					activated.push( system );
				}
				super.__activate__();
			} catch ( error : haxe.Exception ) {
				while ( activated.length > 0 ) {
					try activated.pop().__deactivate__( SystemStopReason.ParentStopped )
					catch ( _ : haxe.Exception ) {}
				}
				throw error;
			}
		}
	}

	override function __deactivate__( ?reason : SystemStopReason = Removed ) : Void {

		if ( active ) {

			final childReason : SystemStopReason = switch reason {
				case SystemStopReason.WorldClosing: SystemStopReason.WorldClosing;
				default: SystemStopReason.ParentStopped;
			};
			var firstError : Null<haxe.Exception> = null;
			for ( system in systems ) {
				try system.__deactivate__( childReason ) catch ( error : haxe.Exception ) {
					if ( firstError == null ) firstError = error;
				}
			}
			try super.__deactivate__( reason ) catch ( error : haxe.Exception ) {
				if ( firstError == null ) firstError = error;
			}
			if ( firstError != null ) throw firstError;
		}
	}

	override function __update__( dt : Float ) : Void {

		super.__update__( dt );

		clock.addTime( dt );
		for ( step in clock ) {
			for ( system in systems ) {
				try {
					system.__update__( step );
				} catch ( error : haxe.Exception ) {
					world.__reportSystemError__( this, system, error, dt, step );
				}
			}
		}
	}

	public function add( system : System ) : SystemList {

		if ( system.world != world )
			throw 'Cannot attach $system to a SystemList from another world';
		if ( system == this )
			throw "A SystemList cannot contain itself";
		if ( Std.isOfType( system, SystemList ) && ( cast system : SystemList ).exists( this ) )
			throw "SystemList nesting cannot contain a cycle";
		if ( system.parent == this )
			return this;
		if ( system.parent != null )
			system.parent.remove( system, SystemStopReason.Reparented );

		final index = Lambda.findIndex( systems, existing -> existing.priority < system.priority );
		if ( index < 0 )
			systems.push( system );
		else
			systems.insert( index, system );
		system.parent = this;
		if ( active ) {
			try {
				system.__activate__();
			} catch ( error : Dynamic ) {
				systems.remove( system );
				system.parent = null;
				throw error;
			}
		}
		return this;
	}

	@:allow( bevy.System )
	function recalculateOrder( system : System ) : Void {

		if ( systems.remove( system ) ) {
			system.parent = null;
			add( system );
		}
	}

	public function remove( system : System, ?reason : SystemStopReason = Removed ) : SystemList {

		if ( systems.remove( system ) ) {

			var failure : Null<haxe.Exception> = null;
			try system.__deactivate__( reason ) catch ( error : haxe.Exception )
				failure = error;
			system.parent = null;
			if ( failure != null ) throw failure;
		}
		return this;
	}

	public function removeAll( ?reason : SystemStopReason = Removed ) : SystemList {

		var firstError : Null<haxe.Exception> = null;
		while ( systems.length > 0 ) {
			try remove( systems[systems.length - 1], reason ) catch ( error : haxe.Exception ) {
				if ( firstError == null ) firstError = error;
			}
		}
		if ( firstError != null ) throw firstError;
		return this;
	}

	public function exists( system : System ) : Bool {

		var current = system.parent;
		while ( current != null && current != this )
			current = current.parent;
		return current == this;
	}

	public function find<T : System>( type : Class<T> ) : Null<T> {

		for ( system in systems ) {
			if ( Std.isOfType( system, type ) )
				return cast system;
			if ( Std.isOfType( system, SystemList ) ) {
				final found = ( cast system : SystemList ).find( type );
				if ( found != null )
					return found;
			}
		}
		return null;
	}

	public inline function iterator() : Iterator<System> {

		return systems.iterator();
	}

	public inline function keyValueIterator() : KeyValueIterator<Int, System> {

		return systems.keyValueIterator();
	}

	override public function toString() : String {

		return '$name: $systems';
	}
}
