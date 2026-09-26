package bevy.macro;

#if macro
class DisplayTypeId {

	public static function fromName( name : String ) : Int {

		return haxe.crypto.Crc32.make( haxe.io.Bytes.ofString( name ) ) & 0x7FFFFFFF;
	}
}
#end
