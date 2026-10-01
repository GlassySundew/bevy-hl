package bevy;

/** Optional runtime factory table for channels registered before a world starts. */
@:noCompletion
class EventCatalog {

	static final factories : Array<Void -> IEventChannel> = [];

	public static function registerFactory( id : Int, factory : Void -> IEventChannel ) : Bool {

		while ( factories.length <= id ) factories.push( null );
		factories[id] = factory;
		return true;
	}

	public static function createChannels() : Array<Null<IEventChannel>> {

		final channels : Array<Null<IEventChannel>> = [];
		for ( id in 0...factories.length ) {
			final factory = factories[id];
			channels.push( factory == null ? null : factory() );
		}
		return channels;
	}

	public static function createChannel( id : Int ) : IEventChannel {

		final factory = factories[id];
		if ( factory == null ) throw 'Missing event channel factory for id $id';
		return factory();
	}

	public static inline function factoryCount() : Int return factories.length;
}
