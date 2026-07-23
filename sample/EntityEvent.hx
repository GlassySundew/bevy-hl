import bevy.EntityHandle;

class EntityEvent {
	public final entityHandle : EntityHandle;
	public final value : Int;

	public function new( entityHandle : EntityHandle, value : Int ) {
		this.entityHandle = entityHandle;
		this.value = value;
	}
}
