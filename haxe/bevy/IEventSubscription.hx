package bevy;

@:noCompletion
interface IEventSubscription {
	public var active( default, null ) : Bool;
	public function activate() : Void;
	public function deactivate() : Void;
	public function drain() : Void;
	public function clear() : Void;
}
