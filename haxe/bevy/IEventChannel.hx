package bevy;

@:noCompletion
interface IEventChannel {
	public function advanceTick() : Void;
	public function clear() : Void;
}
