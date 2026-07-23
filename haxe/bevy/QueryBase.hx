package bevy;

import bevy.Native.NativeQuery;

#if macro
private typedef QueryNativeInts = Dynamic;
private typedef QueryNativeValues = Dynamic;
#else
private typedef QueryNativeInts = hl.NativeArray<Int>;
private typedef QueryNativeValues = hl.NativeArray<Dynamic>;
#end

/**
 * Persistent query specification. Entity access consumes a fresh native Bevy
 * snapshot, allowing the query object to survive arbitrary structural changes.
 */
class QueryBase {

	public final world : World;
	public final componentStorages : Array<DynamicComponentStorage>;
	public final excludeComponentStorage : Array<DynamicComponentStorage>;
	public final requiredComponentIds : Array<Int>;
	public final excludedComponentIds : Array<Int>;
	public var entities( get, never ) : Array<Entity>;
	public var length( get, never ) : Int;
	public var active( get, never ) : Bool;

	var activations : Int = 1;
	@:noCompletion final nativeQuery : NativeQuery;
	@:noCompletion final snapshotValues : QueryNativeValues;

	public function new(
		world : World,
		requiredComponentIds : Array<Int>,
		requiredTypeNames : Array<String>,
		excludedComponentIds : Array<Int>,
		excludedTypeNames : Array<String>
	) {
		this.world = world;
		this.requiredComponentIds = requiredComponentIds;
		this.excludedComponentIds = excludedComponentIds;
		for ( component in requiredComponentIds ) world.ensureComponentRegistered( component );
		for ( component in excludedComponentIds ) world.ensureComponentRegistered( component );
		componentStorages = [for ( i in 0...requiredComponentIds.length )
			new DynamicComponentStorage( world, requiredComponentIds[i], requiredTypeNames[i] )];
		excludeComponentStorage = [for ( i in 0...excludedComponentIds.length )
			new DynamicComponentStorage( world, excludedComponentIds[i], excludedTypeNames[i] )];
		nativeQuery = Native.query_new(
			world.nativeHandle,
			toNativeIds( requiredComponentIds ),
			toNativeIds( excludedComponentIds )
		);
		if ( nativeQuery == null ) throw 'Could not create query $this';
		snapshotValues = makeNativeValues( requiredComponentIds.length );
	}

	inline function get_active() : Bool return activations > 0;

	function get_entities() : Array<Entity> {
		if ( !active ) return [];
		refresh();
		final result : Array<Entity> = [];
		final count = Native.query_len( nativeQuery );
		for ( index in 0...count )
			result.push( new Entity( Native.query_entity_at( nativeQuery, index ) ) );
		return result;
	}

	function get_length() : Int {
		if ( !active ) return 0;
		refresh();
		final result = Native.query_len( nativeQuery );
		return result;
	}

	@:noCompletion public inline function refresh() : Void {
		if ( !Native.query_refresh( world.nativeHandle, nativeQuery ) )
			throw 'Could not refresh query $this';
	}

	@:noCompletion public inline function snapshotLength() : Int {
		return Native.query_len( nativeQuery );
	}

	@:noCompletion public inline function snapshotEntityAt( index : Int ) : Entity {
		return new Entity( Native.query_entity_at( nativeQuery, index ) );
	}

	/** Fills the reusable component row and returns its entity in one ABI call. */
	@:noCompletion public inline function snapshotFillAt( index : Int ) : Entity {
		final handle = Native.query_fill_values(
			world.nativeHandle,
			nativeQuery,
			index,
			snapshotValues
		);
		if ( handle < 0 ) throw 'Could not read query row $index from $this';
		return new Entity( handle );
	}

	@:noCompletion public inline function snapshotValueAt( index : Int ) : Dynamic {
		return snapshotValues[index];
	}

	static function toNativeIds( ids : Array<Int> ) : QueryNativeInts {
		#if macro
		return null;
		#else
		final result = new hl.NativeArray<Int>( ids.length );
		for ( index in 0...ids.length ) result[index] = ids[index];
		return result;
		#end
	}

	static function makeNativeValues( length : Int ) : QueryNativeValues {
		#if macro
		return null;
		#else
		return new hl.NativeArray<Dynamic>( length );
		#end
	}

	public function activate() : Void {

		activations++;
	}

	public function deactivate() : Void {

		if ( activations > 0 )
			activations--;
	}

	public function iterUntyped( callback : ( Entity, Any ) -> Void ) : Void {

		if ( !active ) return;
		refresh();
		final count = snapshotLength();
		for ( index in 0...count ) {
			final entity = snapshotFillAt( index );
			callback(
				entity,
				[for ( componentIndex in 0...componentStorages.length )
					snapshotValueAt( componentIndex )]
			);
		}
	}

	public inline function iter( callback : ( Entity, Array<Dynamic> ) -> Void ) : Void {
		iterUntyped( cast callback );
	}

	public function toString() : String {
		final required = componentStorages.map( storage -> storage.componentType ).join( ", " );
		final excluded = excludeComponentStorage.map( storage ->
			storage.componentType ).join( ", " );
		return excluded.length == 0 ? 'Query<$required>' : 'Query<$required without $excluded>';
	}
}
