package bevy;

/** Stable entity reference containing the bridge handle and Bevy generation. */
@:struct
@:structInit
class EntityHandle {

	public var ent : Null<Entity>;
	public var gen : Int;

	public inline function toString() : String return 'ent : $ent, gen : $gen';
}
