package bevy;

class SystemLifecycleSubscription {

	public var subscribed( default, null ) : Bool = true;

	final owner : System;
	@:allow( bevy.System )
	final callback : SystemLifecycleEvent -> Void;

	@:allow( bevy.System )
	function new( owner : System, callback : SystemLifecycleEvent -> Void ) {

		this.owner = owner;
		this.callback = callback;
	}

	public function unsubscribe() : Void {

		if ( subscribed ) {

			subscribed = false;
			owner.__removeLifecycleSubscription__( this );
		}
	}
}
