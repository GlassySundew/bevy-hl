package bevy;

/** Runtime component access compatible with query.componentStorages[index]. */
class DynamicComponentStorage {

	public final storageId : Int;
	public final componentType : String;
	public final sparse : Bool;
	public var shortComponentType( get, never ) : String;
	final world : World;

	public function new(
		world : World,
		storageId : Int,
		componentType : String,
		?sparse : Bool = false
	) {

		this.world = world;
		this.storageId = storageId;
		this.componentType = componentType;
		this.sparse = sparse;
	}

	function get_shortComponentType() : String {

		final parts = componentType.split( "." );
		return parts[parts.length - 1];
	}

	public inline function get( entity : Entity ) : Dynamic {

		return world.getDynamic( entity, storageId );
	}

	public inline function exists( entity : Entity ) : Bool {

		return world.hasDynamic( entity, storageId );
	}

	public function add(
		entity : Entity,
		value : Dynamic,
		?ignoredWorld : World
	) : Dynamic {

		world.insertDynamic( entity, storageId, value );
		return value;
	}

	public inline function remove(
		entity : Entity,
		?ignoredWorld : World
	) : Bool {

		return world.removeDynamic( entity, storageId );
	}

	public function toString() : String {

		return componentType;
	}
}
