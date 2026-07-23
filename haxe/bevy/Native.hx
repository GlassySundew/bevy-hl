package bevy;

#if macro
typedef NativeWorld = Dynamic;

typedef NativeQuery = Dynamic;

typedef NativeInts = Dynamic;
typedef NativeValues = Dynamic;
#else
typedef NativeWorld = hl.Abstract<"bevy_world">;

typedef NativeQuery = hl.Abstract<"bevy_query">;

typedef NativeInts = hl.NativeArray<Int>;
typedef NativeValues = hl.NativeArray<Dynamic>;
#end

@:hlNative( "bevy" )
class Native {

	public static function bridge_version() : Int {

		return 0;
	}

	public static function world_new() : NativeWorld {

		return null;
	}

	public static function world_close( world : NativeWorld ) : Void {}

	public static function component_register(
		world : NativeWorld,
		bridgeId : Int,
		name : String,
		sparse : Bool
	) : Int {

		return -1;
	}

	public static function component_insert(
		world : NativeWorld,
		entity : Int,
		component : Int,
		value : Dynamic
	) : Bool {

		return false;
	}

	public static function component_get(
		world : NativeWorld,
		entity : Int,
		component : Int
	) : Dynamic {

		return null;
	}

	public static function component_has(
		world : NativeWorld,
		entity : Int,
		component : Int
	) : Bool {

		return false;
	}

	public static function component_remove(
		world : NativeWorld,
		entity : Int,
		component : Int
	) : Bool {

		return false;
	}

	public static function spawn(
		world : NativeWorld
	) : Int {

		return -1;
	}

	public static function entity_exists(
		world : NativeWorld,
		entity : Int
	) : Bool {

		return false;
	}

	public static function entity_generation(
		world : NativeWorld,
		entity : Int
	) : Int {

		return -1;
	}

	public static function despawn(
		world : NativeWorld,
		entity : Int
	) : Bool {

		return false;
	}

	public static function query_new(
		world : NativeWorld,
		required : NativeInts,
		excluded : NativeInts
	) : NativeQuery {

		return null;
	}

	public static function query_close(
		query : NativeQuery
	) : Void {}

	public static function query_refresh(
		world : NativeWorld,
		query : NativeQuery
	) : Bool {

		return false;
	}

	public static function query_fill_values(
		world : NativeWorld,
		query : NativeQuery,
		index : Int,
		out : NativeValues
	) : Int {

		return -1;
	}

	public static function query_len(
		query : NativeQuery
	) : Int {

		return 0;
	}

	public static function query_entity_at(
		query : NativeQuery,
		index : Int
	) : Int {

		return -1;
	}
}
