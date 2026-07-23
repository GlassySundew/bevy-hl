package bevy;

/** Runtime factory table populated by generated event descriptors. */
@:noCompletion
class EventCatalog {

	static final factories : Array<Void -> IEventChannel> = [];

	public static function registerFactory( id : Int, factory : Void -> IEventChannel ) : Bool {

		while ( factories.length <= id ) factories.push( null );
		factories[id] = factory;
		return true;
	}

	public static function createChannels() : Array<IEventChannel> {

		final channels : Array<IEventChannel> = [];
		for ( id in 0...factories.length ) {
			final factory = factories[id];
			if ( factory == null ) throw 'Missing event channel factory for id $id';
			channels.push( factory() );
		}
		return channels;
	}
}
