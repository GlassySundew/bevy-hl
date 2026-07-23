package bevy;

/** World-owned event channels, indexed by dense compile-time IDs. */
class EventBus {

	final channels : Array<IEventChannel>;

	public function new() {

		channels = EventCatalog.createChannels();
	}

	@:noCompletion
	public inline function channelUntyped( id : Int ) : IEventChannel {

		final channel = channels[id];
		if ( channel == null )
			throw 'Event channel $id was not registered before the world was created';
		return channel;
	}

	@:allow( bevy.World )
	function advanceTick() : Void {

		for ( channel in channels ) channel.advanceTick();
	}

	@:allow( bevy.World )
	function clear() : Void {

		for ( channel in channels ) channel.clear();
	}
}
