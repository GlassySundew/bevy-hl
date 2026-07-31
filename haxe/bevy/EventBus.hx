package bevy;

/** World-owned event channels, indexed by compilation-server-stable event IDs. */
class EventBus {

	final channels : Array<Null<IEventChannel>>;

	public function new() {

		channels = EventCatalog.createChannels();
	}

	@:noCompletion
	public inline function channelUntyped(
		id : Int,
		?factory : Void -> IEventChannel
	) : IEventChannel {

		var channel = channels[id];
		if ( channel == null ) {
			channel = factory == null
				? EventCatalog.createChannel( id )
				: factory();
			while ( channels.length <= id ) channels.push( null );
			channels[id] = channel;
		}
		return channel;
	}

	@:allow( bevy.World )
	function advanceTick() : Void {

		for ( channel in channels )
			if ( channel != null ) channel.advanceTick();
	}

	@:allow( bevy.World )
	function clear() : Void {

		for ( channel in channels )
			if ( channel != null ) channel.clear();
	}
}
